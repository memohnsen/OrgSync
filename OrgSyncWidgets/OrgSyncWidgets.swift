import WidgetKit
import SwiftUI
import AppIntents

// AgendaSnapshot / AgendaSnapshotItem and the app-group keys come from the
// shared Shared/AgendaSnapshotShared.swift, compiled into this target too.
extension AgendaSnapshot: @retroactive TimelineEntry { public var date: Date { generatedAt } }

private extension AgendaSnapshotItem {
    /// Match the app Agenda: when both dates exist, use the earlier one.
    var relevantDate: Date? { [scheduled, deadline].compactMap { $0 }.min() }
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaSnapshot { .init(generatedAt: .now, items: []) }
    func getSnapshot(in context: Context, completion: @escaping (AgendaSnapshot) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaSnapshot>) -> Void) {
        let snapshot = load()
        completion(Timeline(entries: [snapshot], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
    private func load() -> AgendaSnapshot { loadAgendaSnapshot() }
}
private extension JSONDecoder { static let orgSync: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }() }
private extension JSONEncoder { static let orgSync: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }() }

/// Reads the shared agenda snapshot from the app group; empty when absent.
func loadAgendaSnapshot() -> AgendaSnapshot {
    guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AgendaSnapshot.appGroupIdentifier),
          let data = try? Data(contentsOf: root.appendingPathComponent(AgendaSnapshot.fileName)),
          let value = try? JSONDecoder.orgSync.decode(AgendaSnapshot.self, from: data) else {
        return .init(generatedAt: .now, items: [])
    }
    return value
}

// MARK: - Configurable time range

/// User-selectable window for the scheduled-TODO widget, chosen from the Home
/// Screen "Edit Widget" panel.
enum AgendaTimeRange: String {
    case today
    case week
    case upcoming

    init(configValue: String) {
        // Stored config values may be raw identifiers or the localized picker
        // labels (in whatever language the widget was configured under).
        switch configValue.lowercased() {
        case "today", String(localized: "Today").lowercased(): self = .today
        case "week", "this week", String(localized: "This Week").lowercased(): self = .week
        default: self = .upcoming
        }
    }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .week: String(localized: "This Week")
        case .upcoming: String(localized: "Upcoming")
        }
    }

    var emptyText: String {
        switch self {
        case .today: String(localized: "Nothing scheduled for today.")
        case .week: String(localized: "Nothing scheduled this week.")
        case .upcoming: String(localized: "Scheduled TODOs appear here.")
        }
    }

    /// Keeps only items with a SCHEDULED date inside this window, earliest
    /// first. Deadlines deliberately do not affect this widget's range.
    func filter(_ items: [AgendaSnapshotItem]) -> [AgendaSnapshotItem] {
        let window: AgendaDateWindow = switch self {
        case .today: .todayAndOverdue
        case .week: .upcoming(days: 7, includesOverdue: true)
        case .upcoming: .all
        }
        // This widget deliberately keys on SCHEDULED only (deadlines don't
        // affect its range); the window boundaries themselves come from the
        // shared AgendaDateWindow so they match the app and Siri exactly.
        return items.compactMap { item -> (item: AgendaSnapshotItem, date: Date)? in
            guard let date = item.scheduled else { return nil }
            return (item, date)
        }
        .filter { window.contains($0.date) }
        .sorted { $0.date < $1.date }.map(\.item)
    }
}

/// Strings are used for the widget configuration because WidgetKit does not
/// reliably deserialize this extension's AppEnum value on-device. A dynamic
/// options provider still presents this as a fixed Edit Widget picker.
struct ScheduledRangeOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        [String(localized: "Today"), String(localized: "This Week"), String(localized: "All Upcoming")]
    }

    func defaultResult() async -> String? { "upcoming" }
}

/// Configuration intent backing the Upcoming widget's Edit Widget options.
struct UpcomingConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Scheduled TODOs"
    static var description = IntentDescription("Choose the scheduled-date range to show.")

    @Parameter(title: "Date Range", default: "upcoming", optionsProvider: ScheduledRangeOptionsProvider())
    var range: String

    static var parameterSummary: some ParameterSummary {
        Summary { \.$range }
    }

}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let items: [AgendaSnapshotItem]
    let range: AgendaTimeRange
}

