import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct SceneEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lumina 场景")
    static var defaultQuery = SceneEntityQuery()

    let id: String
    let name: String
    let icon: String?
    let color: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Lumina 场景")
    }

    init(scene: Scene) {
        id = scene.id
        name = scene.name
        icon = scene.icon
        color = scene.color
    }

    init(id: String, name: String, icon: String?, color: String?) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }
}

private let fallbackSceneEntities: [SceneEntity] = [
    .init(id: "scene_focus", name: "专注", icon: "scene_focus", color: "#465B93"),
    .init(id: "scene_concentrate", name: "集中", icon: "scene_concentrate", color: "#4B6A9B"),
    .init(id: "scene_true_colors", name: "原色", icon: "scene_true_colors", color: "#E9C46A"),
    .init(id: "scene_daylight", name: "日光", icon: "sun.max.fill", color: "#65AEE8"),
    .init(id: "scene_cozy", name: "舒适", icon: "scene_cozy", color: "#F2B84B"),
    .init(id: "scene_relax", name: "放松", icon: "scene_relax", color: "#7C68A4"),
    .init(id: "scene_sleep", name: "睡觉", icon: "scene_sleep", color: "#514A78"),
]

private func availableSceneEntities() -> [SceneEntity] {
    let cached = SharedCache().loadScenes().map(SceneEntity.init)
    return cached.isEmpty ? fallbackSceneEntities : cached
}

struct SceneEntityQuery: EntityQuery {
    func entities(for identifiers: [SceneEntity.ID]) async throws -> [SceneEntity] {
        availableSceneEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SceneEntity] {
        availableSceneEntities()
    }
}

struct ScenePanelConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Lumina 场景面板"
    static var description = IntentDescription("选择要放在 iPad 主屏幕上的场景。")

    @Parameter(title: "场景 1") var scene1: SceneEntity?
    @Parameter(title: "场景 2") var scene2: SceneEntity?
    @Parameter(title: "场景 3") var scene3: SceneEntity?
    @Parameter(title: "场景 4") var scene4: SceneEntity?
    @Parameter(title: "场景 5") var scene5: SceneEntity?
    @Parameter(title: "场景 6") var scene6: SceneEntity?
    @Parameter(title: "场景 7") var scene7: SceneEntity?
    @Parameter(title: "场景 8") var scene8: SceneEntity?

    var selectedScenes: [SceneEntity] {
        [scene1, scene2, scene3, scene4, scene5, scene6, scene7, scene8].compactMap { $0 }
    }
}

struct LuminaEntry: TimelineEntry {
    let date: Date
    let scenes: [SceneEntity]
}

struct LuminaProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LuminaEntry {
        LuminaEntry(date: .now, scenes: Array(fallbackSceneEntities.prefix(6)))
    }

    func snapshot(for configuration: ScenePanelConfiguration, in context: Context) async -> LuminaEntry {
        entry(configuration)
    }

    func timeline(for configuration: ScenePanelConfiguration, in context: Context) async -> Timeline<LuminaEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(_ configuration: ScenePanelConfiguration) -> LuminaEntry {
        let available = availableSceneEntities()
        let scenes = configuration.selectedScenes.isEmpty ? Array(available.prefix(8)) : configuration.selectedScenes
        return LuminaEntry(date: .now, scenes: scenes)
    }
}

struct LuminaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LuminaEntry

    private var columns: [GridItem] {
        let count = family == .systemSmall ? 2 : (family == .systemMedium ? 3 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var limit: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 5
        case .systemLarge: 6
        case .systemExtraLarge: 6
        default: 6
        }
    }

    private var embedsPowerTile: Bool {
        family == .systemSmall || family == .systemMedium
    }

    private var showsGlobalControls: Bool {
        family == .systemLarge || family == .systemExtraLarge
    }

    var body: some View {
        VStack(spacing: showsGlobalControls ? 10 : 7) {
            if showsGlobalControls { globalControls }
            if entry.scenes.isEmpty {
                Text("打开 Lumina 同步场景")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: showsGlobalControls ? 9 : 6) {
                    if embedsPowerTile {
                        Button(intent: ToggleAllPowerIntent()) {
                            powerTile
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(entry.scenes.prefix(limit)) { scene in
                        Button(intent: RunSceneIntent(sceneID: scene.id)) {
                            sceneTile(scene)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            SigoWidgetBackground()
        }
    }

    private var powerTile: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.14, blue: 0.09), Color(red: 0.045, green: 0.043, blue: 0.038)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "power")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SigoWidgetTheme.gold)
                    .frame(width: 30, height: 30)
                    .background(SigoWidgetTheme.gold.opacity(0.12), in: Circle())
                Spacer(minLength: 2)
                Text("开关")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SigoWidgetTheme.ivory)
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SigoWidgetTheme.gold.opacity(0.48), lineWidth: 0.9)
        }
        .shadow(color: SigoWidgetTheme.gold.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("切换全部灯光")
    }

    private var globalControls: some View {
        HStack(spacing: 9) {
            Button(intent: ToggleAllPowerIntent()) {
                Label("开关", systemImage: "power")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SigoWidgetTheme.ivory)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.11, blue: 0.08), Color(red: 0.25, green: 0.20, blue: 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                ForEach([1, 25, 50, 75, 100], id: \.self) { value in
                    Button(intent: SetAllBrightnessIntent(brightness: value)) {
                        Text("\(value)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SigoWidgetTheme.ivory)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.34), in: Capsule())
            .overlay { Capsule().stroke(SigoWidgetTheme.gold.opacity(0.45), lineWidth: 0.7) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("亮度")
        }
    }

    private func sceneTile(_ scene: SceneEntity) -> some View {
        let darkForeground = widgetSceneUsesDarkForeground(scene.color)
        let foreground = darkForeground
            ? Color(red: 0.10, green: 0.13, blue: 0.19)
            : Color.white

        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            widgetSceneColor(scene.color).opacity(0.68),
                            widgetSceneColor(scene.color)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(.white.opacity(darkForeground ? 0.28 : 0.18))
                    WidgetSceneGlyph(scene: scene)
                        .font(.system(size: showsGlobalControls ? 17 : 15, weight: .semibold))
                        .foregroundStyle(foreground)
                        .frame(width: showsGlobalControls ? 20 : 17, height: showsGlobalControls ? 20 : 17)
                }
                .frame(width: showsGlobalControls ? 34 : 30, height: showsGlobalControls ? 34 : 30)

                Spacer(minLength: 2)

                Text(scene.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            }
            .padding(showsGlobalControls ? 10 : 8)
        }
        .frame(maxWidth: .infinity, minHeight: showsGlobalControls ? 68 : 54)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.34), lineWidth: 0.8)
        }
        .shadow(color: widgetSceneColor(scene.color).opacity(0.13), radius: 5, y: 2)
    }
}

