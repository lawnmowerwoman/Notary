import Foundation

private let sshdConfigPath = "/etc/ssh/sshd_config"
private let sshdConfigDirectory = "/etc/ssh/sshd_config.d"
private let sshdManagedConfigPath = "/etc/ssh/sshd_config.d/01-notary-sshd.conf"
private let sshdBannerPath = "/etc/ssh/sshd_notary_banner"
private let sshdIncludeDirective = "Include /etc/ssh/sshd_config.d/*"

private enum SSHConfigRead {
    case success([String: String])
    case failure(CheckResult)
}

private func sshdEffectiveSettings(logger: HardenLogger) -> SSHConfigRead {
    do {
        let result = try Shell.run("/usr/sbin/sshd", ["-G"], timeout: 10, logger: logger)

        if result.didTimeout {
            return .failure(
                .init(
                    name: "SSH",
                    status: .timedOut,
                    details: Shell.detailsForReport(
                        command: "/usr/sbin/sshd",
                        args: ["-G"],
                        result: result,
                        timeout: 10
                    )
                )
            )
        }

        if result.code != 0 || result.stdout.isEmpty {
            return .failure(
                .init(
                    name: "SSH",
                    status: .unknown,
                    details: Shell.failureDetailsForReport(
                        command: "/usr/sbin/sshd",
                        args: ["-G"],
                        result: result,
                        timeout: 10
                    )
                )
            )
        }

        var settings: [String: String] = [:]
        for rawLine in result.stdout.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }

            settings[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return .success(settings)
    } catch {
        return .failure(.init(name: "SSH", status: .unknown, details: "sshd -G error: \(error)"))
    }
}

private enum SSHConfigValueRead {
    case success(String)
    case failure(CheckResult)
}

private func sshdConfigValue(_ key: String, logger: HardenLogger) -> SSHConfigValueRead {
    switch sshdEffectiveSettings(logger: logger) {
    case .success(let settings):
        guard let value = settings[key.lowercased()] else {
            return .failure(.init(name: "SSH", status: .unknown, details: "effective sshd config missing key \(key)"))
        }
        return .success(value)
    case .failure(let result):
        return .failure(result)
    }
}

func checkSSHPasswordAuthenticationDisabled(logger: HardenLogger) -> CheckResult {
    switch sshdEffectiveSettings(logger: logger) {
    case .success(let settings):
        let password = settings["passwordauthentication"]?.lowercased()
        let keyboard = settings["kbdinteractiveauthentication"]?.lowercased()

        if password == "no", keyboard == "no" {
            return .init(
                name: "SSH Password Authentication",
                status: .pass,
                details: "passwordauthentication=no and kbdinteractiveauthentication=no"
            )
        }

        return .init(
            name: "SSH Password Authentication",
            status: .fail,
            details: "passwordauthentication=\(password ?? "unknown"), kbdinteractiveauthentication=\(keyboard ?? "unknown")"
        )
    case .failure(let result):
        return .init(name: "SSH Password Authentication", status: result.status, details: result.details)
    }
}

func checkSSHClientAliveInterval(expectedSeconds: Int, logger: HardenLogger) -> CheckResult {
    switch sshdConfigValue("clientaliveinterval", logger: logger) {
    case .success(let value):
        if value == String(expectedSeconds) {
            return .init(
                name: "SSH Client Alive Interval",
                status: .pass,
                details: "clientaliveinterval=\(value)"
            )
        }
        return .init(
            name: "SSH Client Alive Interval",
            status: .fail,
            details: "clientaliveinterval=\(value), expected \(expectedSeconds)"
        )
    case .failure(let result):
        return .init(name: "SSH Client Alive Interval", status: result.status, details: result.details)
    }
}

