import Foundation

struct Device: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var room: String?
    var vendor: String
    var host: String?
    var model: String?
    var firmware: String?
    var online: Bool
    var capabilities: DeviceCapabilities
    var state: DeviceState

    enum CodingKeys: String, CodingKey {
        case id, name, room, vendor, host, model, firmware, online, capabilities, state, `protocol`
    }

    init(
        id: String,
        name: String,
        room: String? = nil,
        vendor: String,
        host: String? = nil,
        model: String? = nil,
        firmware: String? = nil,
        online: Bool = false,
        capabilities: DeviceCapabilities = .init(),
        state: DeviceState = .init()
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.vendor = vendor
        self.host = host
        self.model = model
        self.firmware = firmware
        self.online = online
        self.capabilities = capabilities
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        room = try values.decodeIfPresent(String.self, forKey: .room)
        vendor = try values.decodeIfPresent(String.self, forKey: .vendor)
            ?? values.decodeIfPresent(String.self, forKey: .protocol)
            ?? "unknown"
        host = try values.decodeIfPresent(String.self, forKey: .host)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        firmware = try values.decodeIfPresent(String.self, forKey: .firmware)
        online = try values.decodeIfPresent(Bool.self, forKey: .online) ?? false
        capabilities = try values.decodeIfPresent(DeviceCapabilities.self, forKey: .capabilities) ?? .init()
        state = try values.decodeIfPresent(DeviceState.self, forKey: .state) ?? .init()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(room, forKey: .room)
        try values.encode(vendor, forKey: .vendor)
        try values.encodeIfPresent(host, forKey: .host)
        try values.encodeIfPresent(model, forKey: .model)
        try values.encodeIfPresent(firmware, forKey: .firmware)
        try values.encode(online, forKey: .online)
        try values.encode(capabilities, forKey: .capabilities)
        try values.encode(state, forKey: .state)
    }

    var subtitle: String {
        [room, model, vendor.uppercased()].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    func zoneState(_ id: String) -> ZoneState { state.zones[id] ?? .init() }
}

struct DeviceCapabilities: Codable, Hashable, Sendable {
    var zones: [ZoneCapability] = []
    var nativeScenes: [NativeScene] = []
    var supportsRatio = false
    var support: [String] = []
    var experimentalSegmentRgb = false

    private enum CodingKeys: String, CodingKey { case zones, nativeScenes, supportsRatio, support, experimentalSegmentRgb }

    init(
        zones: [ZoneCapability] = [],
        nativeScenes: [NativeScene] = [],
        supportsRatio: Bool = false,
        support: [String] = [],
        experimentalSegmentRgb: Bool = false
    ) {
        self.zones = zones
        self.nativeScenes = nativeScenes
        self.supportsRatio = supportsRatio
        self.support = support
        self.experimentalSegmentRgb = experimentalSegmentRgb
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        zones = try values.decodeIfPresent([ZoneCapability].self, forKey: .zones) ?? []
        nativeScenes = try values.decodeIfPresent([NativeScene].self, forKey: .nativeScenes) ?? []
        supportsRatio = try values.decodeIfPresent(Bool.self, forKey: .supportsRatio) ?? false
        support = try values.decodeIfPresent([String].self, forKey: .support) ?? []
        experimentalSegmentRgb = try values.decodeIfPresent(Bool.self, forKey: .experimentalSegmentRgb) ?? false
    }
}