struct UpcomingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: .now, items: [], range: .upcoming)
    }
    func snapshot(for configuration: UpcomingConfigIntent, in context: Context) async -> UpcomingEntry {
        let range = AgendaTimeRange(configValue: configuration.range)
        return UpcomingEntry(date: .now, items: range.filter(loadAgendaSnapshot().items), range: range)
    }
    func timeline(for configuration: UpcomingConfigIntent, in context: Context) async -> Timeline<UpcomingEntry> {
        let range = AgendaTimeRange(configValue: configuration.range)
        let entry = UpcomingEntry(date: .now, items: range.filter(loadAgendaSnapshot().items), range: range)
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
        let defaults = UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier)
        var pending = defaults?.stringArray(forKey: AgendaSnapshot.pendingCompletionsKey) ?? []
        if !pending.contains(itemID) { pending.append(itemID) }
        defaults?.set(pending, forKey: AgendaSnapshot.pendingCompletionsKey)

        if let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AgendaSnapshot.appGroupIdentifier) {
            let url = root.appendingPathComponent(AgendaSnapshot.fileName)
            if let data = try? Data(contentsOf: url),
               var snapshot = try? JSONDecoder.orgSync.decode(AgendaSnapshot.self, from: data) {
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

/// Whether the app last reported Pro as unlocked. Missing value (app not yet
/// launched after install/update) counts as unlocked so the widget never locks
/// prematurely.
private var isProUnlocked: Bool {
    UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier)?
        .object(forKey: AgendaSnapshot.proUnlockedKey) as? Bool ?? true
}

/// Shown in place of widget content when Pro is required.
struct WidgetProLockView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Widgets require OrgSync Pro")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FavoritesWidget: Widget {
    let kind = "OrgSyncFavorites"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            if isProUnlocked {
                let paths = Set(UserDefaults(suiteName: AgendaSnapshot.appGroupIdentifier)?.stringArray(forKey: AgendaSnapshot.favoritesKey) ?? [])
                let favoriteItems = paths.sorted().map { path in
                    entry.items.first(where: { $0.filePath == path })
                        ?? AgendaSnapshotItem(id: path, title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, filePath: path, scheduled: nil, deadline: nil, priority: nil, tags: [])
                }
                WidgetNoteList(title: String(localized: "Favorites"), symbol: "star.fill", accent: .yellow, items: favoriteItems, empty: String(localized: "Favorite notes appear here."))
            } else {
                WidgetProLockView()
            }
        }
        .configurationDisplayName("Favorite Notes").description("Quick links to your favorite OrgSync notes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpcomingWidget: Widget {
    let kind = "OrgSyncUpcoming"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: UpcomingConfigIntent.self, provider: UpcomingProvider()) { entry in
            if isProUnlocked {
                AgendaListView(items: entry.items, range: entry.range, accent: .cyan, empty: entry.range.emptyText)
            } else {
                WidgetProLockView()
            }
        }
        .configurationDisplayName("Upcoming TODOs")
        .description("Scheduled and deadline tasks grouped by day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// One rendered line in the agenda widget: a day divider or a task under it.
enum AgendaRow {
    case day(String)
    case task(AgendaSnapshotItem)

    var isDay: Bool { if case .day = self { return true } else { return false } }

    /// Groups items by day (overdue folds into Today) with a divider before each
    /// day's tasks, days ascending and tasks within a day earliest first.
    static func build(from items: [AgendaSnapshotItem]) -> [AgendaRow] {
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
        if calendar.isDate(day, inSameDayAs: today) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) { return String(localized: "Tomorrow") }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// Fantastical-style agenda: tasks grouped under day dividers, each task a
/// completion circle plus its title (no file path, no per-row date).
struct AgendaListView: View {
    var items: [AgendaSnapshotItem]
    var range: AgendaTimeRange
    var accent: Color
    var empty: String

    // These are fitting estimates only; they do not change the row fonts or
    // spacing. The previous estimates left enough unused space for one task.
    @ScaledMetric(relativeTo: .caption2) private var dayHeight: CGFloat = 21
    @ScaledMetric(relativeTo: .footnote) private var taskHeight: CGFloat = 21

    var body: some View {
        GeometryReader { proxy in
            let rows = fitted(from: range.filter(items), in: proxy.size.height)
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

    private func taskRow(_ item: AgendaSnapshotItem) -> some View {
        HStack(spacing: 8) {
            Button(intent: CompleteTodoIntent(itemID: item.id)) {
                Image(systemName: "circle").font(.footnote).foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
            if let marks = Self.priorityMarks(item.priority) {
                Text(marks)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Priority \(item.priority ?? "")")
            }
            Link(destination: URL(string: "orgsync://note/" + item.filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!) {
                HStack(spacing: 6) {
                    Text(item.title).lineLimit(1).font(.footnote.weight(.medium))
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    if !item.tags.isEmpty {
                        Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                            .lineLimit(1)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Org priority rendered as exclamation marks: A = !!!, B = !!, C = !.
    static func priorityMarks(_ priority: String?) -> String? {
        switch priority {
        case "A": "!!!"
        case "B": "!!"
        case "C": "!"
        default: nil
        }
    }

    /// Keeps as many rows as fit the available height, never leaving a trailing
    /// day divider with no tasks under it.
    private func fitted(from items: [AgendaSnapshotItem], in height: CGFloat) -> [AgendaRow] {
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
    var title: String; var symbol: String; var accent: Color; var items: [AgendaSnapshotItem]; var empty: String

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
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                .padding(2)
        }
        .accessibilityLabel("Add task")
    }
}

@main struct OrgSyncWidgetsBundle: WidgetBundle {
    var body: some Widget { FavoritesWidget(); UpcomingWidget() }
}
