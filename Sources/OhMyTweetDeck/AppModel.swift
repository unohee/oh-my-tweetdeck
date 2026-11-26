import Foundation
import OhMyTweetDeckCore
import SwiftUI

let bundleID = Bundle.main.bundleIdentifier ?? "dev.unohee.OhMyTweetDeck"

/// App state: the column layout, the composer draft and the last cross-post outcomes.
@MainActor
final class AppModel: ObservableObject {
    @Published var columns: [Column] {
        didSet { persist() }
    }
    @Published var draftText = ""
    @Published var draftImageURL = ""
    /// Local image file chosen in the compose panel.
    @Published var draftAttachment: URL?
    @Published var isRewriting = false
    @Published var rewriteError: String?
    /// Text before the last AI rewrite, for Undo.
    @Published var textBeforeRewrite: String?
    @Published var targets: Set<Service> = Set(Service.postTargets)
    @Published var outcomes: [Service: OutcomeState] = [:]
    @Published var isPosting = false
    /// Bumped each time the compose panel is shown so the editor takes focus.
    @Published var composeFocusRequest = 0
    /// Non-nil while the X web composer sheet is shown.
    @Published var pendingXPost: PendingXPost?
    @Published var saveError: String?

    let pool = WebViewPool()
    /// Spotlight-style compose panel (⌘N).
    private(set) lazy var composePanel = ComposePanelController(model: self)
    let store: ColumnStore
    let credentials: CredentialStore

    enum OutcomeState: Equatable {
        case sending
        case posted(String?)
        case failed(String)
    }

    struct PendingXPost: Identifiable {
        let id = UUID()
        let text: String
        /// JPEG of the attachment, put into x.com's composer.
        let image: Data?
    }

    init(store: ColumnStore = .standard(bundleID: bundleID),
         credentials: CredentialStore = KeychainCredentialStore(service: bundleID)) {
        self.store = store
        self.credentials = credentials
        self.columns = store.load()
        let vault = pool.vault
        AppDelegate.flushOnQuit = { await vault.saveNow() }
    }

    private func persist() {
        do { try store.save(columns); saveError = nil } catch { saveError = error.localizedDescription }
    }

    // MARK: Columns

    func addColumn(_ service: Service, feed: Feed) {
        columns.append(Column(service: service, feed: feed))
    }

    func remove(_ column: Column) {
        pool.discard(column.id)
        columns.removeAll { $0.id == column.id }
    }

    func move(_ column: Column, by offset: Int) {
        guard let index = columns.firstIndex(of: column) else { return }
        let target = index + offset
        guard columns.indices.contains(target) else { return }
        columns.swapAt(index, target)
    }

    // MARK: Composer

    var draft: PostDraft {
        let trimmed = draftImageURL.trimmingCharacters(in: .whitespaces)
        return PostDraft(text: draftText, imageURL: trimmed.isEmpty ? nil : URL(string: trimmed),
                         attachment: draftAttachment, targets: targets)
    }

    func problems(for service: Service) -> [DraftProblem] {
        DraftValidator.problems(draft, for: service, canUpload: credentials.objectStorage != nil)
    }

    func isConfigured(_ service: Service) -> Bool {
        switch service {
        case .x: return true // web session; login state is checked in the sheet
        case .threads: return credentials.get(.threadsUserID) != nil && credentials.get(.threadsAccessToken) != nil
        case .instagram: return credentials.get(.instagramUserID) != nil && credentials.get(.instagramAccessToken) != nil
        case .youtube: return false
        }
    }

    var canPost: Bool {
        !isPosting && !targets.isEmpty && targets.allSatisfy { problems(for: $0).isEmpty && isConfigured($0) }
    }

    /// Sends the draft: API services in parallel, X through the visible web composer sheet.
    /// A local attachment is re-encoded as JPEG once; X gets the bytes, Threads and Instagram
    /// get a public URL after it is uploaded to the user's object storage.
    func post() {
        guard canPost else { return }
        let draft = self.draft
        isPosting = true
        outcomes = Dictionary(uniqueKeysWithValues: draft.targets.map { ($0, OutcomeState.sending) })
        let apiTargets = draft.targets.subtracting([.x])
        let publishers = credentials.configuredAPIPublishers()
        let storage = credentials.objectStorage

        Task {
            var image: Data?
            if let file = draft.attachment {
                do {
                    image = try await Task.detached { try ImageEncoding.jpeg(from: file) }.value
                } catch {
                    for service in draft.targets { outcomes[service] = .failed("Could not read the image file") }
                    finishIfDone()
                    return
                }
            }
            if draft.targets.contains(.x) { pendingXPost = PendingXPost(text: draft.text, image: image) }

            guard !apiTargets.isEmpty else { finishIfDone(); return }
            var apiDraft = draft
            apiDraft.targets = apiTargets
            apiDraft.attachment = nil
            if apiDraft.imageURL == nil, let image, let storage {
                do {
                    apiDraft.imageURL = try await ObjectStorageUploader(config: storage)
                        .upload(image, key: ObjectStorageUploader.attachmentKey(), contentType: "image/jpeg")
                } catch {
                    for service in apiTargets { outcomes[service] = .failed("\(error)") }
                    finishIfDone()
                    return
                }
            }
            let results = await CrossPoster().post(apiDraft, using: publishers)
            for (service, outcome) in results {
                switch outcome {
                case .posted(let receipt): outcomes[service] = .posted(receipt.postID)
                case .failed(let message): outcomes[service] = .failed(message)
                }
            }
            finishIfDone()
        }
    }

    // MARK: AI rewrite

    var canRewrite: Bool {
        credentials.aiProvider != nil && !isRewriting
            && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func rewrite(_ mode: DraftRewrite) {
        guard canRewrite, let provider = credentials.aiProvider else { return }
        let original = draftText
        isRewriting = true
        rewriteError = nil
        Task {
            defer { isRewriting = false }
            do {
                let result = try await DraftAssistant(provider: provider).rewrite(original, mode, limit: rewriteLimit)
                guard !result.isEmpty, draftText == original else { return }  // user kept typing: keep theirs
                textBeforeRewrite = original
                draftText = result
            } catch {
                rewriteError = "\(error)"
            }
        }
    }

    func undoRewrite() {
        guard let previous = textBeforeRewrite else { return }
        draftText = previous
        textBeforeRewrite = nil
    }

    /// Tightest budget among the selected services, in plain characters. X weighs CJK as two,
    /// so its budget halves for such drafts.
    private var rewriteLimit: Int? {
        targets.map { service -> Int in
            guard service == .x else { return service.maxLength }
            let weighted = TextMetrics.length(of: draftText, for: .x)
            return weighted > draftText.count ? service.maxLength / 2 : service.maxLength
        }.min()
    }

    func finishXPost(_ state: OutcomeState) {
        outcomes[.x] = state
        pendingXPost = nil
        finishIfDone()
    }

    private func finishIfDone() {
        guard !outcomes.values.contains(.sending) else { return }
        isPosting = false
        // Clear the draft only when every target succeeded, so a partial failure can be retried.
        if outcomes.values.allSatisfy({ if case .posted = $0 { return true } else { return false } }) {
            draftText = ""
            draftImageURL = ""
            draftAttachment = nil
            textBeforeRewrite = nil
        }
    }
}
