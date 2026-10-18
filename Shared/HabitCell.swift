import SwiftUI
import WidgetKit

/// Клетка дня: выполнено — цвет привычки, нет — бледный, недоделано — по настройке,
/// перевыполнено — заливка с иконкой; сегодня без отметки — обводка.
struct HabitCell: View {
    let state: HabitDayState
    let isToday: Bool
    let color: Color
    let size: CGFloat
    var style = HabitStyle()
    /// Цвета иконок у привычки (nil — по умолчанию).
    var partialIconHex: String?
    var overIconHex: String?
    var twiceIconHex: String?
    /// Пропуск сверх допустимого — вместо бледного цвета привычки цвет пропусков (свой или общий).
    var missed = false
    var missedHex: String?
    /// Показать значок заметки (только в приложении).
    var hasNote = false
    /// Несделанный день без причины — значок вопроса на месте значка заметки (только в приложении).
    var needsReason = false
    /// Свой цвет значка заметки.
    var noteIconHex: String?
    /// Непрозрачная подложка под клеткой (для поднятия в контекстном меню).
    var opaqueBackground: Color?

    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.3, style: .continuous) }
    private var undone: Color { color.opacity(style.undoneOpacity) }

    var body: some View {
        // Рамка вида — ровно клетка, без запасов и отрицательных отступов: iOS кладёт снимок
        // контекстного меню по рамке, и любое расхождение рамки и рисунка даёт сдвиг при возврате.
        ZStack(alignment: .bottomTrailing) {
            if let opaqueBackground { shape.fill(opaqueBackground) }
            cell
            // Без непрозрачной подложки обводка значков — прозрачная: вырезаем чуть увеличенный
            // силуэт из клетки. Заметка — у правого нижнего угла, знак вопроса — у правого верхнего.
            if opaqueBackground == nil {
                if hasNote {
                    DayBadgeView(badge: .note, size: badgeSize, cutout: true, color: .black)
                        .blendMode(.destinationOut)
                        .offset(x: badgeOffset.width, y: badgeOffset.height)
                }
                if needsReason {
                    DayBadgeView(badge: .question, size: badgeSize, cutout: true, color: .black)
                        .blendMode(.destinationOut)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: badgeOffset.width, y: -badgeOffset.height)
                }
            }
        }
        .compositingGroup()
        // С подложкой (в приложении) обводка — силуэт цвета подложки под значком: он часть
        // самого дня и уходит вместе с ним в меню, а полоса пропусков под днём остаётся целой.
        .overlay(alignment: .bottomTrailing) {
            if hasNote {
                ZStack {
                    if let opaqueBackground { DayBadgeView(badge: .note, size: badgeSize, cutout: true, color: opaqueBackground) }
                    DayBadgeView(badge: .note, size: badgeSize, cutout: false, color: noteColor)
                }
                .offset(x: badgeOffset.width, y: badgeOffset.height)
            }
        }
        .overlay(alignment: .topTrailing) {
            if needsReason {
                ZStack {
                    if let opaqueBackground { DayBadgeView(badge: .question, size: badgeSize, cutout: true, color: opaqueBackground) }
                    DayBadgeView(badge: .question, size: badgeSize, cutout: false, color: badgeColor)
                }
                .offset(x: badgeOffset.width, y: -badgeOffset.height)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var cell: some View {
        ZStack {
            if missed && state == .none {
                shape.fill(style.missedColor(missedHex).opacity(style.missedOpacity))
            } else {
                shape.fill(undone)
            }
            switch state {
            case .none:
                undoneMark
            case .done:
                shape.fill(color).widgetAccentable()
            case .partial:
                partial
            case .over:
                shape.fill(color).widgetAccentable()
                icon(style.overSymbol, scale: style.overIconScale, hex: overIconHex) { overLook($0) }
            case .twice:
                shape.fill(color).widgetAccentable()
                twice
            }
        }
    }

    /// Вид невыполненного дня по настройке — в цвет привычки (на пропуске — в цвет пропусков).
    @ViewBuilder private var undoneMark: some View {
        let base = missed ? style.missedColor(missedHex) : color
        switch style.undonePattern {
        case .plain:
            EmptyView()
        case .outline:
            shape.strokeBorder(base.opacity(style.undoneIconOpacity), lineWidth: max(0.5, size * style.undoneOutlineWidth)).widgetAccentable()
        case .icon:
            Image(systemName: style.undoneSymbol).resizable().scaledToFit()
                .foregroundStyle(base.opacity(style.undoneIconOpacity))
                .frame(width: size * style.undoneIconScale, height: size * style.undoneIconScale)
                .widgetAccentable()
        }
    }

    @ViewBuilder private var partial: some View {
        switch style.partialPattern {
        case .icon:
            icon(style.partialSymbol, scale: style.partialIconScale, hex: partialIconHex) {
                $0.foregroundStyle(color).widgetAccentable()
            }
        case .lighter:
            shape.fill(color.opacity(0.5)).widgetAccentable()
        case .outline:
            shape.strokeBorder(color, lineWidth: max(1.5, size * 0.08)).widgetAccentable()
        case .diagonal:
            shape.fill(color.opacity(style.undoneStripeOpacity))
            DiagonalStripes(width: style.stripeWidth).fill(color.opacity(style.doneStripeOpacity))
                .clipShape(shape).widgetAccentable()
        case .dot:
            Circle().fill(color)
                .frame(width: size * style.partialDotScale, height: size * style.partialDotScale)
                .widgetAccentable()
        case .half:
            HStack(spacing: 0) {
                color.widgetAccentable()
                Color.clear
            }
            .clipShape(shape)
        }
    }

    /// Отметка «дважды»: концентрический квадрат внутри (заливка или обводка) или иконка —
    /// своим цветом, иначе темнее дня (или светлее, по настройке).
    @ViewBuilder private var twice: some View {
        let inner = size * style.twiceInnerSize
        let innerShape = RoundedRectangle(cornerRadius: inner * 0.3, style: .continuous)
        switch style.twicePattern {
        case .innerSquare:
            twiceColored(AnyView(innerShape)).frame(width: inner, height: inner)
        case .innerOutline:
            twiceColored(AnyView(innerShape.strokeBorder(lineWidth: max(1.5, size * 0.08)))).frame(width: inner, height: inner)
        case .icon:
            icon(style.twiceSymbol, scale: style.twiceIconScale, hex: twiceIconHex) { shaded($0, darker: style.twiceDarker, darkness: style.twiceDarkness) }
        }
    }

    @ViewBuilder private func twiceColored(_ view: AnyView) -> some View {
        if let hex = twiceIconHex, let custom = Color(hex: hex) {
            view.foregroundStyle(custom)
        } else {
            shaded(view, darker: style.twiceDarker, darkness: style.twiceDarkness)
        }
    }

    /// Темнее дня (цвет привычки, смешанный с чёрным) или цвета невыполненного дня.
    @ViewBuilder private func shaded(_ view: AnyView, darker: Bool, darkness: Double) -> some View {
        if darker {
            ZStack {
                view.foregroundStyle(color)
                view.foregroundStyle(Color.black.opacity(darkness))
            }
        } else {
            undoneLook(view)
        }
    }

    /// Иконка по центру клетки (размер — доля клетки): свой цвет из `hex` или цвет по умолчанию.
    @ViewBuilder
    private func icon<V: View>(_ name: String, scale: Double, hex: String?, fallback: (AnyView) -> V) -> some View {
        let image = AnyView(Image(systemName: name).resizable().scaledToFit())
        Group {
            if let hex, let custom = Color(hex: hex) {
                image.foregroundStyle(custom)
            } else {
                fallback(image)
            }
        }
        .frame(width: size * scale, height: size * scale)
    }

    /// Иконка перевыполнения по умолчанию: темнее клетки (цвет привычки, смешанный с чёрным)
    /// или светлее — цвета невыполненного дня.
    @ViewBuilder private func overLook(_ image: AnyView) -> some View {
        if style.overIconDarker {
            // Смесь цвета привычки с чёрным: тот же оттенок, темнее на заданную долю.
            ZStack {
                image.foregroundStyle(color)
                image.foregroundStyle(Color.black.opacity(style.overIconDarkness))
            }
        } else {
            undoneLook(image)
        }
    }

    /// Цвет невыполненного дня поверх заливки: бледный цвет привычки на фоне.
    private func undoneLook(_ image: AnyView) -> some View {
        ZStack {
            image.foregroundStyle(scheme == .dark ? Color(white: 0.11) : .white)
            image.foregroundStyle(undone)
        }
    }

    /// Цвет значков дня: цвет привычки, а на подсвеченном пропуске — его полупрозрачная заливка.
    private var badgeColor: Color {
        missed && state == .none ? style.missedColor(missedHex).opacity(style.missedOpacity) : color
    }

    /// Значок заметки: свой цвет, если задан, иначе — как остальные значки.
    private var noteColor: Color {
        if let hex = noteIconHex, let custom = Color(hex: hex) { return custom }
        return badgeColor
    }

    // Значок заметки над нижним правым углом.
    private var badgeSize: CGFloat { max(8, size * 0.3) }
    private var badgeOffset: CGSize { CGSize(width: badgeSize * 0.3, height: badgeSize * 0.2) }
}

/// Значок заметки — лист с загнутым углом, без прорезей. `cutout` — силуэт, расширенный
/// на `lineWidth` во все стороны (для равномерной прозрачной обводки).
struct NoteBadge: View {
    let size: CGFloat
    let lineWidth: CGFloat
    let cutout: Bool
    var color: Color = .secondary

    var body: some View {
        let w = size * 0.78, h = size
        if cutout {
            DocShape()
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth * 2, lineJoin: .round))
                .background(DocShape().fill(color))
                .frame(width: w, height: h)
        } else {
            ZStack {
                DocShape().fill(color)
                DocFold().fill(Color.white.opacity(0.35))
            }
            .frame(width: w, height: h)
        }
    }
}

