import Foundation
import Testing
@testable import OhMyTweetDeckCore

// MARK: - Test doubles

/// Replays canned responses in order and records every request.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in
            requests.append(request)
            return responses.isEmpty ? (500, "{}") : responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

let noSleep = ContainerPolling(interval: .zero, maxAttempts: 3, sleep: { _ in })

func formBody(_ request: URLRequest) -> [String: String] {
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    var result: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
        result[kv[0].removingPercentEncoding!] = kv.count > 1 ? kv[1].removingPercentEncoding! : ""
    }
    return result
}

// MARK: - Columns

@Suite struct ColumnTests {
    @Test func defaultDeckHasOneHomeColumnPerService() {
        let deck = Column.defaultDeck
        #expect(deck.map(\.service) == Service.postTargets)
        #expect(deck.map(\.url.absoluteString) == [
            "https://x.com/home", "https://www.threads.com/", "https://www.instagram.com/",
        ])
    }

    @Test func youtubeIsWatchOnly() {
        #expect(!Service.youtube.isPostTarget)
        #expect(!Service.postTargets.contains(.youtube))
        let column = Column(service: .youtube, feed: Service.youtube.feedPresets[3])
        #expect(column.url.absoluteString == "https://www.youtube.com/playlist?list=WL")
        #expect(DraftValidator.problems(PostDraft(text: "hi", targets: [.youtube]), for: .youtube) == [.notPostable])
    }

    @Test func customPathKeepsQueryString() {
        let column = Column(service: .x, feed: Feed(title: "Swift", path: "search?q=swift&f=live"))
        #expect(column.url.absoluteString == "https://x.com/search?q=swift&f=live")
    }

    @Test func columnsShareWindowWidth() {
        #expect(DeckLayout.columnWidth(available: 1442, count: 3) == 480)
        #expect(DeckLayout.columnWidth(available: 2000, count: 1) == 2000)
        // Too narrow for three columns: keep the minimum and let the deck scroll.
        #expect(DeckLayout.columnWidth(available: 800, count: 3) == DeckLayout.minColumnWidth)
        #expect(DeckLayout.columnWidth(available: 800, count: 0) == DeckLayout.minColumnWidth)
    }

    @Test func widthIsClamped() {
        #expect(Column(service: .x, feed: Feed(title: "a", path: "/"), width: 10).width == Column.widthRange.lowerBound)
        #expect(Column(service: .x, feed: Feed(title: "a", path: "/"), width: 9999).width == Column.widthRange.upperBound)
    }

    @Test func storeRoundTripsAndFallsBackOnCorruption() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ColumnStore(fileURL: dir.appendingPathComponent("columns.json"))
        #expect(store.load().count == Column.defaultDeck.count) // missing file

        let columns = [Column(service: .threads, feed: Feed(title: "Activity", path: "/activity"), width: 420)]
        try store.save(columns)
        #expect(store.load() == columns)

        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().map(\.service) == Service.postTargets)
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Text metrics & validation

@Suite struct TextMetricsTests {
    @Test func xWeightsLatinOneAndHangulTwo() {
        #expect(TextMetrics.length(of: "hello", for: .x) == 5)
        #expect(TextMetrics.length(of: "안녕", for: .x) == 4)
    }

    @Test func xCountsURLsAs23() {
        #expect(TextMetrics.length(of: "see https://example.com/a/very/long/path/indeed", for: .x) == 4 + 23)
    }

    @Test func xCountsEmojiAsTwo() {
        #expect(TextMetrics.length(of: "👍", for: .x) == 2)
        #expect(TextMetrics.length(of: "👨‍👩‍👧", for: .x) == 2)
        #expect(TextMetrics.length(of: "#1", for: .x) == 2) // '#' and '1' are not emoji here
    }

    @Test func threadsCountsEmojiAsUTF8Bytes() {
        #expect(TextMetrics.length(of: "hi", for: .threads) == 2)
        #expect(TextMetrics.length(of: "hi👍", for: .threads) == 2 + 4)
        #expect(TextMetrics.length(of: "안녕", for: .threads) == 2)
    }

    @Test func instagramNeedsImageAndXIgnoresIt() {
        let textOnly = PostDraft(text: "hello", targets: [.x, .threads, .instagram])
        #expect(DraftValidator.problems(textOnly, for: .instagram) == [.imageRequired])
        #expect(DraftValidator.problems(textOnly, for: .x).isEmpty)
        #expect(DraftValidator.problems(textOnly, for: .threads).isEmpty)

        let withImage = PostDraft(text: "hello", imageURL: URL(string: "https://cdn.example.com/a.jpg"), targets: [.x])
        #expect(DraftValidator.problems(withImage, for: .x).isEmpty)
        #expect(DraftValidator.notes(withImage, for: .x).count == 1)
        #expect(DraftValidator.problems(withImage, for: .instagram).isEmpty)
    }

