import OhMyTweetDeckCore
import SwiftUI

/// Left-hand compose panel: one message, sent to every selected service.
struct ComposerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New post").font(.headline)

            TextEditor(text: $model.draftText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                .frame(minHeight: 140, maxHeight: 260)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Public image URL (https, JPEG)", text: $model.draftImageURL)
                    .textFieldStyle(.roundedBorder)
                Text("Instagram needs an image; Meta fetches it from this URL. X posts text only.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            ForEach(Service.allCases) { service in
                TargetRow(service: service)
            }

            Spacer(minLength: 0)

            if !model.outcomes.isEmpty {
                OutcomeList()
            }

            HStack {
                Button("Accounts…") { openSettings() }
                Spacer()
                Button {
                    model.post()
                } label: {
                    if model.isPosting { ProgressView().controlSize(.small) } else { Text("Post to \(model.targets.count)") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canPost)
                .help("Send to every selected service (⌘↩)")
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct TargetRow: View {
    @EnvironmentObject var model: AppModel
    let service: Service

    var body: some View {
        let selected = model.targets.contains(service)
        let problems = model.problems(for: service)
        let configured = model.isConfigured(service)
        let remaining = TextMetrics.remaining(model.draftText, for: service)

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(isOn: Binding(
                    get: { selected },
                    set: { on in if on { model.targets.insert(service) } else { model.targets.remove(service) } }
                )) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(rgb: service.accentRGB)).frame(width: 8, height: 8)
                        Text(service.displayName)
                    }
                }
                Spacer()
                Text("\(remaining)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(remaining < 0 ? .red : remaining < 20 ? .orange : .secondary)
            }
            if selected {
                if !configured {
                    Text("Add API credentials in Accounts").font(.caption).foregroundStyle(.orange)
                } else if let first = problems.first {
                    Text(first.description).font(.caption).foregroundStyle(.red)
                } else if service == .x {
                    Text("Sent through your x.com session").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct OutcomeList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Service.allCases.filter { model.outcomes[$0] != nil }) { service in
                HStack(alignment: .top, spacing: 6) {
                    switch model.outcomes[service]! {
                    case .sending:
                        ProgressView().controlSize(.mini)
                        Text("\(service.displayName): sending…")
                    case .posted:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(service.displayName): posted")
                    case .failed(let message):
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                        Text("\(service.displayName): \(message)").textSelection(.enabled)
                    }
                }
                .font(.caption)
            }
        }
    }
}
