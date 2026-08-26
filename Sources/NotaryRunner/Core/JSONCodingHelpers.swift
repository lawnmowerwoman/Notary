import Foundation

/// Decodes an integer that may be represented as either a JSON number or a JSON string.
package struct IntOrString: Codable, Hashable, Sendable {
    package let value: Int

    package init(_ value: Int) { self.value = value }

    package init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let i = try? c.decode(Int.self) {
            self.value = i
            return
        }
        if let s = try? c.decode(String.self), let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.value = i
            return
        }

        throw DecodingError.typeMismatch(
            Int.self,
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Expected Int or String convertible to Int")
        )
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
