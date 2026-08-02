import Foundation

public enum AppTokenCanonicalJSON {
    public static func headerData(_ header: AppTokenHeader) throws -> Data {
        let json = "{"
            + "\"algorithm\":\(jsonString(header.algorithm)),"
            + "\"formatVersion\":\(header.formatVersion),"
            + "\"keyId\":\(jsonString(header.keyId)),"
            + "\"type\":\(jsonString(header.type))"
            + "}"
        return Data(json.utf8)
    }

    public static func payloadData(_ payload: AppTokenPayload) throws -> Data {
        var fields: [(String, String)] = [
            ("activationCode", jsonString(payload.activationCode)),
            ("customerName", jsonString(payload.customerName)),
            ("features", jsonArray(payload.features)),
            ("issuer", jsonString(payload.issuer)),
            ("productId", jsonString(payload.productId)),
            ("schemaVersion", "\(payload.schemaVersion)"),
            ("tokenId", jsonString(payload.tokenId))
        ]

        if let issuedAt = payload.issuedAt {
            fields.append(("issuedAt", jsonString(issuedAt)))
        }
        if let validFrom = payload.validFrom {
            fields.append(("validFrom", jsonString(validFrom)))
        }
        fields.append(("validUntil", jsonString(payload.validUntil)))

        fields.sort { $0.0 < $1.0 }
        let body = fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",")
        return Data("{\(body)}".utf8)
    }

    public static func parseHeader(_ data: Data) throws -> AppTokenHeader {
        let object = try parseObject(data)
        return AppTokenHeader(
            type: try string(object, "type"),
            formatVersion: try int(object, "formatVersion"),
            algorithm: try string(object, "algorithm"),
            keyId: try string(object, "keyId")
        )
    }

    public static func parsePayload(_ data: Data) throws -> AppTokenPayload {
        let object = try parseObject(data)
        return AppTokenPayload(
            schemaVersion: try int(object, "schemaVersion"),
            issuer: try string(object, "issuer"),
            productId: try string(object, "productId"),
            tokenId: try string(object, "tokenId"),
            activationCode: try string(object, "activationCode"),
            customerName: try string(object, "customerName"),
            validFrom: object["validFrom"] as? String,
            validUntil: try string(object, "validUntil"),
            features: try stringArray(object, "features"),
            issuedAt: object["issuedAt"] as? String
        )
    }

    private static func parseObject(_ data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data, options: [])
        guard let object = value as? [String: Any] else {
            throw AppTokenError.malformed("JSON root is not an object")
        }
        return object
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw AppTokenError.malformed("Missing string field: \(key)")
        }
        return value
    }

    private static func int(_ object: [String: Any], _ key: String) throws -> Int {
        guard let value = object[key] as? Int else {
            throw AppTokenError.malformed("Missing integer field: \(key)")
        }
        return value
    }

    private static func stringArray(_ object: [String: Any], _ key: String) throws -> [String] {
        guard let values = object[key] as? [String] else {
            throw AppTokenError.malformed("Missing string array field: \(key)")
        }
        return values
    }

    private static func jsonArray(_ values: [String]) -> String {
        "[" + values.map(jsonString).joined(separator: ",") + "]"
    }

    private static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

