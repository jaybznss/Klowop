import SwiftUI

/// Klowop design language.
///
/// Each life-sphere has a signature gradient used consistently across card
/// headers, rings, charts, and hero surfaces. Content sits on flat grouped
/// backgrounds; gradients are reserved for identity moments.
enum Theme {
    static let cornerRadius: CGFloat = 20

    // Base accents
    static let nutrition = Color.green
    static let agenda = Color.blue
    static let finance = Color.indigo
    static let assistant = Color.purple

    // Signature gradients
    static let nutritionGradient = LinearGradient(
        colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let agendaGradient = LinearGradient(
        colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let financeGradient = LinearGradient(
        colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let assistantGradient = LinearGradient(
        colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let activityGradient = LinearGradient(
        colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let bodyGradient = LinearGradient(
        colors: [.cyan, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let budgetGradient = LinearGradient(
        colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Card chrome

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

/// Apple Health-style card header: a small gradient icon tile next to the title.
/// Embeds its own trailing Spacer, so trailing controls can follow it in an HStack.
struct CardHeader: View {
    let title: String
    let symbol: String
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(gradient, in: .rect(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.headline)
            Spacer(minLength: 0)
        }
    }
}

/// Gradient progress ring with rounded caps, animated on value changes.
struct ProgressRing: View {
    let progress: Double
    let gradient: LinearGradient
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth(duration: 0.6), value: progress)
    }
}

// MARK: - Formatting helpers

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
