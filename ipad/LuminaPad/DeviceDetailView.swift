import SwiftUI
import UIKit

struct DeviceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let deviceID: String
    let zoneID: String
    @State private var editingIdentity = false

    private var device: Device? { model.device(id: deviceID) }
    private var capability: ZoneCapability? {
        device?.capabilities.zones.first { $0.id == zoneID }
    }
    private var title: String {
        guard let device, let capability else { return "灯光" }
        guard device.capabilities.zones.count > 1 else { return device.name }
        switch capability.id.lowercased() {
        case "main", "front": return capability.label.isEmpty ? "前灯" : capability.label
        case "ambient", "back": return capability.label.isEmpty ? "背板灯" : capability.label
        default: return capability.label.isEmpty ? device.name : capability.label
        }
    }

    var body: some View {
        ScrollView {
            Group {
                if let device, let capability {
                    ZoneControlPanel(device: device, capability: capability)
                        .frame(maxWidth: 840)
                } else {
                    EmptyState(icon: "questionmark.circle", title: "灯光不存在", message: "它可能已从 Hub 中删除。")
                        .frame(maxWidth: 840)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .luminaPageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("编辑", systemImage: "pencil") { editingIdentity = true }
                .disabled(device == nil)
        }
        .sheet(isPresented: $editingIdentity) {
            if let device { DeviceIdentityEditor(device: device) }
        }
    }
}

private struct ZoneControlPanel: View {
    @EnvironmentObject private var model: AppModel
    let device: Device
    let capability: ZoneCapability

    @State private var brightness: Double
    @State private var temperature: Double
    @State private var selectedRGB: RGBColor
    @State private var hex: String

    init(device: Device, capability: ZoneCapability) {
        self.device = device
        self.capability = capability
        let state = device.zoneState(capability.id)
        let initialBrightness = state.brightness > 0 ? state.brightness : capability.brightness?.min ?? 1
        let initialTemperature = state.colorTemperatureKelvin ?? capability.colorTemperature?.min ?? 2_700
        let initialRGB = state.rgb ?? mappedColor(forKelvin: initialTemperature)
        _brightness = State(initialValue: Double(initialBrightness))
        _temperature = State(initialValue: Double(initialTemperature))
        _selectedRGB = State(initialValue: initialRGB)
        _hex = State(initialValue: initialRGB.hex)
    }

    private var state: ZoneState { device.zoneState(capability.id) }
    private var canControl: Bool { device.online }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .bottom, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    ControlLabel("亮度", value: "\(Int(brightness.rounded()))%")
                    if let range = capability.brightness {
                        LuminaPillSlider(
                            value: $brightness,
                            range: Double(range.min)...Double(range.max),
                            colors: [Color(hex: "#FFD77A")!, Color(hex: "#FFB83E")!],
                            enabled: canControl
                        ) { value in
                            Task {
                                await model.control(
                                    deviceID: device.id,
                                    action: .init(
                                        zone: capability.id,
                                        power: true,
                                        brightness: Int(value.rounded())
                                    )
                                )
                            }
                        }
                    }
                }

                LuminaSlidingPowerSwitch(
                    isOn: state.power,
                    enabled: canControl && capability.power,
                    width: 82,
                    height: 44
                ) {
                    Task {
                        await model.control(
                            deviceID: device.id,
                            action: .init(zone: capability.id, power: !state.power)
                        )
                    }
                }
            }

            if let range = capability.colorTemperature {
                VStack(alignment: .leading, spacing: 9) {
                    ControlLabel("色温", value: "\(Int(temperature.rounded()))K")
                    LuminaPillSlider(
                        value: $temperature,
                        range: Double(range.min)...Double(range.max),
                        colors: [
                            Color(hex: "#FFA84C")!,
                            Color(hex: "#FFF4D8")!,
                            Color(hex: "#B8DCFF")!
                        ],
                        enabled: canControl
                    ) { value in
                        selectedRGB = mappedColor(forKelvin: Int(value.rounded()))
                        hex = selectedRGB.hex
                        Task {
                            await model.control(
                                deviceID: device.id,
                                action: .init(
                                    zone: capability.id,
                                    power: true,
                                    colorTemperatureKelvin: Int(value.rounded())
                                )
                            )
                        }
                    }
                }
            }

            if capability.rgb || capability.colorTemperature != nil {
                colorSection
            }
        }
        .task(id: state) { synchronize() }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ControlLabel(
                capability.rgb ? "色彩" : "色彩 · 自动映射为色温",
                value: capability.rgb ? selectedRGB.hex : "\(Int(temperature.rounded()))K"
            )

            LuminaColorField(color: $selectedRGB, enabled: canControl) { color in
                hex = color.hex
                apply(color)
            }
            .frame(height: 260)

            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(validHex ? Color.secondary : Color.red, lineWidth: 1.5)
                        .frame(height: 70)

                    HStack(spacing: 12) {
                        TextField("#FFB060", text: $hex)
                            .textInputAutocapitalization(.characters)
                            .font(.title3.monospaced())
                            .onChange(of: hex) { _, value in
                                hex = String(value.prefix(7)).uppercased()
                                if let color = RGBColor(hex: hex) { selectedRGB = color }
                            }

                        Button("应用") {
                            guard let color = RGBColor(hex: hex) else { return }
                            selectedRGB = color
                            apply(color)
                        }
                        .font(.headline)
                        .buttonStyle(.plain)
                        .foregroundStyle(validHex && canControl ? LuminaTheme.indigo : .secondary)
                        .disabled(!validHex || !canControl)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 70)

                    Text("色号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .background(LuminaTheme.mist)
                        .offset(x: 14, y: -8)
                }

                Text(capability.rgb ? "输入完整色号后应用" : "白光前灯会取该颜色最接近的冷暖色温")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
    }

    private var validHex: Bool { RGBColor(hex: hex) != nil }

    private func apply(_ color: RGBColor) {
        if capability.rgb {
            Task {
                await model.control(
                    deviceID: device.id,
                    action: .init(zone: capability.id, power: true, rgb: color)
                )
            }
        } else if let range = capability.colorTemperature {
            let kelvin = mappedKelvin(color, minimum: range.min, maximum: range.max)
            temperature = Double(kelvin)
            Task {
                await model.control(
                    deviceID: device.id,
                    action: .init(zone: capability.id, power: true, colorTemperatureKelvin: kelvin)
                )
            }
        }
    }

    private func synchronize() {
        if let range = capability.brightness {
            brightness = Double(min(max(state.brightness, range.min), range.max))
        }
        if let range = capability.colorTemperature,
           let kelvin = state.colorTemperatureKelvin {
            temperature = Double(min(max(kelvin, range.min), range.max))
            if state.rgb == nil {
                selectedRGB = mappedColor(forKelvin: Int(temperature))
                hex = selectedRGB.hex
            }
        }
        if let rgb = state.rgb {
            selectedRGB = rgb
            hex = rgb.hex
        }
    }
}

