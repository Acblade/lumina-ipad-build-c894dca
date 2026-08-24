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
            .padding(.top, 28)
            .padding(.bottom, 120)
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
    @State private var leftRGB: RGBColor
    @State private var rightRGB: RGBColor
    @State private var leftHex: String
    @State private var rightHex: String

    init(device: Device, capability: ZoneCapability) {
        self.device = device
        self.capability = capability
        let state = device.zoneState(capability.id)
        let initialBrightness = state.brightness > 0 ? state.brightness : capability.brightness?.min ?? 1
        let temperatureRange = capability.colorTemperature
        let mapsTemperatureToRGB = device.vendor.lowercased() == "yeelight"
            && capability.id.lowercased() == "ambient"
            && capability.rgb
        let initialTemperature = state.colorTemperatureKelvin
            ?? (mapsTemperatureToRGB && state.rgb != nil && temperatureRange != nil
                ? mappedKelvin(state.rgb!, minimum: temperatureRange!.min, maximum: temperatureRange!.max)
                : temperatureRange?.min ?? 2_700)
        let initialRGB = state.rgb ?? mappedColor(
            forKelvin: initialTemperature,
            minimum: temperatureRange?.min ?? 2_200,
            maximum: temperatureRange?.max ?? 6_500
        )
        let initialLeft = state.segmentRgb?.left ?? initialRGB
        let initialRight = state.segmentRgb?.right ?? initialRGB
        _brightness = State(initialValue: Double(initialBrightness))
        _temperature = State(initialValue: Double(initialTemperature))
        _selectedRGB = State(initialValue: initialRGB)
        _hex = State(initialValue: initialRGB.hex)
        _leftRGB = State(initialValue: initialLeft)
        _rightRGB = State(initialValue: initialRight)
        _leftHex = State(initialValue: initialLeft.hex)
        _rightHex = State(initialValue: initialRight.hex)
    }

    private var state: ZoneState { device.zoneState(capability.id) }
    private var canControl: Bool { device.online }
    private var mapsTemperatureToRGB: Bool {
        device.vendor.lowercased() == "yeelight"
            && capability.id.lowercased() == "ambient"
            && capability.rgb
    }

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
                        let kelvin = Int(value.rounded())
                        selectedRGB = mappedColor(forKelvin: kelvin, minimum: range.min, maximum: range.max)
                        hex = selectedRGB.hex
                        Task {
                            await model.control(
                                deviceID: device.id,
                                action: mapsTemperatureToRGB
                                    ? .init(zone: capability.id, power: true, rgb: selectedRGB)
                                    : .init(zone: capability.id, power: true, colorTemperatureKelvin: kelvin)
                            )
                        }
                    }
                }
            }

            if capability.rgb || capability.colorTemperature != nil {
                colorSection
            }

            if capability.segmentRgb {
                segmentSection
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

    private var segmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ControlLabel("左右分区", value: "\(leftRGB.hex) · \(rightRGB.hex)")

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("左侧").font(.headline)
                    LuminaColorField(color: $leftRGB, enabled: canControl) { color in
                        leftHex = color.hex
                        applySegments()
                    }
                    .frame(height: 220)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("右侧").font(.headline)
                    LuminaColorField(color: $rightRGB, enabled: canControl) { color in
                        rightHex = color.hex
                        applySegments()
                    }
                    .frame(height: 220)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                SegmentHexApplyField(
                    label: "左侧色号",
                    text: $leftHex,
                    enabled: canControl,
                    onColorChange: { leftRGB = $0 },
                    onApply: { color in leftRGB = color; applySegments() }
                )
                SegmentHexApplyField(
                    label: "右侧色号",
                    text: $rightHex,
                    enabled: canControl,
                    onColorChange: { rightRGB = $0 },
                    onApply: { color in rightRGB = color; applySegments() }
                )
            }
        }
    }

    private func apply(_ color: RGBColor) {
        if capability.rgb {
            if capability.segmentRgb {
                leftRGB = color
                rightRGB = color
                leftHex = color.hex
                rightHex = color.hex
            }
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

    private func applySegments() {
        Task {
            await model.control(
                deviceID: device.id,
                action: .init(
                    zone: capability.id,
                    power: true,
                    segmentRgb: .init(left: leftRGB, right: rightRGB)
                )
            )
        }
    }

    private func synchronize() {
        if let range = capability.brightness {
            brightness = Double(min(max(state.brightness, range.min), range.max))
        }
        if let range = capability.colorTemperature {
            if mapsTemperatureToRGB, let rgb = state.rgb {
                temperature = Double(mappedKelvin(rgb, minimum: range.min, maximum: range.max))
            } else if let kelvin = state.colorTemperatureKelvin {
                temperature = Double(min(max(kelvin, range.min), range.max))
            }
            if state.rgb == nil {
                selectedRGB = mappedColor(forKelvin: Int(temperature), minimum: range.min, maximum: range.max)
                hex = selectedRGB.hex
            }
        }
        if let rgb = state.rgb {
            selectedRGB = rgb
            hex = rgb.hex
        }
        if let segment = state.segmentRgb {
            leftRGB = segment.left
            rightRGB = segment.right
            leftHex = segment.left.hex
            rightHex = segment.right.hex
        }
    }
}

private struct SegmentHexApplyField: View {
    let label: String
    @Binding var text: String
    let enabled: Bool
    let onColorChange: (RGBColor) -> Void
    let onApply: (RGBColor) -> Void

    private var parsed: RGBColor? { RGBColor(hex: text) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(parsed == nil ? Color.red : Color.secondary, lineWidth: 1.5)
                .frame(height: 70)

            HStack(spacing: 10) {
                TextField("#FFB060", text: $text)
                    .textInputAutocapitalization(.characters)
                    .font(.body.monospaced())
                    .onChange(of: text) { _, value in
                        text = String(value.prefix(7)).uppercased()
                        if let color = RGBColor(hex: text) { onColorChange(color) }
                    }

                Button("应用") {
                    guard let color = parsed else { return }
                    onApply(color)
                }
                .font(.headline)
                .buttonStyle(.plain)
                .foregroundStyle(parsed != nil && enabled ? LuminaTheme.indigo : .secondary)
                .disabled(parsed == nil || !enabled)
            }
            .padding(.horizontal, 16)
            .frame(height: 70)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .background(LuminaTheme.mist)
                .offset(x: 12, y: -8)
        }
        .frame(maxWidth: .infinity)
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
    let warm = (r: 255.0, g: 148.0, b: 61.0)
    let cool = (r: 179.0, g: 224.0, b: 255.0)
    let direction = (r: cool.r - warm.r, g: cool.g - warm.g, b: cool.b - warm.b)
    let denominator = direction.r * direction.r + direction.g * direction.g + direction.b * direction.b
    let projection = (
        (Double(value.r) - warm.r) * direction.r
            + (Double(value.g) - warm.g) * direction.g
            + (Double(value.b) - warm.b) * direction.b
    ) / denominator
    let normalized = min(max(projection, 0), 1)
    return Int((Double(minimum) + normalized * Double(maximum - minimum)).rounded())
}

private func mappedColor(forKelvin kelvin: Int, minimum: Int = 2_200, maximum: Int = 6_500) -> RGBColor {
    let span = max(maximum - minimum, 1)
    let normalized = min(max(Double(kelvin - minimum) / Double(span), 0), 1)
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