func checkSSHClientAliveCountMax(expectedCount: Int, logger: HardenLogger) -> CheckResult {
    switch sshdConfigValue("clientalivecountmax", logger: logger) {
    case .success(let value):
        if value == String(expectedCount) {
            return .init(
                name: "SSH Client Alive Count Max",
                status: .pass,
                details: "clientalivecountmax=\(value)"
            )
        }
        return .init(
            name: "SSH Client Alive Count Max",
            status: .fail,
            details: "clientalivecountmax=\(value), expected \(expectedCount)"
        )
    case .failure(let result):
        return .init(name: "SSH Client Alive Count Max", status: result.status, details: result.details)
    }
}

func checkSSHLoginBanner(expectedText: String, logger: HardenLogger) -> CheckResult {
    switch sshdConfigValue("banner", logger: logger) {
    case .success(let value):
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.lowercased() == "none" || path.isEmpty {
            return .init(
                name: "SSH Login Banner",
                status: .fail,
                details: "sshd banner is disabled."
            )
        }

        guard let banner = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .init(
                name: "SSH Login Banner",
                status: .fail,
                details: "sshd banner file could not be read at \(path)."
            )
        }

        if banner.trimmingCharacters(in: .whitespacesAndNewlines) == expectedText.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .init(
                name: "SSH Login Banner",
                status: .pass,
                details: "sshd shows the configured banner from \(path)."
            )
        }

        return .init(
            name: "SSH Login Banner",
            status: .fail,
            details: "sshd banner content differs from the configured banner."
        )
    case .failure(let result):
        return .init(name: "SSH Login Banner", status: result.status, details: result.details)
    }
}

private func ensureSSHDIncludeDirectory(logger: HardenLogger) throws {
    let fm = FileManager.default

    if !fm.fileExists(atPath: sshdConfigDirectory) {
        try fm.createDirectory(atPath: sshdConfigDirectory, withIntermediateDirectories: true, attributes: nil)
        logger.info("[ENFORCE] SSH created \(sshdConfigDirectory)")
    }

    let configURL = URL(fileURLWithPath: sshdConfigPath)
    let original = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
    if original.contains(sshdIncludeDirective) {
        return
    }

    let updated = sshdIncludeDirective + "\n" + original
    try updated.write(to: configURL, atomically: true, encoding: .utf8)
    logger.info("[ENFORCE] SSH inserted include directive into \(sshdConfigPath)")
}

private func currentManagedSSHDDirectives() -> [String: String] {
    guard let raw = try? String(contentsOfFile: sshdManagedConfigPath, encoding: .utf8) else {
        return [:]
    }

    var directives: [String: String] = [:]
    for rawLine in raw.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }

        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { continue }
        directives[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return directives
}

private func writeManagedSSHDDirectives(_ directives: [String: String], logger: HardenLogger) throws {
    let orderedKeys = directives.keys.sorted()
    let content = orderedKeys.map { key in
        "\(key) \(directives[key] ?? "")"
    }.joined(separator: "\n") + "\n"

    try content.write(toFile: sshdManagedConfigPath, atomically: true, encoding: .utf8)
    logger.info("[ENFORCE] SSH wrote managed directives to \(sshdManagedConfigPath)")
}

private func refreshSSHDServiceIfLoaded(logger: HardenLogger) {
    guard let state = try? Shell.run("/bin/launchctl", ["print", "system/com.openssh.sshd"], timeout: 5, logger: logger) else {
        return
    }

    let combined = [state.stdout, state.stderr].joined(separator: "\n").lowercased()
    if combined.contains("could not find service") || combined.contains("could not find") {
        return
    }

    if let refresh = try? Shell.run("/bin/launchctl", ["kickstart", "-k", "system/com.openssh.sshd"], timeout: 10, logger: logger) {
        logger.info("[ENFORCE] SSH kickstart code=\(refresh.code) out=\(refresh.stdout) err=\(refresh.stderr)")
    }
}

