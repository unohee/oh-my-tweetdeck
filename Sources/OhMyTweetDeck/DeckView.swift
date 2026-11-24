import OhMyTweetDeckCore
import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

/// TweetDeck-style layout: a compose panel on the left, then columns scrolling sideways.
struct DeckView: View {
    @EnvironmentObject var model: AppModel
    @State private var customColumnService: Service?

    var body: some View {
        HStack(spacing: 0) {
            if model.composerOpen {
                ComposerView()
                    .frame(width: 320)
                Divider()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 1) {
                    ForEach(model.columns) { column in
                        ColumnView(column: column)
                            .frame(width: column.width)
                    }
                }
            }
            .background(Color(nsColor: .separatorColor))
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.composerOpen.toggle() }
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: [.command])
                .help("Toggle the compose panel (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(Service.allCases) { service in
                        Section(service.displayName) {
                            ForEach(service.feedPresets, id: \.self) { feed in
                                Button(feed.title) { model.addColumn(service, feed: feed) }
                            }
                            Button("Custom path…") { customColumnService = service }
                        }
                    }
                } label: {
                    Label("Add column", systemImage: "plus.rectangle.on.rectangle")
                }
                .help("Add a column")
            }
        }
        .sheet(item: $customColumnService) { service in
            CustomColumnSheet(service: service)
        }
        .sheet(item: $model.pendingXPost) { pending in
            XPostSheet(text: pending.text) { model.finishXPost($0) }
        }
    }
}

struct ColumnView: View {
    @EnvironmentObject var model: AppModel
    let column: Column

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(rgb: column.service.accentRGB))
                    .frame(width: 4, height: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(column.feed.title).font(.system(size: 12, weight: .semibold))
                    Text(column.service.displayName).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                iconButton("chevron.left", "Back") { model.pool.existing(column.id)?.goBack() }
                iconButton("arrow.clockwise", "Reload") { model.pool.reload(column, home: false) }
                Menu {
                    Button("Go to column home") { model.pool.reload(column, home: true) }
                    Divider()
                    Button("Move left") { model.move(column, by: -1) }
                    Button("Move right") { model.move(column, by: 1) }
                    Menu("Width") {
                        ForEach([320.0, 380, 460, 560], id: \.self) { w in
                            Button("\(Int(w)) pt") { model.setWidth(column, w) }
                        }
                    }
                    Divider()
                    Button("Remove column", role: .destructive) { model.remove(column) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(.bar)
            Divider()
            WebColumnView(column: column, pool: model.pool)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }
}

struct CustomColumnSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let service: Service
    @State private var title = ""
    @State private var path = ""

    var body: some View {
        Form {
            Text("New \(service.displayName) column").font(.headline)
            TextField("Title", text: $title, prompt: Text("e.g. #swiftlang"))
            TextField("Path", text: $path, prompt: Text("e.g. /search?q=swiftlang&f=live"))
            Text("Any page on \(service.origin.host ?? ""), such as a profile, list or search.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    model.addColumn(service, feed: Feed(title: title.isEmpty ? path : title, path: path))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
