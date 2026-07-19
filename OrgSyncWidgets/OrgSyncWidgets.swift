import WidgetKit
import SwiftUI
import AppIntents

private let appGroup = "group.com.memohnsen.OrgSync"
private let snapshotName = "agenda-snapshot.json"
private let pendingCompletionsKey = "widget.pendingCompletions"

struct WidgetAgendaItem: Codable, Identifiable {
    var id: String; var title: String; var filePath: String
    var scheduled: Date?; var deadline: Date?; var priority: String?; var tags: [String]
}
struct WidgetAgendaSnapshot: Codable { var generatedAt: Date; var items: [WidgetAgendaItem] }
extension WidgetAgendaSnapshot: TimelineEntry { var date: Date { generatedAt } }

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetAgendaSnapshot { .init(generatedAt: .now, items: []) }
    func getSnapshot(in context: Context, completion: @escaping (WidgetAgendaSnapshot) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetAgendaSnapshot>) -> Void) {
        let snapshot = load()
        completion(Timeline(entries: [snapshot], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
    private func load() -> WidgetAgendaSnapshot {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? Data(contentsOf: root.appendingPathComponent(snapshotName)),
              let value = try? JSONDecoder.orgSync.decode(WidgetAgendaSnapshot.self, from: data) else {
            return .init(generatedAt: .now, items: [])
        }
        return value
    }
}
private extension JSONDecoder { static let orgSync: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }() }
private extension JSONEncoder { static let orgSync: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }() }

/// Marks an agenda TODO complete straight from the widget. The extension can't
/// reach the notes in the app's Documents sandbox, so it (1) queues the item id
/// for the app to write DONE into the real note, and (2) optimistically removes
/// it from the shared snapshot so every widget updates immediately.
struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete TODO"

    @Parameter(title: "Item ID") var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroup)
        var pending = defaults?.stringArray(forKey: pendingCompletionsKey) ?? []
        if !pending.contains(itemID) { pending.append(itemID) }
        defaults?.set(pending, forKey: pendingCompletionsKey)

        if let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            let url = root.appendingPathComponent(snapshotName)
            if let data = try? Data(contentsOf: url),
               var snapshot = try? JSONDecoder.orgSync.decode(WidgetAgendaSnapshot.self, from: data) {
                snapshot.items.removeAll { $0.id == itemID }
                if let out = try? JSONEncoder.orgSync.encode(snapshot) {
                    try? out.write(to: url, options: .atomic)
                }
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct FavoritesWidget: Widget {
    let kind = "OrgSyncFavorites"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            let paths = Set(UserDefaults(suiteName: appGroup)?.stringArray(forKey: "favorites.relativePaths") ?? [])
            let favoriteItems = paths.sorted().map { path in
                entry.items.first(where: { $0.filePath == path })
                    ?? WidgetAgendaItem(id: path, title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, filePath: path, scheduled: nil, deadline: nil, priority: nil, tags: [])
            }
            WidgetNoteList(title: "Favorites", symbol: "star.fill", accent: .yellow, items: favoriteItems, empty: "Favorite notes appear here.")
        }
        .configurationDisplayName("Favorite Notes").description("Quick links to your favorite OrgSync notes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpcomingWidget: Widget {
    let kind = "OrgSyncUpcoming"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            let upcoming = entry.items.filter { ($0.deadline ?? $0.scheduled) != nil }.sorted { ($0.deadline ?? $0.scheduled ?? .distantFuture) < ($1.deadline ?? $1.scheduled ?? .distantFuture) }
            WidgetNoteList(title: "Upcoming", symbol: "calendar", accent: .cyan, items: upcoming, empty: "Scheduled TODOs appear here.", showsCompletion: true)
        }
        .configurationDisplayName("Upcoming TODOs").description("Your next scheduled and deadline tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetNoteList: View {
    var title: String; var symbol: String; var accent: Color; var items: [WidgetAgendaItem]; var empty: String
    var showsCompletion = false

    // Estimated heights, scaled with Dynamic Type so the row count stays right
    // at larger text sizes. The header row plus each two-line note row are
    // divided into the real available height to decide how many rows fit —
    // this is what keeps rows from spilling off the top and bottom.
    @ScaledMetric(relativeTo: .headline) private var headerHeight: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 42

    var body: some View {
        GeometryReader { proxy in
            let capacity = max(1, Int((proxy.size.height - headerHeight) / rowHeight))
            let visible = Array(items.prefix(capacity))
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(accent)
                if visible.isEmpty { Text(empty).font(.caption).foregroundStyle(.secondary) }
                ForEach(visible) { item in
                    HStack(spacing: 8) {
                        if showsCompletion {
                            Button(intent: CompleteTodoIntent(itemID: item.id)) {
                                Image(systemName: "circle")
                                    .font(.subheadline)
                                    .foregroundStyle(accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Complete \(item.title)")
                        }
                        Link(destination: URL(string: "orgsync://note/" + item.filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).lineLimit(1).font(.subheadline)
                                Text(item.filePath).lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            // WidgetKit centers a view that does not claim the available space in
            // medium and large families. Fill that space and pin content to the
            // same leading edge used by the small widget.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

@main struct OrgSyncWidgetsBundle: WidgetBundle {
    var body: some Widget { FavoritesWidget(); UpcomingWidget() }
}
