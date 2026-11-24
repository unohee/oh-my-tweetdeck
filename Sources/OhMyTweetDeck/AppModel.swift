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
    @Published var composerOpen = true
    @Published var draftText = ""
    @Published var draftImageURL = ""
    @Published var targets: Set<Service> = Set(Service.allCases)
    @Published var outcomes: [Service: OutcomeState] = [:]
    @Published var isPosting = false
    /// Non-nil while the X web composer sheet is shown.
    @Published var pendingXPost: PendingXPost?
    @Published var saveError: String?

    let pool = WebViewPool()
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
    }

    init(store: ColumnStore = .standard(bundleID: bundleID),
         credentials: CredentialStore = KeychainCredentialStore(service: bundleID)) {
        self.store = store
        self.credentials = credentials
        self.columns = store.load()
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

    func setWidth(_ column: Column, _ width: Double) {
        guard let index = columns.firstIndex(where: { $0.id == column.id }) else { return }
        columns[index].width = min(max(width, Column.widthRange.lowerBound), Column.widthRange.upperBound)
    }

    // MARK: Composer

    var draft: PostDraft {
        let trimmed = draftImageURL.trimmingCharacters(in: .whitespaces)
        return PostDraft(text: draftText, imageURL: trimmed.isEmpty ? nil : URL(string: trimmed), targets: targets)
    }

    func problems(for service: Service) -> [DraftProblem] {
        DraftValidator.problems(draft, for: service)
    }

    func isConfigured(_ service: Service) -> Bool {
        switch service {
        case .x: return true // web session; login state is checked in the sheet
        case .threads: return credentials.get(.threadsUserID) != nil && credentials.get(.threadsAccessToken) != nil
        case .instagram: return credentials.get(.instagramUserID) != nil && credentials.get(.instagramAccessToken) != nil
        }
    }

    var canPost: Bool {
        !isPosting && !targets.isEmpty && targets.allSatisfy { problems(for: $0).isEmpty && isConfigured($0) }
    }

    /// Sends the draft: API services in parallel, X through the visible web composer sheet.
    func post() {
        guard canPost else { return }
        let draft = self.draft
        isPosting = true
        outcomes = Dictionary(uniqueKeysWithValues: draft.targets.map { ($0, OutcomeState.sending) })

        if draft.targets.contains(.x) { pendingXPost = PendingXPost(text: draft.text) }

        let apiTargets = draft.targets.subtracting([.x])
        let publishers = credentials.configuredAPIPublishers()
        Task {
            if !apiTargets.isEmpty {
                var apiDraft = draft
                apiDraft.targets = apiTargets
                let results = await CrossPoster().post(apiDraft, using: publishers)
                for (service, outcome) in results {
                    switch outcome {
                    case .posted(let receipt): outcomes[service] = .posted(receipt.postID)
                    case .failed(let message): outcomes[service] = .failed(message)
                    }
                }
            }
            finishIfDone()
        }
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
        }
    }
}
