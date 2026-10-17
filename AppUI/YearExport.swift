import Photos
import SwiftUI

/// Экспорт привычки картинкой: месяцы по три в ряд, вместо чисел — дни-квадраты (сделано —
/// цвет привычки, иначе — бледный). Сверху название привычки её цветом, над месяцами каждого
/// года — год. Ширина картинки 1080 px, высота — по периоду. Сохраняется в Фото.
struct YearExportSheet: View {
    let habit: Habit
    @Environment(\.dismiss) private var dismiss
    @State private var fromMonth: Int
    @State private var fromYear: Int
    @State private var toMonth: Int
    @State private var toYear: Int
    @State private var saving = false

    private let years: [Int]
    private static let months = Calendar.current.monthSymbols

    init(habit: Habit) {
        self.habit = habit
        let cal = Calendar.current
        let now = cal.component(.year, from: Date())
        let first = habit.firstMarkedDay.map { cal.component(.year, from: $0) } ?? now
        years = Array(min(first, now - 1)...(now + 1))
        _fromMonth = State(initialValue: 1)
        _fromYear = State(initialValue: now)
        _toMonth = State(initialValue: 12)
        _toYear = State(initialValue: now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("From") { monthYear(month: $fromMonth, year: $fromYear) }
                Section("To") { monthYear(month: $toMonth, year: $toYear) }
            }
            .navigationTitle("Export Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { Task { await export() } }.disabled(saving)
                }
            }
            // «По» не раньше «С»: сдвигаем другой край вслед.
            .onChange(of: fromYear * 12 + fromMonth) { _, from in
                if toYear * 12 + toMonth < from { toYear = fromYear; toMonth = fromMonth }
            }
            .onChange(of: toYear * 12 + toMonth) { _, to in
                if to < fromYear * 12 + fromMonth { fromYear = toYear; fromMonth = toMonth }
            }
        }
    }

    private func monthYear(month: Binding<Int>, year: Binding<Int>) -> some View {
        HStack(spacing: 0) {
            Picker("Month", selection: month) {
                ForEach(1...12, id: \.self) { Text(Self.months[$0 - 1]).tag($0) }
            }
            Picker("Year", selection: year) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 140)
    }

    @MainActor private func export() async {
        saving = true
        defer { saving = false }
        let cal = Calendar.current
        guard let from = cal.date(from: DateComponents(year: fromYear, month: fromMonth, day: 1)),
              let to = cal.date(from: DateComponents(year: toYear, month: toMonth, day: 1)) else { return }
        let renderer = ImageRenderer(content: YearExportImage(habit: habit, from: from, to: to))
        renderer.scale = 1080 / YearExportImage.width
        // На белом холсте целой высоты: иначе дробный край картинки уходил в чёрную полоску.
        guard let rendered = renderer.uiImage else {
            Toast.show("Couldn't make the image", error: true)
            return
        }
        let size = CGSize(width: 1080, height: ceil(rendered.size.height * rendered.scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            rendered.draw(in: CGRect(x: 0, y: 0, width: size.width, height: rendered.size.height * rendered.scale))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.95) else {
            Toast.show("Couldn't make the image", error: true)
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            Toast.show("No access to Photos — allow adding photos in Settings → Apps → Habits.", error: true)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil)
            }
            Toast.show("Saved to Photos")
            dismiss()
        } catch {
            Toast.show("Couldn't save to Photos: \(error.localizedDescription)", error: true)
        }
    }
}

/// Сама картинка (в точках; при сохранении масштабируется до 1080 px в ширину).
struct YearExportImage: View {
    static let width: CGFloat = 360
    let habit: Habit
    let from: Date
    let to: Date

    private let pad: CGFloat = 18
    private let columnGap: CGFloat = 14
    private let gap: CGFloat = 2
    private var monthWidth: CGFloat { (Self.width - 2 * pad - 2 * columnGap) / 3 }
    private var cell: CGFloat { (monthWidth - 6 * gap) / 7 }

    /// Месяцы периода, по годам.
    private var years: [(year: Int, months: [Date])] {
        let cal = Calendar.current
        var result: [(Int, [Date])] = []
        var month = from
        while month <= to {
            let year = cal.component(.year, from: month)
            if result.last?.0 == year { result[result.count - 1].1.append(month) } else { result.append((year, [month])) }
            month = cal.date(byAdding: .month, value: 1, to: month)!
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Размер названия — как у заголовка на странице привычки относительно ширины экрана.
            Text(habit.title)
                .font(.system(size: 34 * Self.width / UIScreen.main.bounds.width, weight: .bold, design: .rounded))
                .foregroundStyle(habit.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            ForEach(years, id: \.year) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(group.year))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                    // Каждый год — с первого места строки.
                    let rows = stride(from: 0, to: group.months.count, by: 3).map { Array(group.months[$0..<min($0 + 3, group.months.count)]) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: columnGap) {
                            ForEach(row, id: \.self) { month(at: $0) }
                            ForEach(0..<(3 - row.count), id: \.self) { _ in Color.clear.frame(width: monthWidth, height: 1) }
                        }
                    }
                }
            }
        }
        .padding(pad)
        .frame(width: Self.width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func month(at start: Date) -> some View {
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        // Пустые места до первого дня — по первому дню недели системы.
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead)
            + (0..<days).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        let undone = habit.color.opacity(HabitSettings.style.undoneOpacity)
        return VStack(alignment: .leading, spacing: 6) {
            Text(formatter.string(from: start).capitalized)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                            let shape = RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous)
                            if let day {
                                shape.fill(habit.isDone(day) ? habit.color : undone).frame(width: cell, height: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: monthWidth, alignment: .leading)
    }
}