    @Test func oneDraftWithTextAndImageIsPostableEverywhere() {
        let draft = PostDraft(text: "hello deck", imageURL: URL(string: "https://cdn.example.com/a.jpg"),
                              targets: Set(Service.postTargets))
        for service in Service.postTargets {
            #expect(DraftValidator.problems(draft, for: service).isEmpty, "\(service)")
        }
    }

    @Test func overLimitAndNonHTTPSAreReported() {
        let long = PostDraft(text: String(repeating: "a", count: 281), targets: [.x])
        #expect(DraftValidator.problems(long, for: .x) == [.tooLong(over: 1)])
        let http = PostDraft(text: "x", imageURL: URL(string: "http://a.com/b.jpg"), targets: [.instagram])
        #expect(DraftValidator.problems(http, for: .instagram) == [.imageMustBeHTTPS])
    }
}

// MARK: - Publishers (no network)

@Suite struct PublisherTests {
    @Test func threadsTextPostCreatesPollsAndPublishes() async throws {
        let transport = ScriptedTransport([
            (200, #"{"id":"C1"}"#),
            (200, #"{"status":"IN_PROGRESS"}"#),
            (200, #"{"status":"FINISHED"}"#),
            (200, #"{"id":"P1"}"#),
        ])
        let publisher = ThreadsPublisher(userID: "U1", accessToken: "tok", transport: transport, polling: noSleep)
        let receipt = try await publisher.publish(PostDraft(text: "a+b & c=d 안녕", targets: [.threads]))

        #expect(receipt == PublishReceipt(service: .threads, postID: "P1"))
        let r = transport.requests
        #expect(r.count == 4)
        #expect(r[0].url!.absoluteString == "https://graph.threads.com/v1.0/U1/threads")
        #expect(r[0].httpMethod == "POST")
        #expect(formBody(r[0]) == ["media_type": "TEXT", "text": "a+b & c=d 안녕"])
        #expect(r[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(!(r[0].url!.absoluteString.contains("tok")))
        #expect(r[1].url!.absoluteString == "https://graph.threads.com/v1.0/C1?fields=status,error_message")
        #expect(r[3].url!.absoluteString == "https://graph.threads.com/v1.0/U1/threads_publish")
        #expect(formBody(r[3]) == ["creation_id": "C1"])
    }

    @Test func threadsContainerErrorSurfacesMessage() async {
        let transport = ScriptedTransport([
            (200, #"{"id":"C1"}"#),
            (200, #"{"status":"ERROR","error_message":"FAILED_DOWNLOADING_IMAGE"}"#),
        ])
        let publisher = ThreadsPublisher(userID: "U1", accessToken: "t", transport: transport, polling: noSleep)
        await #expect(throws: PublishError.containerFailed("FAILED_DOWNLOADING_IMAGE")) {
            try await publisher.publish(PostDraft(text: "x", targets: [.threads]))
        }
    }

    @Test func graphErrorIsDecoded() async {
        let transport = ScriptedTransport([(400, #"{"error":{"message":"Invalid OAuth access token","code":190}}"#)])
        let publisher = ThreadsPublisher(userID: "U1", accessToken: "t", transport: transport, polling: noSleep)
        await #expect(throws: GraphAPIError(status: 400, message: "Invalid OAuth access token", code: 190)) {
            try await publisher.publish(PostDraft(text: "x", targets: [.threads]))
        }
    }

    @Test func instagramImagePostFlow() async throws {
        let transport = ScriptedTransport([
            (200, #"{"id":"C9"}"#),
            (200, #"{"status_code":"FINISHED"}"#),
            (200, #"{"id":"M9"}"#),
        ])
        let publisher = InstagramPublisher(userID: "IG1", accessToken: "t", transport: transport, polling: noSleep)
        let draft = PostDraft(text: "caption", imageURL: URL(string: "https://cdn.example.com/p.jpg"), targets: [.instagram])
        let receipt = try await publisher.publish(draft)

        #expect(receipt.postID == "M9")
        let r = transport.requests
        #expect(r[0].url!.absoluteString == "https://graph.instagram.com/v23.0/IG1/media")
        #expect(formBody(r[0]) == ["image_url": "https://cdn.example.com/p.jpg", "caption": "caption"])
        #expect(r[2].url!.absoluteString == "https://graph.instagram.com/v23.0/IG1/media_publish")
    }

    @Test func instagramRejectsTextOnlyWithoutNetwork() async {
        let transport = ScriptedTransport([])
        let publisher = InstagramPublisher(userID: "IG1", accessToken: "t", transport: transport, polling: noSleep)
        await #expect(throws: PublishError.invalid([.imageRequired])) {
            try await publisher.publish(PostDraft(text: "hi", targets: [.instagram]))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func instagramContainerTimesOut() async {
        let transport = ScriptedTransport([
            (200, #"{"id":"C"}"#),
            (200, #"{"status_code":"IN_PROGRESS"}"#),
            (200, #"{"status_code":"IN_PROGRESS"}"#),
            (200, #"{"status_code":"IN_PROGRESS"}"#),
        ])
        let publisher = InstagramPublisher(userID: "IG1", accessToken: "t", transport: transport, polling: noSleep)
        let draft = PostDraft(text: "", imageURL: URL(string: "https://a.com/p.jpg"), targets: [.instagram])
        await #expect(throws: PublishError.containerTimedOut) { try await publisher.publish(draft) }
    }
}

// MARK: - X intent & fan-out

@Suite struct XIntentTests {
    @Test func composeURLEncodesReservedCharacters() {
        let url = XWebIntent.composeURL(text: "a+b & c=d #tag 안녕\nline2")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(url.host == "x.com" && url.path == "/intent/post")
        #expect(comps.queryItems?.first?.value == "a+b & c=d #tag 안녕\nline2")
        #expect(url.absoluteString.contains("%2B"))
    }

    @Test func draftScriptEscapesAndNormalizesNeedle() {
        let script = XWebIntent.draftPresentScript(text: "  he said \"hi\"\n</script>  and   more ")
        #expect(script.contains(#"["he said \"hi\" <\/script> and more"]"#))
    }

    @Test func scriptsEmbedSelectorsAsJSON() {
        #expect(XWebIntent.clickScript.contains(#"[data-testid=\"tweetButton\"]"#))
        #expect(XWebIntent.jsArrayLiteral(["a\"b", "c\nd"]) == #"["a\"b","c\nd"]"#)
    }
}

struct StubPublisher: Publisher {
    let service: Service
    let fails: Bool
    func publish(_ draft: PostDraft) async throws -> PublishReceipt {
        if fails { throw PublishError.containerFailed("boom") }
        return PublishReceipt(service: service, postID: "id-\(service.rawValue)")
    }
}

@Suite struct CrossPosterTests {
    @Test func oneFailureDoesNotBlockOthersAndMissingIsReported() async {
        let draft = PostDraft(text: "hi", targets: [.x, .threads, .instagram])
        let outcomes = await CrossPoster().post(draft, using: [
            StubPublisher(service: .threads, fails: false),
            StubPublisher(service: .instagram, fails: true),
        ])
        guard case .posted(let receipt) = outcomes[.threads] else { Issue.record("threads"); return }
        #expect(receipt.postID == "id-threads")
        guard case .failed(let message) = outcomes[.instagram] else { Issue.record("ig"); return }
        #expect(message.contains("boom"))
        guard case .failed(let missing) = outcomes[.x] else { Issue.record("x"); return }
        #expect(missing.contains("Not configured"))
    }

    @Test func untargetedPublishersAreNotCalled() async {
        let outcomes = await CrossPoster().post(
            PostDraft(text: "hi", targets: [.threads]),
            using: [StubPublisher(service: .threads, fails: false), StubPublisher(service: .instagram, fails: true)])
        #expect(outcomes.keys.sorted { $0.rawValue < $1.rawValue } == [.threads])
    }

    @Test func inMemoryStoreBuildsOnlyCompletePublishers() {
        let store = InMemoryCredentialStore([.threadsUserID: "1", .threadsAccessToken: "t", .instagramUserID: "2"])
        #expect(store.configuredAPIPublishers().map(\.service) == [.threads])
    }
}

// MARK: - Attachments & object storage

@Suite struct ObjectStorageTests {
    /// AWS's documented "GET Object" example (S3 SigV4 header auth).
    @Test func sigV4MatchesAWSExample() {
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
        request.httpMethod = "GET"
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        SigV4.sign(&request, accessKeyID: "AKIAIOSFODNN7EXAMPLE",
                   secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                   region: "us-east-1", date: Date(timeIntervalSince1970: 1_369_353_600))  // 2013-05-24
        #expect(request.value(forHTTPHeaderField: "Authorization") ==
            "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, "
            + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, "
            + "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    let config = ObjectStorageConfig(endpoint: URL(string: "https://acct.r2.cloudflarestorage.com")!, region: "auto",
                                     bucket: "media", accessKeyID: "AK", secretAccessKey: "SK",
                                     publicBaseURL: URL(string: "https://pub-1.r2.dev/")!)

    @Test func uploadPutsSignedObjectAndReturnsPublicURL() async throws {
        let transport = ScriptedTransport([(200, "")])
        let url = try await ObjectStorageUploader(config: config, transport: transport)
            .upload(Data([1, 2, 3]), key: "omt/2026/11/a b.jpg", contentType: "image/jpeg")
        #expect(url.absoluteString == "https://pub-1.r2.dev/omt/2026/11/a%20b.jpg")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://acct.r2.cloudflarestorage.com/media/omt/2026/11/a%20b.jpg")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("/auto/s3/aws4_request") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("SK") == false)
    }

    @Test func uploadErrorSurfacesStatus() async {
        let transport = ScriptedTransport([(403, "<Error>AccessDenied</Error>")])
        await #expect(throws: ObjectStorageError.self) {
            _ = try await ObjectStorageUploader(config: config, transport: transport)
                .upload(Data(), key: "k.jpg", contentType: "image/jpeg")
        }
    }

    @Test func attachmentKeyIsDatedAndRandom() {
        let key = ObjectStorageUploader.attachmentKey(date: Date(timeIntervalSince1970: 1_795_000_000),
                                                      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!)
        #expect(key == "omt/2026/11/00000000-0000-0000-0000-0000000000ab.jpg")
    }

    @Test func storeBuildsStorageOnlyWhenComplete() {
        let store = InMemoryCredentialStore([.storageEndpoint: "https://acct.r2.cloudflarestorage.com",
                                             .storageBucket: "media", .storageAccessKeyID: "AK",
                                             .storageSecretAccessKey: "SK"])
        #expect(store.objectStorage == nil)
        try? store.set("https://pub-1.r2.dev", for: .storagePublicBaseURL)
        #expect(store.objectStorage?.region == "auto")
    }

    @Test func attachmentValidation() {
        let file = URL(fileURLWithPath: "/tmp/a.png")
        let draft = PostDraft(text: "hi", attachment: file, targets: Set(Service.postTargets))
        // With storage: everything is postable and X attaches the file itself.
        for service in Service.postTargets { #expect(DraftValidator.problems(draft, for: service).isEmpty) }
        #expect(DraftValidator.notes(draft, for: .x).isEmpty)
        // Without storage: only the Graph API services are blocked.
        #expect(DraftValidator.problems(draft, for: .x, canUpload: false).isEmpty)
        #expect(DraftValidator.problems(draft, for: .instagram, canUpload: false) == [.imageStorageMissing])
        // An image-only X post is fine once a file is attached.
        #expect(DraftValidator.problems(PostDraft(text: "", attachment: file, targets: [.x]), for: .x).isEmpty)
    }

    @Test func jpegEncodingCapsLongEdge() throws {
        // 1×1 PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let file = FileManager.default.temporaryDirectory.appending(path: "omt-test-\(UUID()).png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let jpeg = try ImageEncoding.jpeg(from: file)
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
    }
}

// MARK: - AI draft assistant

@Suite struct DraftAssistantTests {
    let provider = AIProvider(kind: .openRouter, baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                              apiKey: "sk-test", model: "some/model")

    @Test func rewriteSendsChatCompletionAndCleansReply() async throws {
        let transport = ScriptedTransport([(200, #"{"choices":[{"message":{"content":"<think>hm</think>\n\"Hello world\" "}}]}"#)])
        let out = try await DraftAssistant(provider: provider, transport: transport).rewrite("hello wrld", .polish, limit: 280)
        #expect(out == "Hello world")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(body["model"] as? String == "some/model")
        let messages = body["messages"] as! [[String: String]]
        #expect(messages.last?["content"] == "hello wrld")
        #expect(messages.first?["content"]?.contains("280 characters") == true)
    }

    @Test func ollamaSendsNoAuthAndErrorsSurface() async {
        let local = AIProvider(kind: .ollama, baseURL: URL(string: "http://localhost:11434/v1")!, apiKey: nil, model: "llama")
        let transport = ScriptedTransport([(404, #"{"error":"model 'llama' not found"}"#)])
        do {
            _ = try await DraftAssistant(provider: local, transport: transport).rewrite("x", .shorter, limit: nil)
            Issue.record("expected an error")
        } catch let error as DraftAssistantError {
            #expect(error.message.contains("not found"))
        } catch { Issue.record("wrong error \(error)") }
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func modelsAreListed() async throws {
        let transport = ScriptedTransport([(200, #"{"data":[{"id":"b"},{"id":"a"}]}"#)])
        #expect(try await DraftAssistant(provider: provider, transport: transport).models() == ["a", "b"])
        let empty = ScriptedTransport([(200, #"{"object":"list","data":null}"#)])
        #expect(try await DraftAssistant(provider: provider, transport: empty).models() == [])
    }

    @Test func providerNeedsModelAndOpenRouterKey() {
        let store = InMemoryCredentialStore([.aiProvider: "openRouter", .aiModel: "m"])
        #expect(store.aiProvider == nil)
        try? store.set("sk", for: .aiAPIKey)
        #expect(store.aiProvider?.baseURL.absoluteString == "https://openrouter.ai/api/v1")
        let local = InMemoryCredentialStore([.aiProvider: "ollama", .aiModel: "llama"])
        #expect(local.aiProvider?.baseURL.absoluteString == "http://localhost:11434/v1")
    }
}

@Suite struct AutoRefreshTests {
    let home = URL(string: "https://x.com/home")!
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func decide(interval: Int = 300, after: TimeInterval = 301, loading: Bool = false,
                current: String? = "https://x.com/home", page: AutoRefresh.PageState? = .init()) -> AutoRefresh.Decision {
        AutoRefresh.decide(interval: interval, lastLoad: t0, now: t0 + after, isLoading: loading,
                           current: current.flatMap(URL.init(string:)), home: home, page: page)
    }

    @Test func idleDueColumnRefreshes() {
        #expect(decide() == .refresh)
    }

    @Test func offNotDueAndLoadingWait() {
        #expect(decide(interval: 0) == .off)
        #expect(decide(after: 120) == .notDue)
        #expect(decide(after: 298) == .refresh)  // finished just after the previous tick
        #expect(decide(loading: true) == .loading)
    }

    @Test func busyPagesWait() {
        #expect(decide(page: nil) == .unknownPage)
        #expect(decide(page: .init(scrollTop: 800)) == .scrolled)
        #expect(decide(page: .init(scrollTop: 40)) == .refresh)
        #expect(decide(page: .init(editing: true)) == .editing)
        #expect(decide(page: .init(playing: true)) == .playing)
        #expect(decide(page: .init(modal: true)) == .modal)
    }

    @Test func browsingAwayFromHomeWaits() {
        #expect(decide(current: "https://x.com/someone/status/1") == .awayFromHome)
        #expect(decide(current: "https://x.com/home/") == .refresh)
        #expect(decide(current: "https://x.com/home?s=20") == .refresh)
    }

    @Test func searchColumnHomeIncludesQuery() {
        let search = URL(string: "https://x.com/search?q=swift&f=live")!
        #expect(AutoRefresh.isHome(URL(string: "https://x.com/search?q=swift&f=live")!, home: search))
        #expect(!AutoRefresh.isHome(URL(string: "https://x.com/search?q=other&f=live")!, home: search))
        #expect(AutoRefresh.isHome(URL(string: "https://www.threads.com")!, home: URL(string: "https://www.threads.com/")!))
    }

    @Test func probeResultDecodes() {
        let state = AutoRefresh.PageState.decode(#"{"scrollTop":12.5,"editing":false,"playing":true,"modal":false}"#)
        #expect(state == .init(scrollTop: 12.5, playing: true))
        #expect(AutoRefresh.PageState.decode("not json") == nil)
        #expect(AutoRefresh.PageState.decode(nil) == nil)
    }

    @Test func intervalDefaultsAndLabels() throws {
        let defaults = try #require(UserDefaults(suiteName: "omt-autorefresh-test"))
        defaults.removePersistentDomain(forName: "omt-autorefresh-test")
        #expect(AutoRefresh.interval(in: defaults) == AutoRefresh.defaultInterval)
        defaults.set(0, forKey: AutoRefresh.defaultsKey)
        #expect(AutoRefresh.interval(in: defaults) == 0)
        defaults.set("60", forKey: AutoRefresh.defaultsKey)  // what a launch argument looks like
        #expect(AutoRefresh.interval(in: defaults) == 60)
        #expect(AutoRefresh.label(0) == "Off")
        #expect(AutoRefresh.label(60) == "Every minute")
        #expect(AutoRefresh.label(300) == "Every 5 min")
        defaults.removePersistentDomain(forName: "omt-autorefresh-test")
    }
}
