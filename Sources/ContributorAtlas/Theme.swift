import SwiftUI
import AtlasCore

extension Color {
    static let atlasCanvas = Color(nsColor: .windowBackgroundColor)
    static let atlasPanel = Color(nsColor: .controlBackgroundColor)
    static let atlasAccent = Color.accentColor
    static let atlasGreen = Color(red: 0.16, green: 0.58, blue: 0.37)
    static let atlasLine = Color.primary.opacity(0.09)
}
func compact(_ n: Int) -> String { n.formatted() }
func decimal(_ n: Double) -> String { n.formatted(.number.precision(.fractionLength(1))) }
func frequency(_ n: Double) -> String { n.formatted(.number.precision(.fractionLength(n > 0 && n < 0.01 ? 3 : 2))) }
func hourLabel(_ hour: Int) -> String { String(format: "%02d:00", hour) }
let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

struct Panel<Content: View>: View {
    var title: String
    var detail: String = ""
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(20)
        .atlasContentSurface()
    }
}

struct PersonIcon: View {
    var bot: Bool = false
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: bot ? "cpu" : "person.fill")
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(Color.secondary)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.05), in: Circle())
    }
}

struct AreaBadge: View {
    let area: WorkArea
    var body: some View {
        Label(area.rawValue, systemImage: area.symbol)
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.045), in: Capsule())
    }
}

struct EmptyResults: View {
    var reset: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No commits match these filters").font(.headline)
            Button("Reset filters", action: reset).buttonStyle(.bordered)
        }.frame(maxWidth: .infinity).padding(60)
    }
}

private struct NavigationGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.atlasPanel, in: RoundedRectangle(cornerRadius: 18))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

extension View {
    func atlasNavigationGlass() -> some View { modifier(NavigationGlass()) }
    func atlasContentSurface() -> some View {
        background(Color.atlasPanel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.atlasLine.opacity(0.65), lineWidth: 0.5))
    }
    @ViewBuilder func atlasFilterBar<Bar: View>(visible: Bool, @ViewBuilder bar: () -> Bar) -> some View {
        if visible {
            if #available(macOS 26.0, *) { safeAreaBar(edge: .top, spacing: 0, content: bar) }
            else { safeAreaInset(edge: .top, spacing: 0, content: bar) }
        } else { self }
    }
}
