import Foundation

public enum TokenSourceKind: String, Equatable {
    case dedicatedManagedProfile
    case mainManagedProfile
    case localSecureStorage
}

public struct TokenCandidate: Equatable {
    public var source: TokenSourceKind
    public var token: String

    public init(source: TokenSourceKind, token: String) {
        self.source = source
        self.token = token
    }
}

public protocol AppTokenSource {
    var source: TokenSourceKind { get }
    func readToken() throws -> String?
}

public struct AppTokenResolver {
    private var sources: [any AppTokenSource]

    public init(sources: [any AppTokenSource]) {
        self.sources = sources
    }

    public func resolve() -> TokenCandidate? {
        for source in sources {
            guard let token = try? source.readToken(),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            return TokenCandidate(source: source.source, token: token)
        }
        return nil
    }
}

public struct FileTokenSource: AppTokenSource {
    public var source: TokenSourceKind
    public var url: URL
    public var key: String

    public init(source: TokenSourceKind, url: URL, key: String) {
        self.source = source
        self.url = url
        self.key = key
    }

    public func readToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            return nil
        }
        return dict[key] as? String
    }
}

public enum NotaryTokenSources {
    public static func resolver() -> AppTokenResolver {
        AppTokenResolver(sources: [
            FileTokenSource(
                source: .dedicatedManagedProfile,
                url: URL(fileURLWithPath: "/Library/Managed Preferences/de.twocent.notary.apptoken.plist"),
                key: "apptoken"
            ),
            FileTokenSource(
                source: .mainManagedProfile,
                url: URL(fileURLWithPath: "/Library/Managed Preferences/de.twocent.notary.plist"),
                key: "apptoken"
            ),
            FileTokenSource(
                source: .localSecureStorage,
                url: URL(fileURLWithPath: "/var/db/notary.plist"),
                key: "apptoken"
            )
        ])
    }
}

