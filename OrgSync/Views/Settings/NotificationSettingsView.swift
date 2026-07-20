//
//  NotificationSettingsView.swift
//  OrgSync
//
//  Dedicated notifications page, pushed from Settings. Master toggle, the
//  time-of-day (or off) for all-day TODOs, and a multi-select of lead times
//  for timed TODOs. Custom lead times can be entered in minutes, hours, or
//  days; everything persists as minutes in SettingsStore.
//

import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(TodoNotificationScheduler.self) private var scheduler: TodoNotificationScheduler?

    /// Built-in lead-time choices, in minutes before the event.
    static let standardOffsets = [0, 5, 10, 15, 30, 60]

    @State private var isAddingCustomOffset = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("TODO Notifications", isOn: $settings.todoNotifications)
                    .accessibilityIdentifier("settings.todoNotifications")
                    .accessibilityHint("Sends local notifications for scheduled and deadline TODOs.")
                    .onChange(of: settings.todoNotifications) { _, enabled in
                        if enabled { Task { await scheduler?.requestAuthorization() } }
                    }
                if settings.todoNotifications, scheduler?.authorization == .denied {
                    Link("Notifications are off for OrgSync — open Settings",
                         destination: URL(string: UIApplication.openSettingsURLString)!)
                        .accessibilityHint("Opens iOS Settings, where you can allow notifications for OrgSync.")
                }
            } footer: {
                Text("Notifications are a layer on top of your notes — nothing is written into the org files.")
            }

            if settings.todoNotifications {
                Section {
                    Toggle("Notify for All-Day TODOs", isOn: allDayEnabled)
                        .accessibilityIdentifier("settings.notifications.allDay")
                    if settings.allDayNotificationMinutes != nil {
                        DatePicker("Time", selection: allDayTime, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("settings.notifications.allDayTime")
                    }
                } header: {
                    Text("All-Day TODOs")
                } footer: {
                    Text("TODOs dated without a time notify once, at this time of day.")
                }

                Section {
                    ForEach(Self.standardOffsets, id: \.self) { offset in
                        offsetRow(offset)
                    }
                    ForEach(customOffsets, id: \.self) { offset in
                        offsetRow(offset)
                    }
                    .onDelete { indexSet in
                        for offset in indexSet.map({ customOffsets[$0] }) {
                            settings.timedNotificationOffsets.removeAll { $0 == offset }
                        }
                    }
                    Button {
                        isAddingCustomOffset = true
                    } label: {
                        Label("Add Custom Lead Time", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("settings.notifications.addCustomOffset")
                } header: {
                    Text("Timed TODOs")
                } footer: {
                    Text("TODOs dated with a time can notify at several lead times. Swipe to remove a custom lead time.")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        // iOS 27 draws a solid bar with a hard cutoff on scroll; keep the
        // pre-27 translucent look.
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await scheduler?.refreshAuthorization() }
        .sheet(isPresented: $isAddingCustomOffset) {
            CustomLeadTimeSheet { minutes in
                if minutes > 0, !settings.timedNotificationOffsets.contains(minutes) {
                    settings.timedNotificationOffsets.append(minutes)
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func offsetRow(_ offset: Int) -> some View {
        let isSelected = settings.timedNotificationOffsets.contains(offset)
        Button {
            toggleOffset(offset)
        } label: {
            HStack {
                Text(offsetTitle(offset))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .tint(.primary)
        .accessibilityIdentifier("settings.notifications.offset.\(offset)")
        .accessibilityLabel(offsetTitle(offset))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles this lead time for timed TODO notifications.")
    }

    private func offsetTitle(_ offset: Int) -> String {
        offset == 0 ? "At time of event" : "\(TodoNotificationPlanner.offsetLabel(offset)) before"
    }

    // MARK: - Mutations

    /// Custom (non-standard) selected offsets, shown after the built-in rows.
    private var customOffsets: [Int] {
        settings.timedNotificationOffsets
            .filter { !Self.standardOffsets.contains($0) }
            .sorted()
    }

    private func toggleOffset(_ offset: Int) {
        if let index = settings.timedNotificationOffsets.firstIndex(of: offset) {
            settings.timedNotificationOffsets.remove(at: index)
        } else {
            settings.timedNotificationOffsets.append(offset)
        }
    }

    // MARK: - All-day bindings

    private var allDayEnabled: Binding<Bool> {
        Binding(
            get: { settings.allDayNotificationMinutes != nil },
            set: { settings.allDayNotificationMinutes = $0 ? 9 * 60 : nil }
        )
    }

    private var allDayTime: Binding<Date> {
        Binding(
            get: {
                let minutes = settings.allDayNotificationMinutes ?? 9 * 60
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                settings.allDayNotificationMinutes = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
            }
        )
    }
}

/// Sheet for entering a custom lead time as an amount plus a unit
/// (minutes, hours, or days). Reports the result converted to minutes.
private struct CustomLeadTimeSheet: View {
    enum Unit: String, CaseIterable, Identifiable {
        case minutes = "Minutes"
        case hours = "Hours"
        case days = "Days"
        var id: String { rawValue }
        var minutesMultiplier: Int {
            switch self {
            case .minutes: 1
            case .hours: 60
            case .days: 24 * 60
            }
        }
    }

    let onAdd: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var unit: Unit = .minutes
    @FocusState private var amountFocused: Bool

    private var minutes: Int? {
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else { return nil }
        let total = amount * unit.minutesMultiplier
        // Keep fire dates sane: at most 30 days of lead time.
        return total <= 30 * 24 * 60 ? total : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                        .focused($amountFocused)
                        .accessibilityIdentifier("settings.notifications.customAmount")
                    Picker("Unit", selection: $unit) {
                        ForEach(Unit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.notifications.customUnit")
                } footer: {
                    Text("Notify this long before a timed TODO, up to 30 days.")
                }
            }
            .navigationTitle("Custom Lead Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let minutes { onAdd(minutes) }
                        dismiss()
                    }
                    .disabled(minutes == nil)
                    .accessibilityIdentifier("settings.notifications.customAdd")
                }
            }
            .task { amountFocused = true }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
            .environment(SettingsStore())
    }
}
