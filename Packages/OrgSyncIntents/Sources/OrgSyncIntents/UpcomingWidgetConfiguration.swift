import AppIntents

/// Widget configuration types live in this package so the app and widget
/// archive the same AppEnum identity. An extension-only intent deserializes
/// under Xcode installs and fails TestFlight Edit Widget with "Unable to load".
public enum AgendaWidgetRange: String, AppEnum, CaseIterable, Sendable {
    case today
    case week
    case upcoming

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Date Range")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: "Today",
        .week: "This Week",
        .upcoming: "All Upcoming",
    ]
}

public struct UpcomingConfigIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Scheduled TODOs"
    public static let description = IntentDescription("Choose the scheduled-date range to show.")

    @Parameter(title: "Date Range", default: .upcoming)
    public var range: AgendaWidgetRange

    public static var parameterSummary: some ParameterSummary {
        Summary { \.$range }
    }

    public init() {
        range = .upcoming
    }

    public init(range: AgendaWidgetRange) {
        self.range = range
    }
}
