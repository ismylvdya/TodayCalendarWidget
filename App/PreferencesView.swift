import SwiftUI
import WidgetKit

/// Окно настроек на Mac — те же настройки календаря, что в приложении на iPhone
/// (Calendar Enhancer Settings), кроме выбора иконки. Изменения сразу видят виджеты.
struct PreferencesView: View {
    @AppStorage(CalendarSettings.Key.alertsEnabled, store: AppGroup.defaults) private var alertsEnabled = true
    @AppStorage(CalendarSettings.Key.keepAfterTap, store: AppGroup.defaults) private var keepAfterTap = true
    @AppStorage(CalendarSettings.Key.keepAfterSwipe, store: AppGroup.defaults) private var keepAfterSwipe = true
    @AppStorage(CalendarSettings.Key.notifyMovedIntoPast, store: AppGroup.defaults) private var notifyMovedIntoPast = true
    @AppStorage(CalendarSettings.Key.removeWhenMovedLater, store: AppGroup.defaults) private var removeMovedLater = true
    @AppStorage(CalendarSettings.Key.removeWhenDeleted, store: AppGroup.defaults) private var removeDeleted = true
    @AppStorage(CalendarSettings.Key.staleLabelMinutes, store: AppGroup.defaults) private var staleMinutes = 30
    @AppStorage(CalendarSettings.Key.cursorHex, store: AppGroup.defaults) private var cursorHex = CalendarSettings.defaultCursorHex
    @AppStorage(CalendarSettings.Key.cursorOverEventOpacity, store: AppGroup.defaults) private var cursorOverEvent = 0.7
    @AppStorage(CalendarSettings.Key.bellOpacityLight, store: AppGroup.defaults) private var bellLight = 0.5
    @AppStorage(CalendarSettings.Key.bellOpacityDark, store: AppGroup.defaults) private var bellDark = 0.7
    @AppStorage(CalendarSettings.Key.bellHexLight, store: AppGroup.defaults) private var bellHexLight = ""
    @AppStorage(CalendarSettings.Key.bellHexDark, store: AppGroup.defaults) private var bellHexDark = ""
    @AppStorage(CalendarSettings.Key.darkBackgroundHex, store: AppGroup.defaults) private var darkBackgroundHex = ""
    @AppStorage(CalendarSettings.Key.darkGradient, store: AppGroup.defaults) private var darkGradient = true
    @AppStorage(CalendarSettings.Key.bellInsetTop, store: AppGroup.defaults) private var bellInsetTop = 3.0
    @AppStorage(CalendarSettings.Key.defaultDayStart, store: AppGroup.defaults) private var dayStart = 6
    @AppStorage(CalendarSettings.Key.defaultDayEnd, store: AppGroup.defaults) private var dayEnd = 24

    /// После изменения настроек — обновить виджеты и уведомления.
    let changed: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Alert Notifications", isOn: $alertsEnabled)
                Toggle("Keep Notification After Click", isOn: $keepAfterTap)
                Toggle("Keep Notification After Closing", isOn: $keepAfterSwipe)
                Toggle("Notify When Event Moves Earlier Than Now", isOn: $notifyMovedIntoPast)
                Toggle("Remove When Event Moves Later", isOn: $removeMovedLater)
                Toggle("Remove When Event Is Deleted", isOn: $removeDeleted)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Notifications for events with alerts are scheduled \(CalendarSettings.alertDaysAhead) days ahead. If an event is moved so that its alert time has already passed, the alert comes right away.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Default Day Start", selection: $dayStart) { ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) } }
                Picker("Default Day End", selection: $dayEnd) { ForEach(0...24, id: \.self) { Text("\($0):00").tag($0) } }
                Stepper("Show “synced N min ago” after \(staleMinutes) min", value: $staleMinutes, in: 5...240, step: 5)
                HexRow(title: "Cursor Color", hex: Binding(get: { cursorHex }, set: { cursorHex = String($0.prefix(7)) }))
                LabeledContent("Cursor over events: \(Int((cursorOverEvent * 100).rounded()))%") {
                    Slider(value: $cursorOverEvent, in: 0...1).frame(width: 180)
                }
                Stepper("Bell from top: \(Int(bellInsetTop)) pt", value: $bellInsetTop, in: 0...10, step: 1)
            } header: {
                Text("Widget")
            } footer: {
                Text("Default Day Start and End apply to calendar widgets whose Day start/end is set to “Default”.")
                    .foregroundStyle(.secondary)
            }

            Section("Light") {
                HexRow(title: "Alert bell color", hex: $bellHexLight, placeholder: "Calendar color")
                LabeledContent("Alert bell opacity: \(Int((bellLight * 100).rounded()))%") {
                    Slider(value: $bellLight, in: 0...1).frame(width: 180)
                }
            }

            Section("Dark") {
                HexRow(title: "Background color", hex: Binding(get: { darkBackgroundHex.isEmpty ? CalendarSettings.defaultDarkBackgroundHex : darkBackgroundHex },
                                                               set: { darkBackgroundHex = String($0.prefix(7)) }))
                Toggle("Background gradient", isOn: $darkGradient)
                HexRow(title: "Alert bell color", hex: $bellHexDark, placeholder: "Calendar color")
                LabeledContent("Alert bell opacity: \(Int((bellDark * 100).rounded()))%") {
                    Slider(value: $bellDark, in: 0...1).frame(width: 180)
                }
            }
        }
        .formStyle(.grouped)
        // Form прокручивается и своей высоты не задаёт — без высоты окно получалось из одной шапки.
        .frame(width: 480, height: 640)
        .onChange(of: snapshot) { changed() }
    }

    /// Все значения разом — любое изменение одним onChange.
    private var snapshot: [String] {
        [alertsEnabled, keepAfterTap, keepAfterSwipe, notifyMovedIntoPast, removeMovedLater, removeDeleted, darkGradient].map(String.init)
            + [staleMinutes, dayStart, dayEnd].map(String.init)
            + [cursorOverEvent, bellLight, bellDark, bellInsetTop].map { String($0) }
            + [cursorHex, bellHexLight, bellHexDark, darkBackgroundHex]
    }
}

/// Цвет: hex-поле и палитра. Пустое поле — значение по умолчанию (подсказка в поле).
private struct HexRow: View {
    let title: String
    @Binding var hex: String
    var placeholder = "#RRGGBB"

    var body: some View {
        LabeledContent(title) {
            HStack {
                TextField("", text: $hex, prompt: Text(placeholder))
                    .font(.body.monospaced())
                    .frame(width: 130)
                ColorPicker("", selection: Binding(get: { Color(hex: hex) ?? .gray },
                                                   set: { hex = $0.macHex }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }
}

private extension Color {
    /// «#RRGGBB».
    var macHex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        func byte(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
