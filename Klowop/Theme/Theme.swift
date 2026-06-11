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
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
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
