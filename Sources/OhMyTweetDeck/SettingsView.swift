import OhMyTweetDeckCore
import SwiftUI

/// API credentials for the services posted through official APIs. Stored in the Keychain.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var values: [CredentialKey: String] = [:]
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Text("X posts through the x.com session in your columns. Log in to X in any X column; no API key is needed.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("X") }

            Section {
                field("Threads user ID", .threadsUserID)
                secure("Access token (threads_basic, threads_content_publish)", .threadsAccessToken)
            } header: { Text("Threads — official Threads API") }

            Section {
                field("Instagram professional account ID", .instagramUserID)
                secure("Access token (instagram_business_content_publish)", .instagramAccessToken)
                Text("Instagram API with Instagram Login. Professional (Business/Creator) accounts only.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Instagram — Instagram API") }

            HStack {
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear {
            for key in CredentialKey.allCases { values[key] = model.credentials.get(key) ?? "" }
        }
    }

    private func binding(_ key: CredentialKey) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func field(_ title: String, _ key: CredentialKey) -> some View {
        TextField(title, text: binding(key))
    }

    private func secure(_ title: String, _ key: CredentialKey) -> some View {
        SecureField(title, text: binding(key))
    }

    private func save() {
        do {
            for key in CredentialKey.allCases {
                try model.credentials.set(values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), for: key)
            }
            message = "Saved to Keychain"
            model.objectWillChange.send()
        } catch {
            message = "Save failed: \(error.localizedDescription)"
        }
    }
}
