#if os(iOS)
import EventKit
import SwiftUI

/// Привязка напоминания к привычке: поиск по названию среди всех незавершённых напоминаний.
struct ReminderPickerView: View {
    /// Уже привязанные напоминания (к любой привычке) — в списке неактивны.
    var linked: Set<String> = []
    let onPick: (ReminderLink) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasAccess = ReminderSync.hasAccess
    @State private var reminders: [EKReminder] = []
    @State private var search = ""

    private var found: [EKReminder] {
        search.isEmpty ? reminders : reminders.filter { ($0.title ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !hasAccess {
                    Button("Allow Access to Reminders") { Task { hasAccess = await ReminderSync.requestAccess(); await load() } }
                }
                ForEach(found, id: \.calendarItemIdentifier) { reminder in
                    Button {
                        onPick(ReminderLink(reminderID: reminder.calendarItemIdentifier,
                                            listID: reminder.calendar.calendarIdentifier,
                                            titles: [reminder.title ?? ""]))
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title ?? "")
                                // Значков списков EventKit не отдаёт — кружок цвета списка, как в Reminders.
                                HStack(spacing: 4) {
                                    Circle().fill(Color(cgColor: reminder.calendar.cgColor)).frame(width: 7, height: 7)
                                    Text(reminder.calendar.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if reminder.hasRecurrenceRules { Image(systemName: "repeat").foregroundStyle(.secondary) }
                        }
                    }
                    .foregroundStyle(linked.contains(reminder.calendarItemIdentifier) ? .secondary : .primary)
                    .disabled(linked.contains(reminder.calendarItemIdentifier))
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Reminder name")
            .navigationTitle("Link a Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        reminders = await ReminderSync.openReminders()
    }
}
#endif