/// Значок вопроса — того же размера, что значок заметки. `cutout` — силуэт, расширенный
/// на `lineWidth`: знак, повторённый со сдвигом во все стороны.
struct QuestionBadge: View {
    let size: CGFloat
    let lineWidth: CGFloat
    let cutout: Bool
    var color: Color = .secondary

    var body: some View {
        let mark = Image(systemName: "questionmark").resizable().scaledToFit().fontWeight(.heavy)
            .frame(width: size * 0.78, height: size)
        if cutout {
            // Копии знака со сдвигом по двум окружностям и без сдвига: у маленькой точки
            // сдвиг больше её самой, и одна окружность оставляла её середину непокрытой.
            ZStack {
                mark
                ForEach(0..<12, id: \.self) { i in
                    let a = Double(i) / 12 * 2 * .pi
                    mark.offset(x: cos(a) * lineWidth, y: sin(a) * lineWidth)
                    mark.offset(x: cos(a) * lineWidth / 2, y: sin(a) * lineWidth / 2)
                }
            }
            .foregroundStyle(color)
        } else {
            mark.foregroundStyle(color)
        }
    }
}

/// Лист со срезанным правым верхним углом.
struct DocShape: Shape {
    func path(in r: CGRect) -> Path {
        let fold = r.width * 0.38, radius = r.width * 0.14
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Загнутый уголок листа.
struct DocFold: Shape {
    func path(in r: CGRect) -> Path {
        let fold = r.width * 0.38
        var p = Path()
        p.move(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY + fold))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.closeSubpath()
        return p
    }
}

/// Диагональные полосы, выровненные по диагонали клетки (из левого нижнего угла в правый
/// верхний): одна полоса проходит ровно по диагонали, поэтому углы симметричны.
struct DiagonalStripes: Shape {
    let width: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = max(1, width) * 2.0.squareRoot()   // ширина полосы вдоль x + y
        let center = rect.minX + rect.maxY         // диагональ: x + y = const
        let lo = rect.minX + rect.minY, hi = rect.maxX + rect.maxY
        let t0 = rect.minX - rect.height, t1 = rect.maxX + rect.height
        var k = ((lo - center) / (2 * w)).rounded(.down) - 1
        while center + k * 2 * w - w / 2 <= hi {
            let c1 = center + k * 2 * w - w / 2, c2 = c1 + w
            path.move(to: CGPoint(x: t0, y: c1 - t0))
            path.addLine(to: CGPoint(x: t1, y: c1 - t1))
            path.addLine(to: CGPoint(x: t1, y: c2 - t1))
            path.addLine(to: CGPoint(x: t0, y: c2 - t0))
            path.closeSubpath()
            k += 1
        }
        return path
    }
}