private struct ControlLabel: View {
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

private struct LuminaColorField: View {
    @Binding var color: RGBColor
    let enabled: Bool
    let onCommit: (RGBColor) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .stroke(Color.black.opacity(0.72), lineWidth: 2)
                    .background(Circle().stroke(.white, lineWidth: 4))
                    .frame(width: 30, height: 30)
                    .position(selectorPosition(in: proxy.size))
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { update($0.location, in: proxy.size) }
                    .onEnded {
                        update($0.location, in: proxy.size)
                        onCommit(color)
                    }
            )
        }
        .opacity(enabled ? 1 : 0.58)
        .allowsHitTesting(enabled)
    }

    private func selectorPosition(in size: CGSize) -> CGPoint {
        let hsv = color.hsv
        let y = hsv.brightness >= 0.999
            ? hsv.saturation * 0.5
            : 0.5 + (1 - hsv.brightness) * 0.5
        return CGPoint(
            x: min(max(hsv.hue * size.width, 15), max(size.width - 15, 15)),
            y: min(max(y * size.height, 15), max(size.height - 15, 15))
        )
    }

    private func update(_ point: CGPoint, in size: CGSize) {
        guard enabled, size.width > 0, size.height > 0 else { return }
        let hue = min(max(point.x / size.width, 0), 1)
        let vertical = min(max(point.y / size.height, 0), 1)
        let saturation = vertical <= 0.5 ? vertical * 2 : 1
        let brightness = vertical <= 0.5 ? 1 : 2 - vertical * 2
        color = RGBColor(hue: hue, saturation: saturation, brightness: brightness)
    }
}

private extension RGBColor {
    var hsv: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let value = normalized
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        UIColor(
            red: CGFloat(value.r) / 255,
            green: CGFloat(value.g) / 255,
            blue: CGFloat(value.b) / 255,
            alpha: 1
        ).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return (hue, saturation, brightness)
    }

    init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let ui = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: nil)
        self.init(r: Int((red * 255).rounded()), g: Int((green * 255).rounded()), b: Int((blue * 255).rounded()))
    }
}

private func mappedKelvin(_ color: RGBColor, minimum: Int, maximum: Int) -> Int {
    let value = color.normalized
    let warmth = Double(value.r - value.b + 255) / 510
    return Int((Double(maximum) - min(max(warmth, 0), 1) * Double(maximum - minimum)).rounded())
}

private func mappedColor(forKelvin kelvin: Int) -> RGBColor {
    let normalized = min(max(Double(kelvin - 2_200) / Double(6_500 - 2_200), 0), 1)
    return RGBColor(
        r: Int(((1 - 0.30 * normalized) * 255).rounded()),
        g: Int(((0.58 + 0.30 * normalized) * 255).rounded()),
        b: Int(((0.24 + 0.76 * normalized) * 255).rounded())
    ).normalized
}

private struct DeviceIdentityEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let device: Device
    @State private var name: String
    @State private var room: String

    init(device: Device) {
        self.device = device
        _name = State(initialValue: device.name)
        _room = State(initialValue: device.room ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("设备名称", text: $name)
                TextField("房间", text: $room)
            }
            .navigationTitle("编辑灯具")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await model.rename(deviceID: device.id, name: name, room: room.isEmpty ? nil : room) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
