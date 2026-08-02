import Foundation

public enum AppTokenDefaults {
    public static let productId = "NOTX"
    public static let validUntil = "2027-12-31"
    public static let feature = "transporter"
    public static let issuer = "twocent-notary"

    public static var notaryProductPolicy: ProductPolicy {
        ProductPolicy(acceptedProductIds: ["NOTX", "NOT2"], acceptedIssuers: [issuer])
    }

    public static var notaryFeatureRegistry: FeatureRegistry {
        FeatureRegistry(recognizedFeatures: [feature])
    }

    public static func activationCode(productId: String = productId) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let suffix = (0..<12).map { _ in String(alphabet.randomElement()!) }.joined()
        return "\(productId)\(suffix)"
    }
}

