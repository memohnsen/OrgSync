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

private extension WidgetAgendaItem {
    /// Match the app Agenda: when both dates exist, use the earlier one.
    var relevantDate: Date? { [scheduled, deadline].compactMap { $0 }.min() }
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetAgendaSnapshot { .init(generatedAt: .now, items: []) }
    func getSnapshot(in context: Context, completion: @escaping (WidgetAgendaSnapshot) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetAgendaSnapshot>) -> Void) {
        let snapshot = load()
        completion(Timeline(entries: [snapshot], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
    private func load() -> WidgetAgendaSnapshot { loadAgendaSnapshot() }
}
private extension JSONDecoder { static let orgSync: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }() }
private extension JSONEncoder { static let orgSync: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }() }

/// Reads the shared agenda snapshot from the app group; empty when absent.
func loadAgendaSnapshot() -> WidgetAgendaSnapshot {
    guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
          let data = try? Data(contentsOf: root.appendingPathComponent(snapshotName)),
          let value = try? JSONDecoder.orgSync.decode(WidgetAgendaSnapshot.self, from: data) else {
        return .init(generatedAt: .now, items: [])
    }
    return value
}

// MARK: - Configurable time range

/// User-selectable window for the Upcoming widget, chosen from the Home Screen
/// "Edit Widget" panel.
enum AgendaTimeRange: String, AppEnum {
    case today
    case week
    case upcoming

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Time Range" }
    static var caseDisplayRepresentations: [AgendaTimeRange: DisplayRepresentation] {
        [.today: "Today", .week: "This Week", .upcoming: "All Upcoming"]
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .upcoming: "Upcoming"
        }
    }

    var emptyText: String {
        switch self {
        case .today: "Nothing scheduled for today."
        case .week: "Nothing scheduled this week."
        case .upcoming: "Scheduled TODOs appear here."
        }
    }

    /// Keeps only dated items falling inside this window, earliest first. Overdue
    /// items are always included (they still need attention today).
    func filter(_ items: [WidgetAgendaItem]) -> [WidgetAgendaItem] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now)) ?? .now
        let dated = items.compactMap { item -> (item: WidgetAgendaItem, date: Date)? in
            guard let date = item.relevantDate else { return nil }
            return (item, date)
        }
        let windowed = dated.filter { entry in
            switch self {
            case .today:
                // Use a calendar-day comparison rather than a timestamp
                // cutoff so a configured Today widget can never show tomorrow
                // because of timezone or midnight conversion differences.
                entry.date < startOfToday || calendar.isDate(entry.date, inSameDayAs: .now)
            case .week: entry.date < endOfWeek
            case .upcoming: true
            }
        }
        return windowed.sorted { $0.date < $1.date }.map(\.item)
    }
}

/// Configuration intent backing the Upcoming widget's Edit Widget options.
struct UpcomingConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Upcoming TODOs"
    static var description = IntentDescription("Choose which scheduled tasks to show.")

    @Parameter(title: "Show", default: .upcoming) var range: AgendaTimeRange

    init() {}
}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let items: [WidgetAgendaItem]
    let range: AgendaTimeRange
}

