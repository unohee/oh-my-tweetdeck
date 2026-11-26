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

/// TweetDeck-style layout: columns share the window width and scroll sideways only when
/// they would get narrower than `DeckLayout.minColumnWidth`.
struct DeckView: View {
    @EnvironmentObject var model: AppModel
    @State private var customColumnService: Service?
    @AppStorage(AutoRefresh.defaultsKey) private var autoRefresh = AutoRefresh.defaultInterval

    var body: some View {
        GeometryReader { geo in
            let width = DeckLayout.columnWidth(available: geo.size.width, count: model.columns.count)
            ScrollView(.horizontal) {
                HStack(spacing: 1) {
                    ForEach(model.columns) { column in
                        ColumnView(column: column)
                            .frame(width: width)
                    }
                }
                .frame(height: geo.size.height)
            }
            .scrollDisabled(width * Double(model.columns.count) <= geo.size.width + 1)
        }
        .background(Color(nsColor: .separatorColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.composePanel.toggle()
                } label: {
                    Label("New Post", systemImage: "square.and.pencil")
                }
                .help("Compose a post (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Auto-refresh", selection: $autoRefresh) {
                        ForEach(AutoRefresh.intervals, id: \.self) { Text(AutoRefresh.label($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Text("Skips a column while you scroll, type, watch or browse away from its home.")
                    Divider()
                    Button("Refresh all now") { model.pool.reloadAll() }
                } label: {
                    Label("Auto-refresh", systemImage: autoRefresh > 0 ? "clock.arrow.circlepath" : "arrow.clockwise")
                }
                .help("Auto-refresh: \(AutoRefresh.label(autoRefresh))")
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
            XPostSheet(text: pending.text, image: pending.image) { model.finishXPost($0) }
        }
        // The X sheet belongs to the deck window; keep the floating panel from covering it.
        .onChange(of: model.pendingXPost?.id) { _, id in
            if id != nil { model.composePanel.hide() }
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
