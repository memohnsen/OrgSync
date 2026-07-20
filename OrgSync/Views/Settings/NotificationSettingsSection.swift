//
//  NotificationSettingsSection.swift
//  OrgSync
//
//  Settings form section for local TODO notifications: master toggle, the
//  time-of-day (or off) for all-day TODOs, and a multi-select of lead times for
//  timed TODOs including custom minute values. Persisted via SettingsStore;
//  the scheduler in RootView reacts to these values changing.
//

import SwiftUI
import UIKit

struct NotificationSettingsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(TodoNotificationScheduler.self) private var scheduler: TodoNotificationScheduler?

    /// Built-in lead-time choices, in minutes before the event.
    static let standardOffsets = [0, 5, 10, 15, 30, 60]

    @State private var showCustomOffsetAlert = false
    @State private var customOffsetText = ""

    var body: some View {
        @Bindable var settings = settings

        Section {
            Toggle("TODO Notifications", isOn: $settings.todoNotifications)
                .accessibilityIdentifier("settings.todoNotifications")
                .accessibilityHint("Sends local notifications for scheduled and deadline TODOs.")
                .onChange(of: settings.todoNotifications) { _, enabled in
                    if enabled { Task { await scheduler?.requestAuthorization() } }
                }

            if settings.todoNotifications {
                if scheduler?.authorization == .denied {
                    Link("Notifications are off — open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                        .accessibilityHint("Opens iOS Settings, where you can allow notifications for OrgSync.")
                }

                Toggle("All-Day TODOs", isOn: allDayEnabled)
                    .accessibilityIdentifier("settings.notifications.allDay")
                    .accessibilityHint("Notifies once on the day of an all-day TODO.")
                if settings.allDayNotificationMinutes != nil {
                    DatePicker("Notify At", selection: allDayTime, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("settings.notifications.allDayTime")
                }

                ForEach(Self.standardOffsets, id: \.self) { offset in
                    offsetRow(offset)
                }
                ForEach(customOffsets, id: \.self) { offset in
                    offsetRow(offset)
                }
                Button("Add Custom Lead Time…") {
                    customOffsetText = ""
                    showCustomOffsetAlert = true
                }
                .accessibilityIdentifier("settings.notifications.addCustomOffset")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Notifications are a layer on top of your notes — nothing is written into the org files. Timed TODOs can notify at several lead times.")
        }
        .alert("Custom Lead Time", isPresented: $showCustomOffsetAlert) {
            TextField("Minutes before", text: $customOffsetText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addCustomOffset() }
        } message: {
            Text("Notify this many minutes before a timed TODO.")
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
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
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

    private func addCustomOffset() {
        guard let minutes = Int(customOffsetText.trimmingCharacters(in: .whitespaces)),
              minutes > 0, minutes <= 24 * 60,
              !settings.timedNotificationOffsets.contains(minutes) else { return }
        settings.timedNotificationOffsets.append(minutes)
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
