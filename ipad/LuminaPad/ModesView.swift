import SwiftUI

struct ModesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var customMode: LightMode?

    private let categoryOrder = ["white", "function", "progressive", "dynamic"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LuminaPageHeader("模式")

                    if model.modes.isEmpty {
                        EmptyState(icon: "sparkles", title: "还没有模式", message: "连接 Hub 并刷新后，会显示灯泡原生模式。")
                    } else {
                        ForEach(categoryOrder, id: \.self) { category in
                            let modes = model.modes.filter { $0.category == category }
                            if !modes.isEmpty {
                                modeSection(category: category, modes: modes)
                            }
                        }
                    }
                }
                .frame(maxWidth: 1320)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity)
            }
            .luminaPageBackground()
            .navigationBarHidden(true)
            .navigationDestination(item: $customMode) { mode in
                ModeApplyView(mode: mode)
            }
        }
    }

    private func modeSection(category: String, modes: [LightMode]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(categoryName(category))
                .font(.title2.bold())

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)],
                alignment: .leading,
                spacing: 22
            ) {
                ForEach(modes) { mode in
                    ModeTile(mode: mode) {
                        Task { await applyDefault(mode) }
                    } customize: {
                        customMode = mode
                    }
                }
            }
        }
    }

    private func applyDefault(_ mode: LightMode) async {
        let targets = model.devices.flatMap { device in
            device.capabilities.zones.map { ModeTarget(deviceId: device.id, zone: $0.id) }
        }
        await model.applyMode(mode, targets: targets, brightness: 70, speed: 100)
    }

    private func categoryName(_ value: String) -> String {
        switch value {
        case "white": "白光"
        case "function": "功能光"
        case "progressive": "渐进"
        case "dynamic": "动态光"
        default: value
        }
    }
}

private struct ModeTile: View {
    let mode: LightMode
    let apply: () -> Void
    let customize: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ModeLogo(mode: mode)
            Text(mode.name)
                .font(.headline)
                .foregroundStyle(LuminaTheme.midnight)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first: customize()
                    case .second: apply()
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("轻点应用，长按自定义")
        .accessibilityAction { apply() }
        .accessibilityAction(named: "自定义") { customize() }
    }
}

private struct ModeLogo: View {
    let mode: LightMode

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(gradient)
            .frame(width: 112, height: 142)
            .overlay {
                Image(systemName: luminaModeSymbol(mode.sceneId))
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
    }

    private var colors: [Color] {
        let parsed = mode.colors.compactMap(Color.init(hex:))
        return parsed.isEmpty ? [LuminaTheme.warmGold.opacity(0.70), LuminaTheme.iris] : parsed
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var iconColor: Color {
        guard let first = mode.colors.first,
              let rgb = RGBColor(hex: first) else { return .white.opacity(0.94) }
        let value = rgb.normalized
        let luminance = (0.2126 * Double(value.r) + 0.7152 * Double(value.g) + 0.0722 * Double(value.b)) / 255
        return luminance > 0.68 ? LuminaTheme.midnight.opacity(0.80) : .white.opacity(0.94)
    }
}

private struct ModeApplyView: View {
    @EnvironmentObject private var model: AppModel
    let mode: LightMode
    @State private var selectedTargets = Set<ModeTarget>()
    @State private var brightness = 70.0
    @State private var speed: Double
    @State private var initializedTargets = false

    init(mode: LightMode) {
        self.mode = mode
        let minimum = mode.speedMin ?? 20
        let maximum = mode.speedMax ?? 200
        _speed = State(initialValue: Double(min(max(100, minimum), maximum)))
    }

    private struct TargetItem: Identifiable {
        let target: ModeTarget
        let name: String
        var id: ModeTarget { target }
    }

    private var allTargets: [TargetItem] {
        model.devices.flatMap { device in
            device.capabilities.zones.map { zone in
                let name: String
                if device.capabilities.zones.count == 1 {
                    name = device.name
                } else {
                    switch zone.id.lowercased() {
                    case "main", "front": name = zone.label.isEmpty ? "前灯" : zone.label
                    case "ambient", "back": name = zone.label.isEmpty ? "背板灯" : zone.label
                    default: name = zone.label.isEmpty ? device.name : zone.label
                    }
                }
                return TargetItem(target: ModeTarget(deviceId: device.id, zone: zone.id), name: name)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !mode.description.isEmpty {
                    Text(mode.description)
                        .font(.title3.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("应用到").font(.title2.bold())
                    ForEach(allTargets) { item in
                        Button {
                            if selectedTargets.contains(item.target) {
                                selectedTargets.remove(item.target)
                            } else {
                                selectedTargets.insert(item.target)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedTargets.contains(item.target) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                Text(item.name).font(.headline)
                                Spacer()
                            }
                            .foregroundStyle(LuminaTheme.midnight)
                            .padding(.horizontal, 18)
                            .frame(height: 56)
                            .background(
                                selectedTargets.contains(item.target)
                                    ? LuminaTheme.warmGold.opacity(0.42)
                                    : LuminaTheme.surface,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    ModeControlLabel("亮度", value: "\(Int(brightness.rounded()))")
                    LuminaPillSlider(
                        value: $brightness,
                        range: 1...100,
                        colors: [Color(hex: "#FFD77A")!, Color(hex: "#FFB83E")!]
                    ) { _ in }
                }

                if mode.dynamic {
                    let minimum = Double(mode.speedMin ?? 20)
                    let maximum = Double(mode.speedMax ?? 200)
                    VStack(alignment: .leading, spacing: 9) {
                        ModeControlLabel("速度", value: "\(Int(speed.rounded()))")
                        LuminaPillSlider(
                            value: $speed,
                            range: minimum...maximum,
                            colors: [Color(hex: "#89A7FF")!, Color(hex: "#6F52D9")!]
                        ) { _ in }
                    }
                }

                Button {
                    Task {
                        await model.applyMode(
                            mode,
                            targets: Array(selectedTargets),
                            brightness: Int(brightness.rounded()),
                            speed: Int(speed.rounded())
                        )
                    }
                } label: {
                    Text(model.isLoading ? "正在应用…" : "应用模式")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                }
                .buttonStyle(.borderedProminent)
                .tint(LuminaTheme.indigo)
                .disabled(selectedTargets.isEmpty || model.isLoading)
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .luminaPageBackground()
        .navigationTitle(mode.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.devices.map(\.id)) {
            guard !initializedTargets else { return }
            selectedTargets = Set(allTargets.map(\.target))
            initializedTargets = true
        }
    }
}

private struct ModeControlLabel: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).font(.title2.bold())
            Spacer()
            Text(value)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