struct ZoneCapability: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var label: String
    var power: Bool = true
    var brightness: IntegerRange?
    var colorTemperature: IntegerRange?
    var rgb = false
    var whiteChannels = false
    var flow = false
    var segmentRgb = false

    private enum CodingKeys: String, CodingKey {
        case id, label, power, brightness, colorTemperature, rgb, whiteChannels, flow, segmentRgb
    }

    init(
        id: String,
        label: String? = nil,
        power: Bool = true,
        brightness: IntegerRange? = nil,
        colorTemperature: IntegerRange? = nil,
        rgb: Bool = false,
        whiteChannels: Bool = false,
        flow: Bool = false,
        segmentRgb: Bool = false
    ) {
        self.id = id
        self.label = label ?? id
        self.power = power
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.rgb = rgb
        self.whiteChannels = whiteChannels
        self.flow = flow
        self.segmentRgb = segmentRgb
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? id
        power = try values.decodeIfPresent(Bool.self, forKey: .power) ?? true
        brightness = try values.decodeIfPresent(IntegerRange.self, forKey: .brightness)
        colorTemperature = try values.decodeIfPresent(IntegerRange.self, forKey: .colorTemperature)
        rgb = try values.decodeIfPresent(Bool.self, forKey: .rgb) ?? false
        whiteChannels = try values.decodeIfPresent(Bool.self, forKey: .whiteChannels) ?? false
        flow = try values.decodeIfPresent(Bool.self, forKey: .flow) ?? false
        segmentRgb = try values.decodeIfPresent(Bool.self, forKey: .segmentRgb) ?? false
    }
}

struct IntegerRange: Codable, Hashable, Sendable {
    var min: Int
    var max: Int
    var reportedMin: Int?
}

struct NativeScene: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    var dynamic = false
    var speedMin: Int?
    var speedMax: Int?

    private enum CodingKeys: String, CodingKey { case id, name, dynamic, speedMin, speedMax }

    init(id: Int, name: String, dynamic: Bool = false, speedMin: Int? = nil, speedMax: Int? = nil) {
        self.id = id
        self.name = name
        self.dynamic = dynamic
        self.speedMin = speedMin
        self.speedMax = speedMax
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        dynamic = try values.decodeIfPresent(Bool.self, forKey: .dynamic) ?? false
        speedMin = try values.decodeIfPresent(Int.self, forKey: .speedMin)
        speedMax = try values.decodeIfPresent(Int.self, forKey: .speedMax)
    }
}

struct DeviceState: Codable, Hashable, Sendable {
    var zones: [String: ZoneState] = [:]
    var rssi: Int?

    private enum CodingKeys: String, CodingKey { case zones, rssi }
    init(zones: [String: ZoneState] = [:], rssi: Int? = nil) { self.zones = zones; self.rssi = rssi }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        zones = try values.decodeIfPresent([String: ZoneState].self, forKey: .zones) ?? [:]
        rssi = try values.decodeIfPresent(Int.self, forKey: .rssi)
    }
}

struct ZoneState: Codable, Hashable, Sendable {
    var power = false
    var brightness = 0
    var colorTemperatureKelvin: Int?
    var rgb: RGBColor?
    var sceneId: Int?
    var speed: Int?
    var ratio: Int?
    var whiteChannels: WhiteChannels?
    var segmentRgb: SegmentRGB?

    private enum CodingKeys: String, CodingKey {
        case power, brightness, colorTemperatureKelvin, rgb, sceneId, speed, ratio, whiteChannels, segmentRgb
    }

    init(
        power: Bool = false,
        brightness: Int = 0,
        colorTemperatureKelvin: Int? = nil,
        rgb: RGBColor? = nil,
        sceneId: Int? = nil,
        speed: Int? = nil,
        ratio: Int? = nil,
        whiteChannels: WhiteChannels? = nil,
        segmentRgb: SegmentRGB? = nil
    ) {
        self.power = power
        self.brightness = brightness
        self.colorTemperatureKelvin = colorTemperatureKelvin
        self.rgb = rgb
        self.sceneId = sceneId
        self.speed = speed
        self.ratio = ratio
        self.whiteChannels = whiteChannels
        self.segmentRgb = segmentRgb
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        power = try values.decodeIfPresent(Bool.self, forKey: .power) ?? false
        brightness = try values.decodeIfPresent(Int.self, forKey: .brightness) ?? 0
        colorTemperatureKelvin = try values.decodeIfPresent(Int.self, forKey: .colorTemperatureKelvin)
        rgb = try values.decodeIfPresent(RGBColor.self, forKey: .rgb)
        sceneId = try values.decodeIfPresent(Int.self, forKey: .sceneId)
        speed = try values.decodeIfPresent(Int.self, forKey: .speed)
        ratio = try values.decodeIfPresent(Int.self, forKey: .ratio)
        whiteChannels = try values.decodeIfPresent(WhiteChannels.self, forKey: .whiteChannels)
        segmentRgb = try values.decodeIfPresent(SegmentRGB.self, forKey: .segmentRgb)
    }
}