private func enforceSSHDDirectives(
    directives newDirectives: [String: String],
    logger: HardenLogger
) -> CheckResult {
    guard geteuid() == 0 else {
        return .init(name: "SSH", status: .fail, details: "enforce requires admin/root")
    }

    do {
        try ensureSSHDIncludeDirectory(logger: logger)

        var directives = currentManagedSSHDDirectives()
        for (key, value) in newDirectives {
            directives[key.lowercased()] = value
        }
        try writeManagedSSHDDirectives(directives, logger: logger)
        refreshSSHDServiceIfLoaded(logger: logger)
        return .init(name: "SSH", status: .pass, details: "managed sshd directives updated")
    } catch {
        return .init(name: "SSH", status: .unknown, details: "sshd config enforce error: \(error)")
    }
}

func enforceSSHPasswordAuthenticationDisabled(logger: HardenLogger) -> CheckResult {
    let result = enforceSSHDDirectives(
        directives: [
            "passwordauthentication": "no",
            "kbdinteractiveauthentication": "no"
        ],
        logger: logger
    )

    guard result.status == .pass else {
        return .init(name: "SSH Password Authentication", status: result.status, details: result.details)
    }

    let post = checkSSHPasswordAuthenticationDisabled(logger: logger)
    if post.status == .pass {
        return .init(name: "SSH Password Authentication", status: .pass, details: "password-based SSH authentication disabled")
    }
    return .init(name: "SSH Password Authentication", status: .fail, details: "sshd config updated but not verified – \(post.details)")
}

func enforceSSHClientAliveInterval(expectedSeconds: Int, logger: HardenLogger) -> CheckResult {
    let result = enforceSSHDDirectives(
        directives: ["clientaliveinterval": String(expectedSeconds)],
        logger: logger
    )

    guard result.status == .pass else {
        return .init(name: "SSH Client Alive Interval", status: result.status, details: result.details)
    }

    let post = checkSSHClientAliveInterval(expectedSeconds: expectedSeconds, logger: logger)
    if post.status == .pass {
        return .init(name: "SSH Client Alive Interval", status: .pass, details: "clientaliveinterval set to \(expectedSeconds)")
    }
    return .init(name: "SSH Client Alive Interval", status: .fail, details: "sshd config updated but not verified – \(post.details)")
}

func enforceSSHClientAliveCountMax(expectedCount: Int, logger: HardenLogger) -> CheckResult {
    let result = enforceSSHDDirectives(
        directives: ["clientalivecountmax": String(expectedCount)],
        logger: logger
    )

    guard result.status == .pass else {
        return .init(name: "SSH Client Alive Count Max", status: result.status, details: result.details)
    }

    let post = checkSSHClientAliveCountMax(expectedCount: expectedCount, logger: logger)
    if post.status == .pass {
        return .init(name: "SSH Client Alive Count Max", status: .pass, details: "clientalivecountmax set to \(expectedCount)")
    }
    return .init(name: "SSH Client Alive Count Max", status: .fail, details: "sshd config updated but not verified – \(post.details)")
}

func enforceSSHLoginBanner(expectedText: String, logger: HardenLogger) -> CheckResult {
    guard geteuid() == 0 else {
        return .init(name: "SSH Login Banner", status: .fail, details: "enforce requires admin/root")
    }

    do {
        try expectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            .appending("\n")
            .write(toFile: sshdBannerPath, atomically: true, encoding: .utf8)

        _ = try? Shell.run(
            "/bin/chmod",
            ["644", sshdBannerPath],
            timeout: 5,
            logger: logger
        )

        let result = enforceSSHDDirectives(
            directives: ["banner": sshdBannerPath],
            logger: logger
        )

        guard result.status == .pass else {
            return .init(name: "SSH Login Banner", status: result.status, details: result.details)
        }

        let post = checkSSHLoginBanner(expectedText: expectedText, logger: logger)
        if post.status == .pass {
            return .init(name: "SSH Login Banner", status: .pass, details: "sshd banner configured")
        }
        return .init(name: "SSH Login Banner", status: .fail, details: "sshd banner updated but not verified – \(post.details)")
    } catch {
        return .init(name: "SSH Login Banner", status: .unknown, details: "ssh banner enforce error: \(error)")
    }
}