struct UpcomingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: .now, items: [], range: .upcoming)
    }
    func snapshot(for configuration: UpcomingConfigIntent, in context: Context) async -> UpcomingEntry {
        UpcomingEntry(date: .now, items: configuration.range.filter(loadAgendaSnapshot().items), range: configuration.range)
    }
    func timeline(for configuration: UpcomingConfigIntent, in context: Context) async -> Timeline<UpcomingEntry> {
        let entry = UpcomingEntry(date: .now, items: configuration.range.filter(loadAgendaSnapshot().items), range: configuration.range)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

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
        AppIntentConfiguration(kind: kind, intent: UpcomingConfigIntent.self, provider: UpcomingProvider()) { entry in
            AgendaListView(items: entry.items, accent: .cyan, empty: entry.range.emptyText)
        }
        .configurationDisplayName("Upcoming TODOs")
        .description("Scheduled and deadline tasks grouped by day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// One rendered line in the agenda widget: a day divider or a task under it.
enum AgendaRow {
    case day(String)
    case task(WidgetAgendaItem)

    var isDay: Bool { if case .day = self { return true } else { return false } }

    /// Groups items by day (overdue folds into Today) with a divider before each
    /// day's tasks, days ascending and tasks within a day earliest first.
    static func build(from items: [WidgetAgendaItem]) -> [AgendaRow] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let grouped = Dictionary(grouping: items) { item -> Date in
            let date = item.relevantDate ?? today
            return max(calendar.startOfDay(for: date), today)
        }
        var rows: [AgendaRow] = []
        for day in grouped.keys.sorted() {
            rows.append(.day(label(for: day, today: today, calendar: calendar)))
            let dayItems = (grouped[day] ?? []).sorted {
                ($0.relevantDate ?? .distantFuture) < ($1.relevantDate ?? .distantFuture)
            }
            rows.append(contentsOf: dayItems.map(AgendaRow.task))
        }
        return rows
    }

    private static func label(for day: Date, today: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// Fantastical-style agenda: tasks grouped under day dividers, each task a
/// completion circle plus its title (no file path, no per-row date).
struct AgendaListView: View {
    var items: [WidgetAgendaItem]
    var accent: Color
    var empty: String

    // These are fitting estimates only; they do not change the row fonts or
    // spacing. The previous estimates left enough unused space for one task.
    @ScaledMetric(relativeTo: .caption2) private var dayHeight: CGFloat = 21
    @ScaledMetric(relativeTo: .footnote) private var taskHeight: CGFloat = 21

    var body: some View {
        GeometryReader { proxy in
            let rows = fitted(in: proxy.size.height)
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    if rows.isEmpty {
                        Text(empty).font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            switch row {
                            case .day(let label):
                                Text(label.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(accent)
                                    .padding(.top, 1)
                            case .task(let item):
                                taskRow(item)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                WidgetAddTaskButton()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func taskRow(_ item: WidgetAgendaItem) -> some View {
        HStack(spacing: 8) {
            Button(intent: CompleteTodoIntent(itemID: item.id)) {
                Image(systemName: "circle").font(.footnote).foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
            Link(destination: URL(string: "orgsync://note/" + item.filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!) {
                Text(item.title).lineLimit(1).font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Keeps as many rows as fit the available height, never leaving a trailing
    /// day divider with no tasks under it.
    private func fitted(in height: CGFloat) -> [AgendaRow] {
        var used: CGFloat = 0
        var result: [AgendaRow] = []
        for row in AgendaRow.build(from: items) {
            let rowHeight = row.isDay ? dayHeight : taskHeight
            if used + rowHeight > height { break }
            used += rowHeight
            result.append(row)
        }
        if let last = result.last, last.isDay { result.removeLast() }
        return result
    }
}

/// Favorites list: a titled header over note rows (name + path). The agenda
/// widget uses AgendaListView instead.
struct WidgetNoteList: View {
    var title: String; var symbol: String; var accent: Color; var items: [WidgetAgendaItem]; var empty: String

    // Estimated heights, scaled with Dynamic Type so the row count stays right
    // at larger text sizes. The header row plus each two-line note row are
    // divided into the real available height to decide how many rows fit —
    // this is what keeps rows from spilling off the top and bottom.
    @ScaledMetric(relativeTo: .headline) private var headerHeight: CGFloat = 30
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 38

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
                        Link(destination: URL(string: "orgsync://note/" + item.filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).lineLimit(1).font(.footnote.weight(.medium))
                                Text(item.filePath).lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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

/// Opens Agenda directly to its New Task popup from either widget family.
private struct WidgetAddTaskButton: View {
    var body: some View {
        Link(destination: URL(string: "orgsync://agenda?newTask=1")!) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .padding(2)
        }
        .accessibilityLabel("Add task")
    }
}

@main struct OrgSyncWidgetsBundle: WidgetBundle {
    var body: some Widget { FavoritesWidget(); UpcomingWidget() }
}
