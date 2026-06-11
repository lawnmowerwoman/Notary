import Foundation

package struct RetryPolicy {
    var maxRetries: Int = 2              // entspricht deinem bisherigen retryCount
    var baseDelay: TimeInterval = 0.8    // statt starr 2s
    var backoffFactor: Double = 2.0
    var jitterRatio: Double = 0.2        // ±20%

    func shouldRetry(statusCode: Int) -> Bool {
        // Retryable HTTP codes
        switch statusCode {
        case 408, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    func shouldRetry(urlError: URLError.Code) -> Bool {
        switch urlError {
        case .timedOut,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    func delaySeconds(forAttempt attempt: Int) -> TimeInterval {
        // attempt: 1..maxRetries  (delay before the next attempt)
        let exp = baseDelay * pow(backoffFactor, Double(attempt - 1))
        let jitter = exp * jitterRatio * Double.random(in: -1...1)
        return max(0, exp + jitter)
    }
}

private func parseRetryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
    // Retry-After can be delta-seconds or HTTP-date
    if let v = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
       !v.isEmpty {

        if let seconds = TimeInterval(v) {
            return max(0, seconds)
        }

        // HTTP-date
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        if let date = fmt.date(from: v) {
            return max(0, date.timeIntervalSinceNow)
        }
    }
    return nil
}


package struct HTTPResponse {
    /// "000" for transport errors (like curl exit != 0), otherwise real HTTP status code (e.g. 200)
    package let statusCode: Int
    package let body: Data
    package let errorDescription: String?

    package var bodyString: String {
        String(data: body, encoding: .utf8) ?? ""
    }

    package var isSuccess: Bool {
        statusCode == 200 || statusCode == 201 || statusCode == 204
    }
}

package final class HTTPClient : @unchecked Sendable {

    private let logger: HardenLogger
    private let session: URLSession

    // Similar to: --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 2
    fileprivate let requestTimeout: TimeInterval
    fileprivate let resourceTimeout: TimeInterval
    fileprivate let retryPolicy: RetryPolicy
    fileprivate let fixedRetryDelaySeconds: TimeInterval?   // optional: falls du bewusst „starr“ willst


    // Status messages like your associative array
    private let statusMessages: [Int: String] = [
        0:   "CURL error. HTTPS URI? Bad URL? TLS/TCP? Network down?",
        200: "Success",
        201: "Created/Updated",
        204: "No Content",
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        409: "Conflict",
        500: "Internal Server Error",
        502: "Bad Gateway",
        503: "Service Unavailable",
        504: "Gateway Timeout"
    ]

    package init(
        logger: HardenLogger,
        requestTimeout: TimeInterval = 10,
        resourceTimeout: TimeInterval = 30,
        retryCount: Int = 2,
        retryDelaySeconds: TimeInterval = 2
    ) {
        self.logger = logger
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout

        // Default: exponential backoff. Wenn du bewusst starr willst, nutze fixedRetryDelaySeconds.
        self.retryPolicy = RetryPolicy(maxRetries: retryCount)
        self.fixedRetryDelaySeconds = nil // oder = retryDelaySeconds, wenn du starr bleiben willst

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = requestTimeout
        cfg.timeoutIntervalForResource = resourceTimeout
        cfg.waitsForConnectivity = false

        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Public API

    /// Send request with optional body (Data) and headers.
    /// On transport error returns statusCode 0 ("000" equivalent) and errorDescription.
    package func request(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutOverride: TimeInterval? = nil
    ) async -> HTTPResponse {

        let safeHeaders = redactHeaders(headers)
        logger.develop("HTTP: \(method) \(url.absoluteString) headers=\(safeHeaders) bodyBytes=\(body?.count ?? 0)")

        var lastError: String?

        // attempts = initial + retries
        let totalAttempts = retryPolicy.maxRetries + 1

        for attemptIndex in 1...totalAttempts {
            if ShutdownCoordinator.shared.isShutdownRequested {
                logger.warn("HTTP: request aborted due to \(ShutdownCoordinator.shared.reason)")
                return HTTPResponse(statusCode: 0, body: Data(), errorDescription: "cancelled due to \(ShutdownCoordinator.shared.reason)")
            }

            // Logging the request
            let start = Date()
            logger.develop("[HTTP] \(method) \(url.path)")

            var req = URLRequest(url: url)
            req.httpMethod = method
            req.httpBody = body
            if let t = timeoutOverride { req.timeoutInterval = t } // overrides cfg.timeoutIntervalForRequest
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            do {
                let (data, resp) = try await session.data(for: req)

                guard let http = resp as? HTTPURLResponse else {
                    lastError = "badServerResponse"
                    logger.error("HTTP transport error: \(method) \(url.absoluteString) – badServerResponse")
                    // treat as retryable transport error
                    if attemptIndex < totalAttempts {
                        let d = fixedRetryDelaySeconds ?? retryPolicy.delaySeconds(forAttempt: attemptIndex)
                        logger.develop("HTTP: retry \(attemptIndex)/\(retryPolicy.maxRetries) after \(String(format: "%.2f", d))s (badServerResponse)")
                        try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
                        continue
                    }
                    return HTTPResponse(statusCode: 0, body: Data(), errorDescription: lastError)
                }

                let code = http.statusCode

                // If success, return immediately
                if code == 200 || code == 201 || code == 204 {
                    // Log the execution
                    let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                    let codeDev = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    let msg = statusMessage(for: codeDev)
                    logger.develop("[HTTP] \(codeDev) \(msg) (\(elapsed) ms)")
                    return HTTPResponse(statusCode: code, body: data, errorDescription: nil)
                }

                // Decide retry by status code
                if attemptIndex < totalAttempts, retryPolicy.shouldRetry(statusCode: code) {

                    // Respect Retry-After if present (429/503 often)
                    let ra = parseRetryAfterSeconds(from: http)
                    let d = ra ?? (fixedRetryDelaySeconds ?? retryPolicy.delaySeconds(forAttempt: attemptIndex))

                    logger.develop("HTTP: retry \(attemptIndex)/\(retryPolicy.maxRetries) after \(String(format: "%.2f", d))s (status=\(code))")
                    if ShutdownCoordinator.shared.isShutdownRequested {
                        return HTTPResponse(statusCode: 0, body: Data(), errorDescription: "cancelled due to \(ShutdownCoordinator.shared.reason)")
                    }
                    try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
                    continue
                }

                // No retry: return response as-is (keeps body for diagnostics)
                return HTTPResponse(statusCode: code, body: data, errorDescription: nil)

            } catch {
                lastError = String(describing: error)

                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                if let urlErr = error as? URLError {
                    logger.warn("[HTTP] transport error \(urlErr.code) (\(elapsed) ms)")
                } else {
                    logger.warn("[HTTP] transport error \(error) (\(elapsed) ms)")
                }
                logger.error("HTTP transport error: \(method) \(url.absoluteString) – \(lastError!)")

                // Retry only for retryable URLError codes
                let nsErr = error as NSError
                let urlErr = (error as? URLError)
                ?? (nsErr.domain == NSURLErrorDomain ? URLError(_nsError: nsErr) : nil)

                if attemptIndex < totalAttempts,
                   let ue = urlErr,
                   retryPolicy.shouldRetry(urlError: ue.code) {

                    let d = fixedRetryDelaySeconds ?? retryPolicy.delaySeconds(forAttempt: attemptIndex)
                    logger.develop("HTTP: retry \(attemptIndex)/\(retryPolicy.maxRetries) after \(String(format: "%.2f", d))s (urlError=\(ue.code))")
                    if ShutdownCoordinator.shared.isShutdownRequested {
                        return HTTPResponse(statusCode: 0, body: Data(), errorDescription: "cancelled due to \(ShutdownCoordinator.shared.reason)")
                    }
                    try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
                    continue
                }

                // No retry left / not retryable
                return HTTPResponse(statusCode: 0, body: Data(), errorDescription: lastError ?? "unknown error")
            }
        }

        return HTTPResponse(statusCode: 0, body: Data(), errorDescription: lastError ?? "unknown error")
    }

    /// Convenience for application/x-www-form-urlencoded (like your OAuth token call)
    package func requestForm(url: URL,
                     method: String,
                     form: String,
                     headers: [String: String] = [:]) async -> HTTPResponse {
        var h = headers
        if h["Content-Type"] == nil {
            h["Content-Type"] = "application/x-www-form-urlencoded"
        }
        return await request(url: url, method: method, headers: h, body: form.data(using: .utf8))
    }

    /// Convenience for JSON request (encodes Encodable)
    func requestJSON<T: Encodable>(url: URL,
                                   method: String,
                                   json: T,
                                   headers: [String: String] = [:]) async -> HTTPResponse {
        var h = headers
        if h["Content-Type"] == nil {
            h["Content-Type"] = "application/json"
        }
        let data = (try? JSONEncoder().encode(json)) ?? Data()
        return await request(url: url, method: method, headers: h, body: data)
    }

    // MARK: - httpStatus equivalent

    func statusMessage(for code: Int) -> String {
        statusMessages[code] ?? "Unexpected HTTP status"
    }

    /// Mirrors your httpStatus(): logs DEVELOP on success, ERROR on failure (and body if provided)
    @discardableResult
    package func requireSuccess(_ resp: HTTPResponse, context: String? = nil, logBodyOnError: Bool = true) -> Bool {
        let msg = statusMessage(for: resp.statusCode)
        let ctx = context.map { " \($0)" } ?? ""

        if resp.isSuccess {
            logger.develop("\(resp.statusCode) \(msg)\(ctx)")
            return true
        } else {
            logger.error("\(resp.statusCode == 0 ? "000" : "\(resp.statusCode)") \(msg)\(ctx)")
            if logBodyOnError {
                let body = resp.bodyString
                if !body.isEmpty {
                    logger.error("Response Body: \(body)")
                }
            }
            return false
        }
    }

    // MARK: - Redaction

    private func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers {
            let lk = k.lowercased()
            if lk == "authorization" {
                out[k] = "Bearer ***"
            } else if lk.contains("token") || lk.contains("clientsecret") || lk.contains("client_secret") {
                out[k] = "***redacted***"
            } else {
                out[k] = v
            }
        }
        return out
    }
}


extension HTTPClient {
    package var configDescription: String {
        // Falls du fixedRetryDelaySeconds nutzt, zeig das explizit.
        let retryStyle: String
        if let fixed = fixedRetryDelaySeconds {
            retryStyle = "fixedDelay=\(Int(fixed))s"
        } else {
            retryStyle = "backoff=exp base=\(String(format: "%.1f", retryPolicy.baseDelay))s jitter=\(Int(retryPolicy.jitterRatio * 100))%"
        }

        return "requestTimeout=\(Int(requestTimeout))s resourceTimeout=\(Int(resourceTimeout))s retries=\(retryPolicy.maxRetries) \(retryStyle)"
    }
}
