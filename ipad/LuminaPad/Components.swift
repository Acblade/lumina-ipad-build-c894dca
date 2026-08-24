import SwiftUI
import UIKit

enum LuminaTheme {
    static let midnight = Color(hex: "#152139")!
    static let indigo = Color(hex: "#465B93")!
    static let iris = Color(hex: "#6F76B8")!
    static let warmGold = Color(hex: "#F2B84B")!
    static let coral = Color(hex: "#ED765B")!
    static let mist = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.06, green: 0.09, blue: 0.15, alpha: 1) : UIColor(red: 0.961, green: 0.965, blue: 0.980, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1) : .white
    })
    static let cloud = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 1) : UIColor(red: 0.910, green: 0.918, blue: 0.949, alpha: 1)
    })
    static let navigation = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.10, blue: 0.17, alpha: 0.97) : UIColor(red: 0.965, green: 0.949, blue: 0.984, alpha: 0.98)
    })
    static let selectedNavigation = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.22, green: 0.28, blue: 0.45, alpha: 1) : UIColor(red: 0.867, green: 0.890, blue: 1.0, alpha: 1)
    })
}

extension View {
    func luminaCard(padding: CGFloat = 20, cornerRadius: CGFloat = 26) -> some View {
        self
            .padding(padding)
            .background(LuminaTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
    }

    func luminaPageBackground() -> some View {
        background(LuminaTheme.mist.ignoresSafeArea())
    }
}

struct LuminaPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension LuminaPageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

struct LuminaSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension LuminaSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

struct StatusPill: View {
    let online: Bool

    var body: some View {
        Label(online ? "在线" : "离线", systemImage: online ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(online ? .green : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((online ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
    }
}

struct LuminaPowerButton: View {
    let isOn: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: 54, height: 54)
                .background(isOn ? LuminaTheme.indigo : LuminaTheme.cloud, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(isOn ? "关闭" : "打开")
    }
}

struct LuminaSlidingPowerSwitch: View {
    let isOn: Bool
    let enabled: Bool
    var width: CGFloat = 78
    var height: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        enabled
                            ? (isOn ? LuminaTheme.indigo : LuminaTheme.cloud)
                            : LuminaTheme.cloud.opacity(0.55)
                    )
                Circle()
                    .fill(enabled ? LuminaTheme.surface : Color.secondary.opacity(0.18))
                    .padding(3)
                    .shadow(color: .black.opacity(isOn ? 0.10 : 0.04), radius: 3, y: 1)
            }
            .frame(width: width, height: height)
            .animation(.snappy(duration: 0.22), value: isOn)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(isOn ? "关闭" : "打开")
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

struct LuminaPillSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let colors: [Color]
    var enabled = true
    var height: CGFloat = 42
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(LuminaTheme.cloud)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height * 0.04, proxy.size.width * fraction))
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { update($0.location.x, width: proxy.size.width) }
                    .onEnded {
                        update($0.location.x, width: proxy.size.width)
                        onCommit(value)
                    }
            )
        }
        .frame(height: height)
        .opacity(enabled ? 1 : 0.55)
        .allowsHitTesting(enabled)
    }

    private var fraction: CGFloat {
        let distance = max(range.upperBound - range.lowerBound, 1)
        return CGFloat(min(max((value - range.lowerBound) / distance, 0), 1))
    }

    private func update(_ x: CGFloat, width: CGFloat) {
        guard enabled, width > 0 else { return }
        let part = Double(min(max(x / width, 0), 1))
        value = range.lowerBound + part * (range.upperBound - range.lowerBound)
    }
}

struct LuminaBrightnessTrack: View {
    let value: Int
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(LuminaTheme.cloud)
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.30), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 100)) / 100)
            }
        }
        .frame(height: 20)
        .accessibilityLabel("亮度")
        .accessibilityValue("\(value)%")
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 280)
            .luminaCard()
    }
}

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: spacing)], spacing: spacing) {
            content
        }
    }
}

func luminaAccent(for state: ZoneState) -> Color {
    if let segment = state.segmentRgb { return Color(rgb: segment.left) }
    if let rgb = state.rgb { return Color(rgb: rgb) }
    if let kelvin = state.colorTemperatureKelvin {
        let normalized = min(max(Double(kelvin - 2_200) / Double(6_500 - 2_200), 0), 1)
        return Color(red: 1 - 0.30 * normalized, green: 0.58 + 0.30 * normalized, blue: 0.24 + 0.76 * normalized)
    }
    if let sceneID = state.sceneId {
        let palettes: [Int: String] = [
            1: "#168FC8", 2: "#E46B9A", 3: "#F47A4C", 4: "#E34B72",
            5: "#F26732", 6: "#EAA64C", 7: "#3D9B62", 8: "#D58CB9",
            9: "#6B9FDE", 10: "#D96B59", 11: "#F1B866", 12: "#65B6D6",
            13: "#8DBCE8", 14: "#D05B35", 15: "#5A8FD4", 16: "#A574C8",
            17: "#E39A42", 18: "#68A9D8", 19: "#C263D8", 20: "#77B96A",
            21: "#44B7D8", 22: "#C77838", 23: "#167D9E", 24: "#3AA357",
            25: "#67C38F", 26: "#C743B7", 27: "#C1494C", 28: "#CE6D31",
            29: "#E58B32", 30: "#D6AF40", 31: "#C9B96A", 32: "#A76B38",
            33: "#C85A76", 34: "#E69A4A", 35: "#D43F43", 36: "#9DBDE2",
            40: "#D37B46"
        ]
        if let hex = palettes[sceneID], let color = Color(hex: hex) { return color }
    }
    return LuminaTheme.warmGold
}

func luminaModeSymbol(_ sceneID: Int) -> String {
    switch sceneID {
    case 34: "sun.max.fill"
    case 11: "sun.min.fill"
    case 12: "sun.max.fill"
    case 13, 36: "snowflake"
    case 40: "circle.lefthalf.filled"
    case 14, 10, 28: "moon.stars.fill"
    case 6: "cup.and.saucer.fill"
    case 17: "paintpalette.fill"
    case 16: "leaf.fill"
    case 15: "viewfinder"
    case 18: "tv.fill"
    case 19, 20: "camera.macro"
    case 9: "alarm.fill"
    case 5, 29: "flame.fill"
    case 22: "leaf.circle.fill"
    case 26: "music.note"
    case 3: "sunset.fill"
    case 2: "heart.fill"
    case 4, 33: "party.popper.fill"
    case 8: "sparkles"
    case 21: "sun.horizon.fill"
    case 7, 24, 27: "tree.fill"
    case 25, 23: "drop.fill"
    case 1: "water.waves"
    case 31: "wind"
    case 30: "rays"
    case 32: "gearshape.fill"
    case 35: "exclamationmark.triangle.fill"
    default: "sparkles"
    }
}

extension Color {
    init(rgb: RGBColor) {
        let value = rgb.normalized
        self.init(.sRGB, red: Double(value.r) / 255, green: Double(value.g) / 255, blue: Double(value.b) / 255)
    }

    init?(hex: String) {
        guard let rgb = RGBColor(hex: hex) else { return nil }
        self.init(rgb: rgb)
    }

    var rgbValue: RGBColor {
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .init(r: 255, g: 255, b: 255)
        }
        return .init(r: Int(red * 255), g: Int(green * 255), b: Int(blue * 255)).normalized
    }
}

extension Date {
    var luminaTime: String {
        formatted(date: .omitted, time: .shortened)
    }
}