/// Перемычки между соседними пропусками в строке недели — пропуски выглядят одним «червяком».
/// Перемычка заполняет промежуток и уголки у скруглений, но не заходит на сами дни.
/// Значок у дня: знак вопроса — у правого верхнего угла, заметка — у правого нижнего.
enum DayBadge { case question, note }

/// Значок дня по виду.
struct DayBadgeView: View {
    let badge: DayBadge
    let size: CGFloat
    let cutout: Bool
    let color: Color

    var body: some View {
        switch badge {
        case .question: QuestionBadge(size: size, lineWidth: cutout ? size * 0.16 : 0, cutout: cutout, color: color)
        case .note: NoteBadge(size: size, lineWidth: cutout ? size * 0.16 : 0, cutout: cutout, color: color)
        }
    }
}

struct MissedLinks: View {
    /// Пропуск ли каждый из 7 дней строки.
    let flags: [Bool]
    let cell: CGFloat
    let gap: CGFloat
    let color: Color
    /// Значки дней строки: полосу под ними вырезаем тем же силуэтом, что и клетку, —
    /// прозрачная обводка значка идёт и поверх полосы.
    var badges: [[DayBadge]] = []
    /// Убрать полосу под самими днями — для полупрозрачных клеток (виджет, превью), иначе
    /// она бы просвечивала. В приложении у клеток непрозрачная подложка, и полоса под ней
    /// остаётся: когда день открывает меню, на его месте видна полоса, а не пустота.
    var cutDays = true

