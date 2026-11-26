import Foundation
import Security
import WebKit

/// Keeps the web logins across launches. WKWebView drops session cookies (no Expires) when the
/// app quits and can lose recent writes if the app exits before WebKit flushes to disk, which
/// makes X / Threads / Instagram ask to log in again every launch. This mirrors the cookies of
/// the shared data store into the Keychain (cookies are credentials: never a plain file), gives
/// session cookies a long expiry, and restores whatever is missing before the first page loads.
@MainActor
final class CookieVault: NSObject, WKHTTPCookieStoreObserver {
    private let service: String
    private let account = "web.cookies"
    private let store: WKHTTPCookieStore
    private var saveTask: Task<Void, Never>?
    private(set) var restored = false

    /// Cookies for these hosts only; the deck never needs anything else persisted.
    private let hosts = ["x.com", "twitter.com", "threads.com", "threads.net", "instagram.com",
                         "youtube.com", "google.com",
                         "facebook.com", "meta.com", "cdninstagram.com"]
    private let sessionLifetime: TimeInterval = 60 * 60 * 24 * 365

    init(service: String = Bundle.main.bundleIdentifier ?? "dev.unohee.OhMyTweetDeck") {
        self.store = WKWebsiteDataStore.default().httpCookieStore
        self.service = service
        super.init()
    }

    /// Re-adds saved cookies the store no longer has, then starts watching for changes.
    func restore() async {
        let current = await store.allCookies()
        let have = Set(current.map(Self.identity))
        for cookie in loadSnapshot() where !have.contains(Self.identity(cookie)) {
            if let exp = cookie.expiresDate, exp < Date() { continue }
            await store.setCookie(cookie)
        }
        restored = true
        store.add(self)
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in self.scheduleSave() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    /// Writes the current cookies immediately (also used on quit).
    func saveNow() async {
        guard restored else { return }  // never overwrite the backup with a not-yet-restored store
        let cookies = await store.allCookies().filter(isDeckCookie)
        guard !cookies.isEmpty else { return }
        let encoded = cookies.compactMap { cookie -> [String: Any]? in
            var props: [String: Any] = [:]
            for (key, value) in cookie.properties ?? [:] { props[key.rawValue] = value }
            props[HTTPCookiePropertyKey.expires.rawValue] =
                (cookie.expiresDate ?? Date().addingTimeInterval(sessionLifetime)).timeIntervalSince1970
            props.removeValue(forKey: HTTPCookiePropertyKey.discard.rawValue)
            return props
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: encoded, format: .binary, options: 0)
        else { return }
        writeKeychain(data)
    }

    private func isDeckCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return hosts.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    private static func identity(_ cookie: HTTPCookie) -> String { "\(cookie.domain)|\(cookie.path)|\(cookie.name)" }

    private func loadSnapshot() -> [HTTPCookie] {
        guard let data = readKeychain(),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return [] }
        return list.compactMap { raw in
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in raw { props[HTTPCookiePropertyKey(key)] = value }
            if let ts = raw[HTTPCookiePropertyKey.expires.rawValue] as? Double {
                props[.expires] = Date(timeIntervalSince1970: ts)
            }
            return HTTPCookie(properties: props)
        }
    }

    // MARK: Keychain

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func readKeychain() -> Data? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func writeKeychain(_ data: Data) {
        let update = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var q = baseQuery
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in getAllCookies { cont.resume(returning: $0) } }
    }

    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { cont in setCookie(cookie) { cont.resume() } }
    }
}
