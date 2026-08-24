import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var allBrightness = 50.0
    @State private var editingAllBrightness = false

    private var zones: [DashboardZone] {
        model.devices.flatMap { device in
            device.capabilities.zones.enumerated().map { index, capability in
                DashboardZone(device: device, capability: capability, index: index)
            }
        }
    }

    private var availableZones: [DashboardZone] {
        zones.filter { $0.device.online && $0.capability.power }
    }

    private var allOn: Bool {
        !availableZones.isEmpty && availableZones.contains { $0.state.power }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LuminaPageHeader("灯光") {
                        Button {
                            Task { await model.refreshAll() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2.weight(.semibold))
                                .frame(width: 48, height: 48)
                                .background(LuminaTheme.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isLoading)
                        .accessibilityLabel("刷新")
                    }

                    allControls

                    if zones.isEmpty {
                        EmptyState(
                            icon: "lightbulb.slash",
                            title: "还没有灯具",
                            message: model.isConfigured ? "点按刷新或在设置中发现灯具。" : "请先在设置中连接 Hub。"
                        )
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 18)], spacing: 18) {
                            ForEach(zones) { zone in
                                DashboardZoneCard(zone: zone)
                            }
                        }
                    }
                }
                .frame(maxWidth: 1320)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .luminaPageBackground()
            .navigationBarHidden(true)
            .navigationDestination(for: DashboardZone.self) { zone in
                DeviceDetailView(deviceID: zone.device.id, zoneID: zone.capability.id)
            }
            .refreshable { await model.refreshAll() }
            .overlay {
                if model.isLoading && model.devices.isEmpty { ProgressView("正在连接 Hub…") }
            }
            .task(id: brightnessFingerprint) {
                guard !editingAllBrightness else { return }
                let lit = availableZones.filter { $0.state.power }
                let source = lit.isEmpty ? availableZones : lit
                let values = source.map(\.state.brightness).filter { $0 > 0 }
                if !values.isEmpty {
                    allBrightness = Double(values.reduce(0, +)) / Double(values.count)
                }
            }
        }
    }

    private var brightnessFingerprint: String {
        zones.map { "\($0.id):\($0.state.power):\($0.state.brightness)" }.joined(separator: "|")
    }

    private var allControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("全部")
                .font(.title2.bold())
            HStack(spacing: 16) {
                LuminaPillSlider(
                    value: $allBrightness,
                    range: 1...100,
                    colors: [Color(hex: "#FFD77A")!, Color(hex: "#FFB83E")!],
                    enabled: !availableZones.isEmpty
                ) { value in
                    editingAllBrightness = false
                    Task { await model.setAllBrightness(Int(value.rounded())) }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in editingAllBrightness = true }
                )

                LuminaSlidingPowerSwitch(
                    isOn: allOn,
                    enabled: !availableZones.isEmpty,
                    action: { Task { await model.setAllPower(!allOn) } }
                )
            }
        }
    }
}

private struct DashboardZone: Identifiable, Hashable {
    let device: Device
    let capability: ZoneCapability
    let index: Int

    var id: String { "\(device.id)::\(capability.id)" }
    var state: ZoneState { device.zoneState(capability.id) }
    var title: String {
        guard device.capabilities.zones.count > 1 else { return device.name }
        switch capability.id.lowercased() {
        case "main", "front": return capability.label.isEmpty ? "前灯" : capability.label
        case "ambient", "back": return capability.label.isEmpty ? "背板灯" : capability.label
        default: return capability.label.isEmpty ? device.name : capability.label
        }
    }
}

private struct DashboardZoneCard: View {
    @EnvironmentObject private var model: AppModel
    let zone: DashboardZone
    @State private var brightness: Double
    @State private var draggingBrightness = false

    init(zone: DashboardZone) {
        self.zone = zone
        _brightness = State(initialValue: Double(zone.state.brightness))
    }

    private var accent: Color { luminaAccent(for: zone.state) }
    private var range: ClosedRange<Double>? {
        zone.capability.brightness.map { Double($0.min)...Double($0.max) }
    }
    private var fraction: CGFloat {
        guard let range else { return zone.state.power ? 1 : 0 }
        let distance = max(range.upperBound - range.lowerBound, 1)
        return CGFloat(min(max((brightness - range.lowerBound) / distance, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LuminaTheme.surface)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.52), accent.opacity(0.90)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * ((zone.state.power || draggingBrightness) ? max(fraction, 0.02) : 0))
                    .allowsHitTesting(false)

                HStack(spacing: 12) {
                    NavigationLink(value: zone) {
                        Text(zone.title)
                            .font(.title2.bold())
                            .foregroundStyle(LuminaTheme.midnight)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    LuminaPowerButton(
                        isOn: zone.state.power,
                        enabled: zone.device.online && zone.capability.power
                    ) {
                        Task {
                            await model.control(
                                deviceID: zone.device.id,
                                action: .init(zone: zone.capability.id, power: !zone.state.power)
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                if !zone.device.online {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
            }
            .simultaneousGesture(brightnessGesture(width: proxy.size.width))
        }
        .frame(height: 112)
        .opacity(zone.device.online ? 1 : 0.62)
        .task(id: zone.state.brightness) {
            if !draggingBrightness { brightness = Double(zone.state.brightness) }
        }
    }

    private func brightnessGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { value in
                guard zone.device.online, let range, width > 0 else { return }
                draggingBrightness = true
                let part = Double(min(max(value.location.x / width, 0), 1))
                brightness = range.lowerBound + part * (range.upperBound - range.lowerBound)
            }
            .onEnded { value in
                guard draggingBrightness, zone.device.online, let range, width > 0 else { return }
                let part = Double(min(max(value.location.x / width, 0), 1))
                let committed = range.lowerBound + part * (range.upperBound - range.lowerBound)
                brightness = committed
                draggingBrightness = false
                Task {
                    await model.control(
                        deviceID: zone.device.id,
                        action: .init(
                            zone: zone.capability.id,
                            power: true,
                            brightness: Int(committed.rounded())
                        )
                    )
                }
            }
    }
}
