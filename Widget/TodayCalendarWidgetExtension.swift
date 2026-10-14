import EventKit
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    let date: Date
    let events: [DayEvent]
    let hasAccess: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date(), events: SampleData.events, hasAccess: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let now = Date()
        if CalendarData.hasAccess {
            completion(DayEntry(date: now, events: CalendarData.todayEvents(store: EKEventStore(), now: now), hasAccess: true))
        } else {
            completion(DayEntry(date: now, events: SampleData.events, hasAccess: !context.isPreview ? false : true))
        }
    }

    /// Кадры на каждую минуту в течение часа — двигается только курсор.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()