struct RGBColor: Codable, Hashable, Sendable {
    var r: Int
    var g: Int
    var b: Int

    var normalized: RGBColor {
        .init(r: r.clamped(to: 0...255), g: g.clamped(to: 0...255), b: b.clamped(to: 0...255))
    }

    var hex: String {
        let value = normalized
        return String(format: "#%02X%02X%02X", value.r, value.g, value.b)
    }

    init(r: Int, g: Int, b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex: String) {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        r = (value >> 16) & 0xff
        g = (value >> 8) & 0xff
        b = value & 0xff
    }
}

struct WhiteChannels: Codable, Hashable, Sendable {
    var cold: Int
    var warm: Int
}

struct SegmentRGB: Codable, Hashable, Sendable {
    var left: RGBColor
    var right: RGBColor
}

struct DeviceControlRequest: Codable, Hashable, Sendable {
    var zone: String?
    var power: Bool?
    var brightness: Int?
    var colorTemperatureKelvin: Int?
    var rgb: RGBColor?
    var sceneId: Int?
    var speed: Int?
    var ratio: Int?
    var transitionMs: Int64?
    var whiteChannels: WhiteChannels?
    var segmentRgb: SegmentRGB?
}

struct DevicePatch: Codable, Hashable, Sendable {
    var name: String?
    var room: String?
    var zoneLabels: [String: String]?
}

struct LightMode: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var sceneId: Int
    var name: String
    var category: String
    var dynamic = false
    var frontCct: Int
    var colors: [String] = []
    var description = ""
    var speedMin: Int?
    var speedMax: Int?

    private enum CodingKeys: String, CodingKey {
        case id, sceneId, name, category, dynamic, frontCct, colors, description, speedMin, speedMax
    }

    init(
        id: String,
        sceneId: Int,
        name: String,
        category: String,
        dynamic: Bool = false,
        frontCct: Int,
        colors: [String] = [],
        description: String = "",
        speedMin: Int? = nil,
        speedMax: Int? = nil
    ) {
        self.id = id
        self.sceneId = sceneId
        self.name = name
        self.category = category
        self.dynamic = dynamic
        self.frontCct = frontCct
        self.colors = colors
        self.description = description
        self.speedMin = speedMin
        self.speedMax = speedMax
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sceneId = try values.decode(Int.self, forKey: .sceneId)
        name = try values.decode(String.self, forKey: .name)
        category = try values.decode(String.self, forKey: .category)
        dynamic = try values.decodeIfPresent(Bool.self, forKey: .dynamic) ?? false
        frontCct = try values.decode(Int.self, forKey: .frontCct)
        colors = try values.decodeIfPresent([String].self, forKey: .colors) ?? []
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        speedMin = try values.decodeIfPresent(Int.self, forKey: .speedMin)
        speedMax = try values.decodeIfPresent(Int.self, forKey: .speedMax)
    }
}

struct ModeTarget: Codable, Hashable, Identifiable, Sendable {
    var deviceId: String
    var zone: String
    var id: String { "\(deviceId)::\(zone)" }
}

struct ApplyModeRequest: Codable, Hashable, Sendable {
    var targets: [ModeTarget]
    var brightness: Int
    var speed: Int?
}

struct Scene: Codable, Hashable, Identifiable, Sendable {
    var id: String = ""
    var name: String
    var icon: String?
    var color: String?
    var durationMs: Int64 = 0
    var tracks: [SceneTrack] = []
    var schedules: [SceneSchedule] = []

    private enum CodingKeys: String, CodingKey { case id, name, icon, color, durationMs, tracks, schedules }

    init(
        id: String = "",
        name: String,
        icon: String? = nil,
        color: String? = nil,
        durationMs: Int64 = 0,
        tracks: [SceneTrack] = [],
        schedules: [SceneSchedule] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.durationMs = durationMs
        self.tracks = tracks
        self.schedules = schedules
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try values.decode(String.self, forKey: .name)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        color = try values.decodeIfPresent(String.self, forKey: .color)
        durationMs = try values.decodeIfPresent(Int64.self, forKey: .durationMs) ?? 0
        tracks = try values.decodeIfPresent([SceneTrack].self, forKey: .tracks) ?? []
        schedules = try values.decodeIfPresent([SceneSchedule].self, forKey: .schedules) ?? []
    }

