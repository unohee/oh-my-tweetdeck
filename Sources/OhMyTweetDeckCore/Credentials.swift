import Foundation
import Security

/// Credentials and endpoints the user enters in Settings. X needs none (it uses the web
/// session). Non-secret values sit next to their secrets so each feature is one Keychain read.
public enum CredentialKey: String, CaseIterable, Sendable {
    case threadsUserID = "threads.userID"
    case threadsAccessToken = "threads.accessToken"
    case instagramUserID = "instagram.userID"
    case instagramAccessToken = "instagram.accessToken"
    case storageEndpoint = "storage.endpoint"
    case storageRegion = "storage.region"
    case storageBucket = "storage.bucket"
    case storageAccessKeyID = "storage.accessKeyID"
    case storageSecretAccessKey = "storage.secretAccessKey"
    case storagePublicBaseURL = "storage.publicBaseURL"
    case aiProvider = "ai.provider"
    case aiBaseURL = "ai.baseURL"
    case aiAPIKey = "ai.apiKey"
    case aiModel = "ai.model"
}

public protocol CredentialStore: Sendable {
    func get(_ key: CredentialKey) -> String?
    func set(_ value: String?, for key: CredentialKey) throws
}

/// Generic-password items in the login Keychain, scoped by `service` (the bundle id).
public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func query(_ key: CredentialKey) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key.rawValue]
    }

    public func get(_ key: CredentialKey) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, for key: CredentialKey) throws {
        SecItemDelete(query(key) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [CredentialKey: String] = [:]
    private let lock = NSLock()

    public init(_ values: [CredentialKey: String] = [:]) {
        self.values = values
    }

    public func get(_ key: CredentialKey) -> String? {
        lock.withLock { values[key] }
    }

    public func set(_ value: String?, for key: CredentialKey) throws {
        lock.withLock { values[key] = (value?.isEmpty ?? true) ? nil : value }
    }
}

extension CredentialStore {
    /// API publishers that have complete credentials. X is handled by the web-session route.
    public func configuredAPIPublishers(transport: HTTPTransport = URLSession.shared) -> [Publisher] {
        var publishers: [Publisher] = []
        if let id = get(.threadsUserID), let token = get(.threadsAccessToken) {
            publishers.append(ThreadsPublisher(userID: id, accessToken: token, transport: transport))
        }
        if let id = get(.instagramUserID), let token = get(.instagramAccessToken) {
            publishers.append(InstagramPublisher(userID: id, accessToken: token, transport: transport))
        }
        return publishers
    }
}

extension CredentialStore {
    /// Object storage for attachments, when every field is present and the URLs parse.
    public var objectStorage: ObjectStorageConfig? {
        guard let endpoint = get(.storageEndpoint).flatMap(URL.init(string:)), endpoint.scheme == "https",
              let bucket = get(.storageBucket), let keyID = get(.storageAccessKeyID),
              let secret = get(.storageSecretAccessKey),
              let publicBase = get(.storagePublicBaseURL).flatMap(URL.init(string:)), publicBase.scheme == "https"
        else { return nil }
        return ObjectStorageConfig(endpoint: endpoint, region: get(.storageRegion) ?? "auto", bucket: bucket,
                                   accessKeyID: keyID, secretAccessKey: secret, publicBaseURL: publicBase)
    }

    /// The AI provider for draft rewrites, when a model is chosen (and a key, if it needs one).
    public var aiProvider: AIProvider? {
        let kind = get(.aiProvider).flatMap(AIProvider.Kind.init(rawValue:)) ?? .openRouter
        guard let base = (get(.aiBaseURL) ?? kind.defaultBaseURL).nonEmpty.flatMap(URL.init(string:)),
              let model = get(.aiModel) else { return nil }
        let key = get(.aiAPIKey)
        if kind.needsKey && key == nil { return nil }
        return AIProvider(kind: kind, baseURL: base, apiKey: key, model: model)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
