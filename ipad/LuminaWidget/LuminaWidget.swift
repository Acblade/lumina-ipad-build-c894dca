import AppIntents
import SwiftUI
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
    .init(id: "scene_all_off", name: "全部关闭", icon: "scene_all_off", color: "#586174"),
    .init(id: "scene_focus", name: "专注", icon: "scene_focus", color: "#465B93"),
    .init(id: "scene_concentrate", name: "集中", icon: "scene_concentrate", color: "#4B6A9B"),
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
        case .systemSmall: 2
        case .systemMedium: 6
        case .systemLarge: 6
        case .systemExtraLarge: 6
        default: 6
        }
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
            LinearGradient(
                colors: [
                    Color(red: 0.965, green: 0.972, blue: 0.985),
                    Color(red: 0.925, green: 0.940, blue: 0.965)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var globalControls: some View {
        HStack(spacing: 9) {
            Button(intent: TurnOffAllIntent()) {
                Label("关闭", systemImage: "power")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.24, blue: 0.32), Color(red: 0.32, green: 0.37, blue: 0.48)],
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
                            .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.24))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.white.opacity(0.64), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.82), lineWidth: 0.7) }
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
                Image(systemName: widgetSceneSymbol(scene.icon, name: scene.name))
                    .font(.system(size: showsGlobalControls ? 20 : 17, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: showsGlobalControls ? 34 : 30, height: showsGlobalControls ? 34 : 30)
                    .background(.white.opacity(darkForeground ? 0.28 : 0.18), in: Circle())

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

private func widgetSceneSymbol(_ icon: String?, name: String = "") -> String {
    switch icon {
    case "scene_focus", "scene_concentrate": return "viewfinder"
    case "scene_sleep": return "moon.stars.fill"
    case "scene_relax": return "leaf.fill"
    case "scene_cozy": return "flame.fill"
    case "scene_true_colors": return "paintpalette.fill"
    case "scene_off", "scene_all_off", "scene_close": return "power"
    default:
        if name.contains("专注") || name.contains("集中") { return "viewfinder" }
        if name.contains("舒适") || name.contains("放松") { return "leaf.fill" }
        if name.contains("睡") || name.contains("夜") { return "moon.stars.fill" }
        if name.contains("原色") || name.contains("颜色") { return "paintpalette.fill" }
        if name.contains("关") { return "power" }
        return "sparkles"
    }
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