    var normalized: Scene {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.tracks = tracks.map { track in
            var sorted = track
            sorted.keyframes.sort { $0.offsetMs < $1.offsetMs }
            return sorted
        }
        let inferred = result.tracks.flatMap(\.keyframes).map(\.offsetMs).max() ?? 0
        result.durationMs = max(durationMs, inferred)
        return result
    }

    var durationLabel: String {
        let total = durationMs / 1_000
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        if minutes > 0 { return seconds > 0 ? "\(minutes)分\(seconds)秒" : "\(minutes)分钟" }
        return "\(seconds)秒"
    }

    func validationError(devices: [Device]) -> String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "场景名称不能为空" }
        guard !tracks.isEmpty else { return "场景至少需要一条设备轨道" }
        var targets = Set<String>()
        for track in tracks {
            guard let device = devices.first(where: { $0.id == track.deviceId }) else { return "轨道引用了已不存在的设备" }
            guard let capability = device.capabilities.zones.first(where: { $0.id == track.zone }) else {
                return "“\(device.name)”没有 \(track.zone) 灯区"
            }
            guard !targets.contains(track.id) else { return "同一设备灯区不能出现重复轨道" }
            targets.insert(track.id)
            guard !track.keyframes.isEmpty else { return "每条轨道至少需要一个关键帧" }
            guard track.keyframes.sorted(by: { $0.offsetMs < $1.offsetMs }).first?.offsetMs == 0 else {
                return "每条轨道的第一个关键帧必须从 0 秒开始"
            }
            var activeSceneID: Int?
            for frame in track.keyframes {
                guard frame.offsetMs >= 0, frame.offsetMs <= 604_800_000 else { return "关键帧必须位于 0 秒到 7 天之间" }
                guard ["linear", "step"].contains(frame.easing) else { return "关键帧过渡只能是 linear 或 step" }
                let appearances: [Any?] = [frame.rgb, frame.colorTemperatureKelvin, frame.whiteChannels, frame.segmentRgb, frame.sceneId]
                guard appearances.compactMap({ $0 }).count <= 1 else { return "一个关键帧只能设置一种颜色或效果模式" }
                if frame.power != nil, !capability.power { return "“\(capability.label)”不支持电源控制" }
                if let brightness = frame.brightness {
                    guard capability.brightness != nil else { return "“\(capability.label)”不支持亮度" }
                    guard (1...100).contains(brightness) else { return "亮度必须是 1–100 的整数" }
                }
                if let cct = frame.colorTemperatureKelvin {
                    guard let range = capability.colorTemperature else { return "“\(capability.label)”不支持色温" }
                    guard (range.min...range.max).contains(cct) else { return "色温必须位于 \(range.min)–\(range.max)K" }
                    activeSceneID = nil
                }
                if frame.rgb != nil {
                    guard capability.rgb else { return "“\(capability.label)”不支持 RGB" }
                    activeSceneID = nil
                }
                if frame.whiteChannels != nil {
                    guard capability.whiteChannels else { return "“\(capability.label)”不支持独立冷暖白通道" }
                    activeSceneID = nil
                }
                if frame.segmentRgb != nil {
                    guard capability.segmentRgb else { return "“\(capability.label)”不支持分段 RGB" }
                    activeSceneID = nil
                }
                if let sceneID = frame.sceneId {
                    guard device.capabilities.nativeScenes.contains(where: { $0.id == sceneID }) else {
                        return "“\(device.name)”不支持原生效果 \(sceneID)"
                    }
                    activeSceneID = sceneID
                }
                if let speed = frame.speed {
                    guard let sceneID = activeSceneID,
                          let nativeScene = device.capabilities.nativeScenes.first(where: { $0.id == sceneID }),
                          nativeScene.dynamic else { return "速度只适用于动态原生效果" }
                    let speedRange = (nativeScene.speedMin ?? 20)...(nativeScene.speedMax ?? 200)
                    guard speedRange.contains(speed) else {
                        return "效果速度必须位于 \(speedRange.lowerBound)–\(speedRange.upperBound)"
                    }
                }
                if let ratio = frame.ratio {
                    guard device.capabilities.supportsRatio else { return "“\(device.name)”不支持双区比例" }
                    guard (0...100).contains(ratio) else { return "双区比例必须是 0–100 的整数" }
                }
            }
        }
        let scheduleIDs = schedules.map(\.id)
        guard scheduleIDs.allSatisfy({ !$0.isEmpty }), Set(scheduleIDs).count == scheduleIDs.count else {
            return "周计划 ID 缺失或重复"
        }
        for schedule in schedules {
            guard schedule.time.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else {
                return "周计划时间必须使用 HH:mm 格式"
            }
            guard schedule.daysOfWeek.allSatisfy({ (1...7).contains($0) }) else { return "星期必须位于 1–7" }
            guard TimeZone(identifier: schedule.timezone) != nil else { return "周计划需要有效的 IANA 时区" }
        }
        return nil
    }
}

