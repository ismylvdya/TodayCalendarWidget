import EventKit
import SwiftUI
import WidgetKit

/// iOS-приложение нужно только для доступа к календарю: виджет сам запросить его не может.
@main
struct TripleTodayApp: App {
    var body: some Scene {
        WindowGroup {
            AccessView()
                // Нажатие на виджет может прийти сюда (calshow:<дата>) — сразу открываем Calendar.
                .onOpenURL { url in
                    if url.scheme == "calshow" { UIApplication.shared.open(url) }
                }
        }
    }
}

struct AccessView: View {
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    @Environment(\.scenePhase) private var scenePhase
    private let store = EKEventStore()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: status == .fullAccess ? "checkmark.circle.fill" : "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(status == .fullAccess ? .green : .orange)
            Text("TodayCalendarWidget").font(.title.bold())
            if status == .fullAccess {
                Text("Calendar access granted. Add the Double Today widget to your Home Screen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("The widget needs full access to your calendars.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(status == .notDetermined ? "Allow Calendar Access" : "Open Settings") { requestAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .onAppear {
            if status == .notDetermined { requestAccess() }
            #if DEBUG
            DebugSeed.runIfRequested(store: store)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // Открытие приложения — заодно повод сразу обновить виджет.
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func requestAccess() {
        if status == .notDetermined {
            store.requestFullAccessToEvents { _, _ in
                DispatchQueue.main.async { refresh() }
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func refresh() {
        status = EKEventStore.authorizationStatus(for: .event)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#if DEBUG
/// Для проверки в симуляторе: запуск с аргументом `-SeedSampleEvents` добавляет
/// в календарь по умолчанию тестовые события на сегодня (один раз).
enum DebugSeed {
    static func runIfRequested(store: EKEventStore) {
        guard ProcessInfo.processInfo.arguments.contains("-SeedSampleEvents"),
              EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.defaultCalendarForNewEvents else { return }
        let day = Calendar.current.startOfDay(for: Date())
        let existing = store.events(matching: store.predicateForEvents(withStart: day, end: day.addingTimeInterval(86400), calendars: nil))
        guard existing.isEmpty else { return }
        let samples: [(String, Double, Double, Bool)] = [
            ("pay bills", 0, 24, true), ("workout", 7.5, 0.5, false), ("call", 10, 1, false),
            ("long workshop", 11, 2.5, false), ("meeting", 12, 3, false), ("call mom", 18, 0.5, false),
            ("market?", 19, 1, false),
        ]
        for (title, start, duration, allDay) in samples {
            let ev = EKEvent(eventStore: store)
            ev.title = title
            ev.calendar = calendar
            ev.isAllDay = allDay
            ev.startDate = day.addingTimeInterval(start * 3600)
            ev.endDate = ev.startDate.addingTimeInterval(duration * 3600 - (allDay ? 1 : 0))
            try? store.save(ev, span: .thisEvent, commit: false)
        }
        try? store.commit()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
