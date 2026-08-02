import Foundation

public enum AppTokenError: Error, CustomStringConvertible, Equatable {
    case malformed(String)
    case unsupportedPrivateKey
    case publicKeyExportFailed
    case privateKeyUnavailable(String)

    public var description: String {
        switch self {
        case .malformed(let message):
            return "Malformed token: \(message)"
        case .unsupportedPrivateKey:
            return "Unsupported private key"
        case .publicKeyExportFailed:
            return "Public key export failed"
        case .privateKeyUnavailable(let message):
            return "Private key unavailable: \(message)"
        }
    }
}