struct SceneTrack: Codable, Hashable, Identifiable, Sendable {
    var deviceId: String
    var zone: String
    var repeatTrack = false
    var keyframes: [SceneKeyframe] = []

    enum CodingKeys: String, CodingKey { case deviceId, zone, keyframes, repeatTrack = "repeat" }
    var id: String { "\(deviceId)::\(zone)" }

    init(deviceId: String, zone: String, repeatTrack: Bool = false, keyframes: [SceneKeyframe] = []) {
        self.deviceId = deviceId
        self.zone = zone
        self.repeatTrack = repeatTrack
        self.keyframes = keyframes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try values.decode(String.self, forKey: .deviceId)
        zone = try values.decodeIfPresent(String.self, forKey: .zone) ?? "main"
        repeatTrack = try values.decodeIfPresent(Bool.self, forKey: .repeatTrack) ?? false
        keyframes = try values.decodeIfPresent([SceneKeyframe].self, forKey: .keyframes) ?? []
    }
}

struct SceneKeyframe: Codable, Hashable, Sendable {
    var offsetMs: Int64
    var power: Bool?
    var brightness: Int?
    var colorTemperatureKelvin: Int?
    var rgb: RGBColor?
    var sceneId: Int?
    var speed: Int?
    var ratio: Int?
    var easing: String = "linear"
    var whiteChannels: WhiteChannels?
    var segmentRgb: SegmentRGB?

    private enum CodingKeys: String, CodingKey {
        case offsetMs, power, brightness, colorTemperatureKelvin, rgb, sceneId, speed, ratio, easing, whiteChannels, segmentRgb
    }

    init(
        offsetMs: Int64,
        power: Bool? = nil,
        brightness: Int? = nil,
        colorTemperatureKelvin: Int? = nil,
        rgb: RGBColor? = nil,
        sceneId: Int? = nil,
        speed: Int? = nil,
        ratio: Int? = nil,
        easing: String = "linear",
        whiteChannels: WhiteChannels? = nil,
        segmentRgb: SegmentRGB? = nil
    ) {
        self.offsetMs = offsetMs
        self.power = power
        self.brightness = brightness
        self.colorTemperatureKelvin = colorTemperatureKelvin
        self.rgb = rgb
        self.sceneId = sceneId
        self.speed = speed
        self.ratio = ratio
        self.easing = easing
        self.whiteChannels = whiteChannels
        self.segmentRgb = segmentRgb
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        offsetMs = try values.decode(Int64.self, forKey: .offsetMs)
        power = try values.decodeIfPresent(Bool.self, forKey: .power)
        brightness = try values.decodeIfPresent(Int.self, forKey: .brightness)
        colorTemperatureKelvin = try values.decodeIfPresent(Int.self, forKey: .colorTemperatureKelvin)
        rgb = try values.decodeIfPresent(RGBColor.self, forKey: .rgb)
        sceneId = try values.decodeIfPresent(Int.self, forKey: .sceneId)
        speed = try values.decodeIfPresent(Int.self, forKey: .speed)
        ratio = try values.decodeIfPresent(Int.self, forKey: .ratio)
        easing = try values.decodeIfPresent(String.self, forKey: .easing) ?? "linear"
        whiteChannels = try values.decodeIfPresent(WhiteChannels.self, forKey: .whiteChannels)
        segmentRgb = try values.decodeIfPresent(SegmentRGB.self, forKey: .segmentRgb)
    }

