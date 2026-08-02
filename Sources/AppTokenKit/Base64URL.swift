import Foundation

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        guard !text.contains("+"), !text.contains("/"), !text.contains("=") else {
            return nil
        }

        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}

public enum AppTokenBase64URL {
    public static func encode(_ data: Data) -> String {
        Base64URL.encode(data)
    }

    public static func decode(_ text: String) -> Data? {
        Base64URL.decode(text)
    }
}
