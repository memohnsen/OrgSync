import WidgetKit
import SwiftUI

private let appGroup = "group.com.memohnsen.OrgSync"
private let snapshotName = "agenda-snapshot.json"

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

struct FavoritesWidget: Widget {
    let kind = "OrgSyncFavorites"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            let paths = Set(UserDefaults(suiteName: appGroup)?.stringArray(forKey: "favorites.relativePaths") ?? [])
            let favoriteItems = paths.sorted().prefix(3).map { path in
                entry.items.first(where: { $0.filePath == path })
                    ?? WidgetAgendaItem(id: path, title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, filePath: path, scheduled: nil, deadline: nil, priority: nil, tags: [])
            }
            WidgetNoteList(title: "Favorites", symbol: "star.fill", items: Array(favoriteItems), empty: "Favorite notes appear here.")
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
            WidgetNoteList(title: "Upcoming", symbol: "calendar", items: Array(upcoming.prefix(5)), empty: "Scheduled TODOs appear here.")
        }
        .configurationDisplayName("Upcoming TODOs").description("Your next scheduled and deadline tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetNoteList: View {
    var title: String; var symbol: String; var items: [WidgetAgendaItem]; var empty: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            if items.isEmpty { Text(empty).font(.caption).foregroundStyle(.secondary) }
            ForEach(items) { item in
                Link(destination: URL(string: "orgsync://note/" + item.filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).lineLimit(1).font(.subheadline)
                        Text(item.filePath).lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }.containerBackground(for: .widget) { Color.clear }
    }
}

@main struct OrgSyncWidgetsBundle: WidgetBundle {
    var body: some Widget { FavoritesWidget(); UpcomingWidget() }
}
