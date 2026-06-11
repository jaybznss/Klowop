import SwiftUI

/// Shared visual language: native Apple materials, SF type, continuous corners.
enum Theme {
    static let cornerRadius: CGFloat = 16

    static let nutrition = Color.green
    static let agenda = Color.blue
    static let finance = Color.indigo
    static let assistant = Color.purple
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .cardScrollFade()
    }
}

/// Cards gently fade and shrink as they scroll out of view.
struct CardScrollFade: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollTransition(.interactive) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0.6)
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
        }
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
    func cardScrollFade() -> some View { modifier(CardScrollFade()) }

    /// Hero treatment: a soft tinted gradient instead of the flat card fill.
    func heroCard(_ color: Color) -> some View {
        padding(16)
            .background(
                LinearGradient(colors: [color.opacity(0.16), color.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .cardScrollFade()
    }
}

extension Double {
    func asCurrency(_ code: String = "USD") -> String {
        formatted(.currency(code: code).precision(.fractionLength(2)))
    }
}

extension Date {
    var dayLabel: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInTomorrow(self) { return "Tomorrow" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month().day())
    }
}
