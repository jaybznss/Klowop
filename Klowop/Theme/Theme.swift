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

    /// Stable per-event color (a hash that survives relaunches, unlike hashValue).
    static let eventPalette: [Color] = [.blue, .indigo, .teal, .green, .orange, .pink, .purple, .red]
    static func eventColor(_ title: String) -> Color {
        let sum = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return eventPalette[sum % eventPalette.count]
    }

    /// An event's display color: its Google calendar color if synced, else a
    /// stable color derived from the title.
    static func color(for event: CalendarEvent) -> Color {
        if let hex = event.colorHex, let color = Color(hex: hex) { return color }
        return eventColor(event.title)
    }
}

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB" hex strings (Google calendar colors).
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = Int(string, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
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

/// Gradient progress ring with rounded caps, a soft glow, animated on change.
struct ProgressRing: View {
    let progress: Double
    let gradient: LinearGradient
    var lineWidth: CGFloat = 8
    var glow: Color = .clear

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow.opacity(0.55), radius: 7)
        }
        .animation(.smooth(duration: 0.6), value: progress)
    }
}

// MARK: - Ambient "aurora" backdrop

/// Slow-drifting, blurred color blobs concentrated near the top of the screen,
/// over the grouped background — ambient light that makes each screen feel alive
/// without washing out content. Tinted per life-sphere.
struct AuroraBackground: View {
    var colors: [Color]
    @State private var breathe = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            GeometryReader { geo in
                ZStack {
                    blob(colors[0], x: 0.28, y: 0.16, scale: 1.0, geo: geo)
                    blob(colors[min(1, colors.count - 1)], x: 0.76, y: 0.12, scale: 0.9, geo: geo)
                    if colors.count > 2 {
                        blob(colors[2], x: 0.52, y: 0.06, scale: 0.8, geo: geo)
                    }
                }
                .blur(radius: 70)
                // Dissolve the glow smoothly toward the middle so the blob edges
                // never read as a hard line; the grouped background takes over below.
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.32),
                        .init(color: .clear, location: 0.72),
                    ], startPoint: .top, endPoint: .bottom)
                )
                // Rasterize the static blurred glow once on the GPU, then animate a
                // cheap scale/opacity "breathing" on that cached texture — no
                // per-frame re-blur, which is what made the whole app laggy.
                .drawingGroup()
                .scaleEffect(breathe ? 1.06 : 1.0, anchor: .top)
                .opacity(breathe ? 0.52 : 0.42)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private func blob(_ color: Color, x: CGFloat, y: CGFloat, scale: CGFloat,
                      geo: GeometryProxy) -> some View {
        Circle()
            .fill(color)
            .frame(width: geo.size.width * scale, height: geo.size.width * scale)
            .position(x: geo.size.width * x, y: geo.size.height * y)
    }
}

extension View {
    /// Soft colored glow for hero surfaces and key numbers.
    func glow(_ color: Color, radius: CGFloat = 18) -> some View {
        shadow(color: color.opacity(0.35), radius: radius, y: 6)
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
