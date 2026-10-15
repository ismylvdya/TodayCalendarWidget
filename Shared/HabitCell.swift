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
    /// Показать значок заметки (только в приложении).
    var hasNote = false

    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.3, style: .continuous) }
    private var undone: Color { color.opacity(style.undoneOpacity) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            cell
            if hasNote {
                // Прозрачная обводка вокруг значка: равномерно вырезаем чуть увеличенный силуэт.
                NoteBadge(size: badgeSize, lineWidth: badgeSize * 0.16, cutout: true)
                    .blendMode(.destinationOut)
                    .offset(x: badgeOffset.width, y: badgeOffset.height)
            }
        }
        .compositingGroup()
        .overlay(alignment: .bottomTrailing) {
            if hasNote {
                NoteBadge(size: badgeSize, lineWidth: 0, cutout: false)
                    .offset(x: badgeOffset.width, y: badgeOffset.height)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var cell: some View {
        ZStack {
            shape.fill(undone)
            switch state {
            case .none:
                if isToday { shape.strokeBorder(.secondary, lineWidth: 1.5) }
            case .done:
                shape.fill(color).widgetAccentable()
            case .partial:
                partial
            case .over:
                shape.fill(color).widgetAccentable()
                icon(style.overSymbol, scale: style.overIconScale, hex: overIconHex) { overLook($0) }
            }
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
        case .half:
            HStack(spacing: 0) {
                color.widgetAccentable()
                Color.clear
            }
            .clipShape(shape)
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

    var body: some View {
        let w = size * 0.78, h = size
        if cutout {
            DocShape()
                .stroke(.black, style: StrokeStyle(lineWidth: lineWidth * 2, lineJoin: .round))
                .background(DocShape().fill(.black))
                .frame(width: w, height: h)
        } else {
            ZStack {
                DocShape().fill(Color.secondary)
                DocFold().fill(Color.secondary.opacity(0.6))
            }
            .frame(width: w, height: h)
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