    var summary: String {
        var values: [String] = []
        if let power { values.append(power ? "打开" : "关闭") }
        if let brightness { values.append("亮度 \(brightness)%") }
        if let colorTemperatureKelvin { values.append("\(colorTemperatureKelvin)K") }
        if let rgb { values.append(rgb.hex) }
        if let sceneId { values.append("效果 \(sceneId)") }
        if let speed { values.append("速度 \(speed)") }
        if let ratio { values.append("双区 \(ratio)%") }
        if let whiteChannels { values.append("冷/暖 \(whiteChannels.cold)/\(whiteChannels.warm)") }
        if let segmentRgb { values.append("左右 \(segmentRgb.left.hex)/\(segmentRgb.right.hex)") }
        return values.isEmpty ? "保持当前状态" : values.joined(separator: " · ")
    }
}

struct SceneSchedule: Codable, Hashable, Identifiable, Sendable {
    var id: String = ""
    var enabled = true
    var time: String
    var daysOfWeek: [Int] = []
    var timezone = "Europe/Zurich"

    private enum CodingKeys: String, CodingKey { case id, enabled, time, daysOfWeek, timezone }

    init(id: String = "", enabled: Bool = true, time: String, daysOfWeek: [Int] = [], timezone: String = "Europe/Zurich") {
        self.id = id
        self.enabled = enabled
        self.time = time
        self.daysOfWeek = daysOfWeek
        self.timezone = timezone
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        time = try values.decode(String.self, forKey: .time)
        daysOfWeek = try values.decodeIfPresent([Int].self, forKey: .daysOfWeek) ?? []
        timezone = try values.decodeIfPresent(String.self, forKey: .timezone) ?? "Europe/Zurich"
    }
}

struct RunTrackResult: Codable, Hashable, Sendable {
    var deviceId: String
    var zone: String = "main"
    var status: String
    var error: String?

    private enum CodingKeys: String, CodingKey { case deviceId, zone, status, error }
    init(deviceId: String, zone: String = "main", status: String, error: String? = nil) {
        self.deviceId = deviceId; self.zone = zone; self.status = status; self.error = error
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try values.decode(String.self, forKey: .deviceId)
        zone = try values.decodeIfPresent(String.self, forKey: .zone) ?? "main"
        status = try values.decode(String.self, forKey: .status)
        error = try values.decodeIfPresent(String.self, forKey: .error)
    }
}

struct RunInfo: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var sceneId: String?
    var status: String?
    var startedAt: String?
    var endedAt: String?
    var trackResults: [RunTrackResult] = []

    private enum CodingKeys: String, CodingKey { case id, sceneId, status, startedAt, endedAt, trackResults }
    init(
        id: String,
        sceneId: String? = nil,
        status: String? = nil,
        startedAt: String? = nil,
        endedAt: String? = nil,
        trackResults: [RunTrackResult] = []
    ) {
        self.id = id
        self.sceneId = sceneId
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.trackResults = trackResults
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sceneId = try values.decodeIfPresent(String.self, forKey: .sceneId)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        startedAt = try values.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try values.decodeIfPresent(String.self, forKey: .endedAt)
        trackResults = try values.decodeIfPresent([RunTrackResult].self, forKey: .trackResults) ?? []
    }
}

struct HubConnection: Codable, Hashable, Sendable {
    var baseURL = ""
    var bearerToken = ""
    var cloudflareClientID = ""
    var cloudflareClientSecret = ""

    var isConfigured: Bool { !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var normalized: HubConnection {
        HubConnection(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            bearerToken: bearerToken.trimmingCharacters(in: .whitespacesAndNewlines),
            cloudflareClientID: cloudflareClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            cloudflareClientSecret: cloudflareClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