private enum SigoWidgetTheme {
    static let gold = Color(red: 0.88, green: 0.70, blue: 0.32)
    static let ivory = Color(red: 0.97, green: 0.94, blue: 0.86)
}

private struct SigoWidgetBackground: View {
    var body: some View {
        Color(red: 0.70, green: 0.57, blue: 0.34)
    }
}

struct LuminaSceneWidget: Widget {
    let kind = "LuminaScenePanel"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ScenePanelConfiguration.self, provider: LuminaProvider()) { entry in
            LuminaWidgetView(entry: entry)
        }
        .configurationDisplayName("Lumina 场景面板")
        .description("不打开 App，直接运行场景、关闭灯光和调整总亮度。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct LuminaWidgetBundle: WidgetBundle {
    var body: some Widget { LuminaSceneWidget() }
}

private struct WidgetSceneGlyph: View {
    let scene: SceneEntity

    var body: some View {
        if AndroidSceneMark.supports(scene.id) {
            AndroidSceneMark(
                sceneID: scene.id,
                color: widgetSceneUsesDarkForeground(scene.color)
                    ? Color(red: 0.10, green: 0.13, blue: 0.19)
                    : .white
            )
        } else if let symbol = widgetSceneSymbol(sceneID: scene.id, icon: scene.icon, name: scene.name) {
            Image(systemName: symbol)
        } else {
            Text(scene.icon?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "✨")
        }
    }
}

private func widgetSceneSymbol(sceneID: String, icon: String?, name: String = "") -> String? {
    switch sceneID {
    case "scene_focus": return "viewfinder"
    case "scene_concentrate": return "scope"
    case "scene_sleep": return "moon.stars.fill"
    case "scene_relax": return "leaf.fill"
    case "scene_cozy": return "cup.and.saucer.fill"
    case "scene_true_colors": return "paintpalette.fill"
    case "scene_daylight": return "sun.max.fill"
    case "scene_off", "scene_all_off", "scene_close": return "power"
    default: break
    }
    if let icon, !icon.isEmpty, UIImage(systemName: icon) != nil { return icon }
    if name.contains("专注") { return "viewfinder" }
    if name.contains("集中") { return "scope" }
    if name.contains("舒适") { return "cup.and.saucer.fill" }
    if name.contains("放松") { return "leaf.fill" }
    if name.contains("睡") || name.contains("夜") { return "moon.stars.fill" }
    if name.contains("原色") || name.contains("颜色") { return "paintpalette.fill" }
    if name.contains("关") { return "power" }
    return nil
}

private func widgetSceneColor(_ hex: String?) -> Color {
    guard let value = hex?.replacingOccurrences(of: "#", with: ""),
          value.count == 6, let number = Int(value, radix: 16) else { return .indigo }
    return Color(
        red: Double((number >> 16) & 0xff) / 255,
        green: Double((number >> 8) & 0xff) / 255,
        blue: Double(number & 0xff) / 255
    )
}

private func widgetSceneUsesDarkForeground(_ hex: String?) -> Bool {
    guard let value = hex?.replacingOccurrences(of: "#", with: ""),
          value.count == 6,
          let number = Int(value, radix: 16) else { return false }
    let red = Double((number >> 16) & 0xff)
    let green = Double((number >> 8) & 0xff)
    let blue = Double(number & 0xff)
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255 > 0.68
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
