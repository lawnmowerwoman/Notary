import Foundation

func checkSystemUptime(warnDays: Int, maxDays: Int) -> CheckResult {
    let uptimeSeconds = ProcessInfo.processInfo.systemUptime
    let uptimeDays = uptimeSeconds / 86_400
    let bootDate = Date(timeIntervalSinceNow: -uptimeSeconds)
    let bootText = formattedBootDate(bootDate)
    let uptimeText = formattedUptime(uptimeSeconds)

    if maxDays > 0, uptimeDays >= Double(maxDays) {
        return CheckResult(
            name: "System Uptime",
            status: .fail,
            details: "system has been running for \(uptimeText) since \(bootText) and exceeded the max threshold of \(maxDays) days",
            severity: .high
        )
    }

    if uptimeDays >= Double(warnDays) {
        return CheckResult(
            name: "System Uptime",
            status: .fail,
            details: "system has been running for \(uptimeText) since \(bootText); a reboot is recommended after \(warnDays) days",
            severity: .low
        )
    }

    return CheckResult(
        name: "System Uptime",
        status: .pass,
        details: "system uptime is \(uptimeText) since \(bootText) and remains below the warn threshold of \(warnDays) days"
    )
}

private func formattedBootDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}

private func formattedUptime(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let days = totalSeconds / 86_400
    let hours = (totalSeconds % 86_400) / 3_600
    let minutes = (totalSeconds % 3_600) / 60

    if days > 0 {
        return "\(days)d \(hours)h \(minutes)m"
    }
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}
