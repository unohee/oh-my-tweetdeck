import AppKit
import OhMyTweetDeckCore
import SwiftUI

/// Accounts, image storage and the AI assistant, in one sidebar window.
/// Every secret goes to the Keychain; nothing here is written to disk in plain text.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page = .accounts
    @State private var values: [CredentialKey: String] = [:]
    @State private var saved: [CredentialKey: String] = [:]
    @State private var message: String?
    @State private var models: [String] = []
    @State private var modelsMessage: String?

    enum Page: String, CaseIterable, Identifiable {
        case accounts, storage, ai
        var id: String { rawValue }
        var title: String {
            switch self {
            case .accounts: return "Accounts"
            case .storage: return "Image storage"
            case .ai: return "AI assistant"
            }
        }
        var symbol: String {
            switch self {
            case .accounts: return "person.crop.circle"
            case .storage: return "externaldrive.badge.icloud"
            case .ai: return "sparkles"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch page {
                        case .accounts: accountsPage
                        case .storage: storagePage
                        case .ai: aiPage
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                saveBar
            }
        }
        .frame(width: 760, height: 580)
        .onAppear(perform: load)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .frame(width: 20)
                            .foregroundStyle(page == item ? Color.white : Color.accentColor)
                        Text(item.title).foregroundStyle(page == item ? Color.white : Color.primary)
                        Spacer(minLength: 0)
                        Circle().fill(status(of: item).color).frame(width: 7, height: 7)
                            .opacity(page == item ? 0.95 : 1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(page == item ? Color.accentColor : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Secrets are stored in your macOS Keychain.")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
        }
        .padding(12)
        .frame(width: 190)
        .background(.regularMaterial)
    }

    // MARK: Pages

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Accounts", subtitle: "Where each service posts from.")

            Card(accent: Service.x.accent, name: "X", pill: .info("Web login")) {
                Text("Posts through your x.com session. Log in to X in any X column; no API key is needed.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Card(accent: Service.threads.accent, name: "Threads",
                 pill: ready(.threadsUserID, .threadsAccessToken),
                 help: ("Get a token", "https://developers.facebook.com/docs/threads/get-started")) {
                FieldRow("User ID", text: binding(.threadsUserID), prompt: "numeric Threads user ID")
                SecretRow("Access token", text: binding(.threadsAccessToken),
                          hint: "needs threads_basic and threads_content_publish")
            }

            Card(accent: Service.instagram.accent, name: "Instagram",
                 pill: ready(.instagramUserID, .instagramAccessToken),
                 help: ("Get a token", "https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login")) {
                FieldRow("Account ID", text: binding(.instagramUserID), prompt: "professional account ID")
                SecretRow("Access token", text: binding(.instagramAccessToken),
                          hint: "needs instagram_business_content_publish")
                Text("Instagram API with Instagram Login. Business and Creator accounts only; every post needs an image.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var storagePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Image storage",
                       subtitle: "Threads and Instagram fetch images from a public URL. Attached files are uploaded here as JPEGs; X gets the file directly.")
            Card(symbol: "externaldrive.badge.icloud", name: "S3-compatible bucket",
                 pill: status(of: .storage).pill,
                 help: ("Cloudflare R2 setup", "https://developers.cloudflare.com/r2/")) {
                FieldRow("Endpoint", text: binding(.storageEndpoint), prompt: "https://<account>.r2.cloudflarestorage.com")
                HStack(spacing: 12) {
                    FieldRow("Bucket", text: binding(.storageBucket), prompt: "my-bucket")
                    FieldRow("Region", text: binding(.storageRegion), prompt: "auto")
                        .frame(width: 140)
                }
                FieldRow("Access key ID", text: binding(.storageAccessKeyID), prompt: "")
                SecretRow("Secret access key", text: binding(.storageSecretAccessKey))
                FieldRow("Public URL", text: binding(.storagePublicBaseURL), prompt: "https://pub-….r2.dev or your domain")
                Text("The bucket must allow public reads. Uploaded files stay until you delete them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var aiPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "AI assistant",
                       subtitle: "Rewrites your draft from the ✦ menu in the compose panel. Only the draft text is sent, and only when you pick a rewrite.")
            Card(symbol: "sparkles", name: provider.displayName, pill: status(of: .ai).pill,
                 help: provider == .openRouter ? ("Get an API key", "https://openrouter.ai/keys") : nil) {
                Picker("Provider", selection: providerBinding) {
                    ForEach(AIProvider.Kind.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                FieldRow("Base URL", text: binding(.aiBaseURL), prompt: provider.defaultBaseURL)
                if provider != .ollama {
                    SecretRow(provider == .openRouter ? "API key" : "API key (optional)", text: binding(.aiAPIKey))
                }
                HStack(alignment: .bottom, spacing: 8) {
                    FieldRow("Model", text: binding(.aiModel),
                             prompt: provider == .ollama ? "e.g. llama3.2" : "e.g. openrouter/auto")
                    Menu {
                        if models.isEmpty { Text(modelsMessage ?? "Press Load first") }
                        ForEach(models, id: \.self) { id in Button(id) { values[.aiModel] = id } }
                    } label: { Text("Models") }
                        .fixedSize().disabled(models.isEmpty)
                    Button("Load") { loadModels() }
                }
                if let modelsMessage, models.isEmpty {
                    Text(modelsMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Save bar

    private var isDirty: Bool {
        CredentialKey.allCases.contains { (values[$0] ?? "") != (saved[$0] ?? "") }
    }

    private var saveBar: some View {
        HStack(spacing: 10) {
            if isDirty {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .labelStyle(DotLabelStyle())
            } else if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revert") { load() }.disabled(!isDirty)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Status

    private enum Status {
        case ready, partial, empty
        var color: Color {
            switch self {
            case .ready: return .green
            case .partial: return .orange
            case .empty: return Color.secondary.opacity(0.45)
            }
        }
        var pill: Pill {
            switch self {
            case .ready: return .good("Ready")
            case .partial: return .warn("Incomplete")
            case .empty: return .none("Not set up")
            }
        }
    }

    private func filled(_ keys: CredentialKey...) -> Int {
        keys.filter { !(values[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private func status(of page: Page) -> Status {
        switch page {
        case .accounts:
            let t = filled(.threadsUserID, .threadsAccessToken), i = filled(.instagramUserID, .instagramAccessToken)
            return (t == 2 && i == 2) ? .ready : (t + i > 0 ? .partial : .empty)
        case .storage:
            let n = filled(.storageEndpoint, .storageBucket, .storageAccessKeyID, .storageSecretAccessKey, .storagePublicBaseURL)
            return n == 5 ? .ready : (n > 0 ? .partial : .empty)
        case .ai:
            let needsKey = provider == .openRouter
            if filled(.aiModel) == 0 { return filled(.aiAPIKey) > 0 ? .partial : .empty }
            return (needsKey && filled(.aiAPIKey) == 0) ? .partial : .ready
        }
    }

    private func ready(_ keys: CredentialKey...) -> Pill {
        let n = keys.filter { !(values[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
        return n == keys.count ? .good("Ready") : (n > 0 ? .warn("Incomplete") : .none("Not set up"))
    }

    // MARK: State

    private var provider: AIProvider.Kind {
        values[.aiProvider].flatMap(AIProvider.Kind.init(rawValue:)) ?? .openRouter
    }

    private var providerBinding: Binding<AIProvider.Kind> {
        Binding(get: { provider }, set: { kind in
            // Swap the default URL along with the provider unless the user typed their own.
            let current = values[.aiBaseURL] ?? ""
            if current.isEmpty || AIProvider.Kind.allCases.contains(where: { $0.defaultBaseURL == current }) {
                values[.aiBaseURL] = kind.defaultBaseURL
            }
            values[.aiProvider] = kind.rawValue
            models = []
            modelsMessage = nil
        })
    }

    private func binding(_ key: CredentialKey) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func load() {
        var loaded: [CredentialKey: String] = [:]
        for key in CredentialKey.allCases { loaded[key] = model.credentials.get(key) ?? "" }
        if (loaded[.aiProvider] ?? "").isEmpty { loaded[.aiProvider] = AIProvider.Kind.openRouter.rawValue }
        values = loaded
        saved = loaded
        message = nil
    }

    private func save() {
        do {
            for key in CredentialKey.allCases {
                try model.credentials.set(values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), for: key)
            }
            saved = values
            message = "Saved to Keychain"
            model.objectWillChange.send()
        } catch {
            message = "Save failed: \(error.localizedDescription)"
        }
    }

    private func loadModels() {
        let base = (values[.aiBaseURL] ?? "").isEmpty ? provider.defaultBaseURL : values[.aiBaseURL]!
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces)) else { modelsMessage = "Invalid base URL"; return }
        let key = values[.aiAPIKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = DraftAssistant(provider: AIProvider(kind: provider, baseURL: url, apiKey: key, model: ""))
        modelsMessage = "Loading…"
        Task {
            do {
                models = try await assistant.models()
                modelsMessage = models.isEmpty ? "No models" : nil
            } catch {
                models = []
                modelsMessage = "\(error)"
            }
        }
    }
}

// MARK: - Pieces

private enum Pill {
    case good(String), warn(String), info(String), none(String)
    var text: String {
        switch self { case .good(let s), .warn(let s), .info(let s), .none(let s): return s }
    }
    var color: Color {
        switch self {
        case .good: return .green
        case .warn: return .orange
        case .info: return .blue
        case .none: return .secondary
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Card<Content: View>: View {
    var accent: Color?
    var symbol: String?
    let name: String
    let pill: Pill
    var help: (String, String)?
    @ViewBuilder var content: Content

    init(accent: Color? = nil, symbol: String? = nil, name: String, pill: Pill,
         help: (String, String)? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent; self.symbol = symbol; self.name = name
        self.pill = pill; self.help = help; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill((accent ?? .accentColor).opacity(0.18)).frame(width: 28, height: 28)
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent ?? .accentColor)
                    } else {
                        Circle().fill(accent ?? .accentColor).frame(width: 10, height: 10)
                    }
                }
                Text(name).font(.headline)
                Text(pill.text)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(pill.color.opacity(0.16)))
                    .foregroundStyle(pill.color)
                Spacer()
                if let help, let url = URL(string: help.1) {
                    Link(destination: url) {
                        Label(help.0, systemImage: "arrow.up.right").font(.caption)
                    }
                }
            }
            content
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct FieldRow: View {
    let label: String
    @Binding var text: String
    let prompt: String

    init(_ label: String, text: Binding<String>, prompt: String) {
        self.label = label; self._text = text; self.prompt = prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }
}

/// Secret input with a reveal toggle and a paste shortcut (tokens are long and hard to type).
private struct SecretRow: View {
    let label: String
    @Binding var text: String
    var hint: String?
    @State private var reveal = false

    init(_ label: String, text: Binding<String>, hint: String? = nil) {
        self.label = label; self._text = text; self.hint = hint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if let hint { Text("· \(hint)").font(.caption).foregroundStyle(.tertiary) }
            }
            HStack(spacing: 6) {
                Group {
                    if reveal { TextField("", text: $text, prompt: Text("Paste here")) }
                    else { SecureField("", text: $text, prompt: Text("Paste here")) }
                }
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        text = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Paste from clipboard")
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .help(reveal ? "Hide" : "Show")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

private extension Service {
    var accent: Color {
        let v = accentRGB
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
