import OhMyTweetDeckCore
import SwiftUI
import UniformTypeIdentifiers

/// Content of the Spotlight-style compose panel: one message, sent to every selected service.
struct ComposerView: View {
    @EnvironmentObject var model: AppModel
    var onClose: () -> Void = {}
    @FocusState private var editorFocused: Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if model.draftText.isEmpty {
                    Text("What's happening?")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.draftText)
                    .font(.system(size: 17))
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .focused($editorFocused)
            }
            .padding(.horizontal, 15)
            .padding(.top, 14)

            StatusLine()
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.6)

            HStack(spacing: 8) {
                ForEach(Service.postTargets) { service in
                    TargetChip(service: service)
                }
                Divider().frame(height: 18)
                ImageControl()

                Spacer(minLength: 0)

                AIMenu()

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .buttonStyle(.borderless)
                .help("Accounts…")

                Button {
                    model.post()
                } label: {
                    if model.isPosting {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack(spacing: 6) {
                            Text("Post to \(model.targets.count)").fontWeight(.semibold)
                            Text("⌘↩").opacity(0.75)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canPost)
                .help("Send to every selected service (⌘↩)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .font(.system(size: 12))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: ComposePanelController.cornerRadius - 2)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let file = urls.first(where: ImageControl.isImageFile) else { return false }
            model.draftAttachment = file
            return true
        } isTargeted: { isDropTargeted = $0 }
        .disabled(model.isRewriting)
        .onAppear { editorFocused = true }
        .onChange(of: model.composeFocusRequest) { editorFocused = true }
    }
}

/// One line above the bar: the latest post outcome, else the first problem of a selected target.
private struct StatusLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.isRewriting {
            Label("Rewriting with AI…", systemImage: "sparkles").foregroundStyle(.secondary)
        } else if let error = model.rewriteError {
            Label("AI: \(error)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .lineLimit(1).textSelection(.enabled)
        } else if let (service, state) = Service.postTargets.compactMap({ s in model.outcomes[s].map { (s, $0) } }).last {
            switch state {
            case .sending: Label("\(service.displayName): sending…", systemImage: "arrow.up.circle").foregroundStyle(.secondary)
            case .posted: Label(summary, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message): Label("\(service.displayName): \(message)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).textSelection(.enabled)
            }
        } else if let (service, text, color) = firstIssue {
            Text("\(service.displayName): \(text)").foregroundStyle(color)
        } else {
            Text(" ")
        }
    }

    private var summary: String {
        let posted = Service.postTargets.filter { if case .posted = model.outcomes[$0] { return true }; return false }
        return "Posted to " + posted.map(\.displayName).joined(separator: ", ")
    }

    private var firstIssue: (Service, String, Color)? {
        for service in Service.postTargets where model.targets.contains(service) {
            if !model.isConfigured(service) { return (service, "add API credentials in Accounts", .orange) }
            if let problem = model.problems(for: service).first, !model.draftText.isEmpty {
                return (service, problem.description, .red)
            }
            if let note = DraftValidator.notes(model.draft, for: service).first { return (service, note, .orange) }
        }
        return nil
    }
}

/// Toggleable pill per service; the number is characters left.
private struct TargetChip: View {
    @EnvironmentObject var model: AppModel
    let service: Service

    var body: some View {
        let selected = model.targets.contains(service)
        let remaining = TextMetrics.remaining(model.draftText, for: service)
        let accent = Color(rgb: service.accentRGB)
        Button {
            if selected { model.targets.remove(service) } else { model.targets.insert(service) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(accent.opacity(selected ? 1 : 0.45)).frame(width: 8, height: 8)
                Text(service.displayName).fontWeight(.medium)
                    .foregroundStyle(selected ? .primary : .secondary)
                Text("\(remaining)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(remaining < 0 ? .red : remaining < 20 ? .orange : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? accent.opacity(0.18) : .primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(selected ? "Posting to \(service.displayName) — click to skip" : "Click to post to \(service.displayName)")
    }
}


/// Attach a local image (button, or drop anywhere on the panel) or paste a public URL.
struct ImageControl: View {
    @EnvironmentObject var model: AppModel

    static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    var body: some View {
        Group {
            if let file = model.draftAttachment {
                HStack(spacing: 6) {
                    Thumbnail(url: file)
                    Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Button { model.draftAttachment = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove the image")
                }
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .padding(.vertical, 3)
            } else {
                HStack(spacing: 6) {
                    Button(action: choose) { Image(systemName: "photo.badge.plus") }
                        .buttonStyle(.borderless)
                        .help("Attach an image (or drop one on the panel)")
                    TextField("Image file or public URL", text: $model.draftImageURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
        .frame(width: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.06)))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = .floating  // above the compose panel
        if panel.runModal() == .OK, let url = panel.url { model.draftAttachment = url }
    }
}

private struct Thumbnail: View {
    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// AI rewrites of the draft (OpenRouter / Ollama / any OpenAI-compatible endpoint).
private struct AIMenu: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Menu {
            if model.credentials.aiProvider == nil {
                Button("Set up AI in Accounts…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            } else {
                ForEach(DraftRewrite.allCases) { mode in
                    Button(mode.title) { model.rewrite(mode) }
                        .disabled(!model.canRewrite)
                }
                if model.textBeforeRewrite != nil {
                    Divider()
                    Button("Undo AI edit") { model.undoRewrite() }
                }
            }
        } label: {
            if model.isRewriting { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles") }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Rewrite the draft with AI")
    }
}
