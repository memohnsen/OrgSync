//
//  AgendaSnapshotShared.swift
//  OrgSync + OrgSyncWidgets
//
//  The single source of truth for the widget payload and app-group storage
//  locations, compiled into BOTH the app and the widget target. It replaces the
//  field-for-field copies the widget used to keep, so a change to the model or a
//  key can't silently desynchronize the two.
//

import Foundation

/// Compact, Codable agenda payload written to the app group and read by widgets.
struct AgendaSnapshot: Codable {
    static let appGroupIdentifier = "group.com.memohnsen.OrgSync"
    static let fileName = "agenda-snapshot.json"
    /// App-group key holding snapshot ids the widget asked to complete but that
    /// the app hasn't yet written into the notes.
    static let pendingCompletionsKey = "widget.pendingCompletions"
    /// App-group key holding the favorite notes' relative paths.
    static let favoritesKey = "favorites.relativePaths"
    /// App-group key mirroring whether Pro features (widgets among them) are
    /// unlocked. Written by the app's SubscriptionStore; read by the widgets.
    /// Absent (fresh install, app not yet launched) counts as unlocked so the
    /// widget never shows a lock before the app has had a chance to check.
    static let proUnlockedKey = "subscription.proUnlocked"

    var generatedAt: Date
    var items: [AgendaSnapshotItem]
}

struct AgendaSnapshotItem: Codable, Identifiable {
    var id: String
    var title: String
    var filePath: String
    var scheduled: Date?
    var deadline: Date?
    var priority: String?
    var tags: [String]
}

extension AgendaSnapshotItem {
    var isCalendarEvent: Bool { filePath == "calendar.org" }

    var showsWidgetCompleteControl: Bool { !isCalendarEvent }

    func widgetTrailingMeta(
        allDayText: String,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        if isCalendarEvent {
            return widgetEventTimeText(allDayText: allDayText, calendar: calendar, locale: locale)
        }
        guard !tags.isEmpty else { return nil }
        return tags.map { "#\($0)" }.joined(separator: " ")
    }

    private func widgetEventTimeText(
        allDayText: String,
        calendar: Calendar,
        locale: Locale
    ) -> String? {
        guard let scheduled else { return nil }
        let comps = calendar.dateComponents([.hour, .minute], from: scheduled)
        if (comps.hour ?? 0) == 0 && (comps.minute ?? 0) == 0 {
            return allDayText
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: scheduled)
    }
}

/// The single definition of agenda date windows, used by every surface — the
/// Agenda tab, the Siri intents, and the widget — so "today" and "this week"
/// can never drift apart between them. What varies per surface (which date a
/// task contributes, whether overdue items belong in an upcoming window) is an
/// explicit choice at the call site, not a re-implementation.
enum AgendaDateWindow: Sendable {
    /// Today plus anything overdue.
    case todayAndOverdue
    /// From today's midnight through `days` days out. `includesOverdue` pulls
    /// overdue items in (Siri, widget); the Agenda tab's Upcoming scope
    /// excludes them because it shows overdue under Today instead.
    case upcoming(days: Int, includesOverdue: Bool)
    /// No bounds.
    case all

    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .todayAndOverdue:
            guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return false }
            return date < startOfTomorrow
        case let .upcoming(days, includesOverdue):
            guard let end = calendar.date(byAdding: .day, value: days, to: startOfToday) else { return false }
            return date < end && (includesOverdue || date >= startOfToday)
        case .all:
            return true
        }
    }
}

enum AgendaListLayout {
    enum Slot: Equatable {
        case day
        case task
    }

    static let rowSpacing: CGFloat = 4
    static let dayHeaderTopPadding: CGFloat = 1
    static let dayHeaderBottomPadding: CGFloat = 6
    static let listBottomPadding: CGFloat = 8
    static let dayHeight: CGFloat = 21
    static let taskHeight: CGFloat = 21
    static let mediumWidgetHeight: CGFloat = 158
    static let widgetContentMargin: CGFloat = 16

    static var mediumContentHeight: CGFloat {
        mediumWidgetHeight - widgetContentMargin * 2
    }

    static func packedHeight(dayCount: Int, taskCount: Int) -> CGFloat {
        CGFloat(dayCount) * dayHeight + CGFloat(taskCount) * taskHeight
    }

    static func fitted(
        _ slots: [Slot],
        in height: CGFloat,
        dayHeight: CGFloat,
        taskHeight: CGFloat
    ) -> [Slot] {
        var used: CGFloat = 0
        var result: [Slot] = []
        for slot in slots {
            let rowHeight = slot == .day ? dayHeight : taskHeight
            if used + rowHeight > height { break }
            used += rowHeight
            result.append(slot)
        }
        if result.last == .day { result.removeLast() }
        return result
    }
}