    private var badgeSize: CGFloat { max(8, cell * 0.3) }

    var body: some View {
        // Подложка под днями: одна полоса на каждую серию пропусков подряд (от двух дней),
        // края — по контуру крайних дней.
        Canvas { context, _ in
            var i = 0
            while i < flags.count {
                guard flags[i] else { i += 1; continue }
                var j = i
                while j + 1 < flags.count && flags[j + 1] { j += 1 }
                if j > i {
                    let rect = CGRect(x: CGFloat(i) * (cell + gap), y: 0, width: CGFloat(j - i + 1) * cell + CGFloat(j - i) * gap, height: cell)
                    var layer = context
                    layer.fill(Path(roundedRect: rect, cornerRadius: cell * 0.3, style: .continuous), with: .color(color))
                    layer.blendMode = .destinationOut
                    for k in i...j where cutDays {
                        let day = CGRect(x: CGFloat(k) * (cell + gap), y: 0, width: cell, height: cell)
                        layer.fill(Path(roundedRect: day, cornerRadius: cell * 0.3, style: .continuous), with: .color(.black))
                    }
                }
                i = j + 1
            }
        }
        .frame(width: CGFloat(flags.count) * cell + CGFloat(max(0, flags.count - 1)) * gap, height: cell)
        // Значки стоят у правых углов клетки со сдвигом (как в HabitCell): центр — на 0.09
        // размера значка левее края и на 0.3 внутрь от нижнего (заметка) или верхнего (вопрос).
        .mask {
            ZStack(alignment: .topLeading) {
                Rectangle()
                ForEach(Array(badges.enumerated()), id: \.offset) { i, dayBadges in
                    ForEach(Array(dayBadges.enumerated()), id: \.offset) { _, badge in
                        DayBadgeView(badge: badge, size: badgeSize, cutout: true, color: .black)
                            .position(x: CGFloat(i) * (cell + gap) + cell - badgeSize * 0.09,
                                      y: badge == .note ? cell - badgeSize * 0.3 : badgeSize * 0.3)
                            .blendMode(.destinationOut)
                    }
                }
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}

/// Круглый чекбокс сегодняшнего дня (главная и виджеты): пустой, отмечен, у «Twice a day» —
/// дважды (отмеченный в кольце). Пропорции — от размера 30 pt.
struct RoundCheckbox: View {
    let habit: Habit
    let size: CGFloat
    var today = HabitDay.today()

    var body: some View {
        let state = habit.state(today)
        let k = size / 30
        ZStack {
            if habit.twiceADay && state == .twice {
                // Внутри — тот же отмеченный кружок, что у обычного дня, кольцо — снаружи, с прежними
                // пропорциями (было 30 на внутренний 20) и выходит за рамку, не сдвигая соседей.
                Circle().strokeBorder(habit.color, lineWidth: 2.7 * k).frame(width: 34.5 * k, height: 34.5 * k)
                Image(systemName: "checkmark.circle.fill").resizable().frame(width: 24 * k, height: 24 * k)
            } else {
                Image(systemName: state == .none ? "circle" : "checkmark.circle.fill").resizable()
                    .frame(width: 24 * k, height: 24 * k)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(habit.color)
    }
}
