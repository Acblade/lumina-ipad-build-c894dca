import SwiftUI

struct SceneEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    private let original: Scene
    @State private var draft: Scene
    @State private var showingTrackPicker = false
    @State private var editingSchedule: IndexedSchedule?
    @State private var showingNewSchedule = false
    @State private var showingDiscardConfirmation = false

    init(scene: Scene?) {
        let initial = scene ?? Scene(name: "新场景", icon: "sparkles", color: "#5856D6")
        original = initial
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("场景名称", text: $draft.name)
                    TextField("SF Symbol 或兼容图标名称", text: Binding(
                        get: { draft.icon ?? "" },
                        set: { draft.icon = $0.isEmpty ? nil : $0 }
                    ))
                    HStack {
                        TextField("颜色 #RRGGBB", text: Binding(
                            get: { draft.color ?? "" },
                            set: { draft.color = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.body.monospaced())
                        ColorPicker("颜色", selection: Binding(
                            get: { sceneColor(draft.color) },
                            set: { draft.color = $0.rgbValue.hex }
                        ), supportsOpacity: false)
                        .labelsHidden()
                    }
                    LabeledContent("总时长") {
                        TextField("秒", value: Binding(
                            get: { Double(draft.durationMs) / 1_000 },
                            set: { draft.durationMs = Int64(min(max($0, 0), 604_800) * 1_000) }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                    }
                    Text("可在最后一个关键帧之后继续保持最终状态，最长 7 天。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if draft.tracks.isEmpty {
                        Text("场景至少需要一条轨道。每条轨道对应一个设备灯区，关键帧保存绝对状态。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(draft.tracks.indices, id: \.self) { index in
                        TrackEditorCard(
                            track: $draft.tracks[index],
                            device: model.device(id: draft.tracks[index].deviceId),
                            delete: { draft.tracks.remove(at: index) }
                        )
                    }
                    Button("添加设备轨道", systemImage: "plus.rectangle.on.rectangle") {
                        showingTrackPicker = true
                    }
                } header: {
                    Text("时间线轨道")
                } footer: {
                    Text("亮度是 1–100 的整数；power 与 brightness 始终是独立状态。")
                }

                Section {
                    if draft.schedules.isEmpty {
                        Text("没有周计划。场景仍可手动、通过 Widget 或 Codex 运行。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(draft.schedules.indices, id: \.self) { index in
                        Button {
                            editingSchedule = IndexedSchedule(index: index, schedule: draft.schedules[index])
                        } label: {
                            HStack {
                                Image(systemName: draft.schedules[index].enabled ? "calendar.badge.checkmark" : "calendar")
                                VStack(alignment: .leading) {
                                    Text(draft.schedules[index].time).font(.headline.monospacedDigit())
                                    Text(daySummary(draft.schedules[index].daysOfWeek) + " · " + draft.schedules[index].timezone)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("删除", role: .destructive) { draft.schedules.remove(at: index) }
                        }
                    }
                    Button("添加周计划", systemImage: "calendar.badge.plus") { showingNewSchedule = true }
                } header: {
                    Text("Hub 周计划")
                } footer: {
                    Text("计划由常开的 Hub 准点执行；iPad 不依赖不确定的后台唤醒。")
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminaTheme.mist)
            .navigationTitle(draft.id.isEmpty ? "新建场景" : "编辑场景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if hasChanges { showingDiscardConfirmation = true }
                        else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { if await model.saveScene(draft.normalized) { dismiss() } }
                    }
                    .disabled(validationMessage != nil)
                }
            }
            .sheet(isPresented: $showingTrackPicker) {
                TrackPicker(existing: Set(draft.tracks.map(\.id))) { track in
                    draft.tracks.append(track)
                }
            }
            .sheet(item: $editingSchedule) { indexed in
                ScheduleEditor(schedule: indexed.schedule) { value in
                    if draft.schedules.indices.contains(indexed.index) { draft.schedules[indexed.index] = value }
                }
            }
            .sheet(isPresented: $showingNewSchedule) {
                ScheduleEditor(schedule: .init(time: "23:00", daysOfWeek: [1, 2, 3, 4, 5, 6, 7])) { value in
                    draft.schedules.append(value)
                }
            }
            .confirmationDialog("放弃未保存的修改？", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
        }
        .tint(LuminaTheme.indigo)
        .interactiveDismissDisabled(hasChanges)
    }

    private var hasChanges: Bool { draft != original }
    private var validationMessage: String? { draft.normalized.validationError(devices: model.devices) }
}

private struct TrackEditorCard: View {
    @Binding var track: SceneTrack
    let device: Device?
    let delete: () -> Void
    @State private var editingFrame: IndexedFrame?
    @State private var showingNewFrame = false

    private var capability: ZoneCapability? {
        device?.capabilities.zones.first { $0.id == track.zone }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device?.name ?? track.deviceId).font(.headline)
                    Text(capability?.label ?? track.zone).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("循环", isOn: $track.repeatTrack)
                    .toggleStyle(.switch)
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
            }
            if track.keyframes.isEmpty {
                Text("尚无关键帧").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(track.keyframes.indices, id: \.self) { index in
                    Button {
                        editingFrame = IndexedFrame(index: index, frame: track.keyframes[index])
                    } label: {
                        HStack(alignment: .top) {
                            Text(offsetLabel(track.keyframes[index].offsetMs))
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.tint)
                                .frame(width: 66, alignment: .leading)
                            Text(track.keyframes[index].summary)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("删除", role: .destructive) { track.keyframes.remove(at: index) }
                    }
                }
            }
            Button("添加关键帧", systemImage: "plus") { showingNewFrame = true }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
        .sheet(item: $editingFrame) { indexed in
            KeyframeEditor(
                frame: indexed.frame,
                device: device,
                capability: capability,
                inheritedSceneID: activeSceneID(before: indexed.index)
            ) { value in
                if track.keyframes.indices.contains(indexed.index) { track.keyframes[indexed.index] = value }
            }
        }
        .sheet(isPresented: $showingNewFrame) {
            KeyframeEditor(
                frame: .init(offsetMs: track.keyframes.map(\.offsetMs).max() ?? 0),
                device: device,
                capability: capability,
                inheritedSceneID: activeSceneID(before: track.keyframes.count)
            ) { value in
                track.keyframes.append(value)
                track.keyframes.sort { $0.offsetMs < $1.offsetMs }
            }
        }
    }

    private func activeSceneID(before index: Int) -> Int? {
        var sceneID: Int?
        for frame in track.keyframes.prefix(index) {
            if frame.colorTemperatureKelvin != nil || frame.rgb != nil || frame.whiteChannels != nil || frame.segmentRgb != nil {
                sceneID = nil
            }
            if let nextSceneID = frame.sceneId { sceneID = nextSceneID }
        }
        return sceneID
    }
}

private struct TrackPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let existing: Set<String>
    let add: (SceneTrack) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.devices) { device in
                    Section(device.name) {
                        ForEach(device.capabilities.zones) { zone in
                            let track = SceneTrack(deviceId: device.id, zone: zone.id)
                            Button {
                                add(track)
                                dismiss()
                            } label: {
                                Label(zone.label, systemImage: "lightbulb")
                            }
                            .disabled(existing.contains(track.id))
                        }
                    }
                }
            }
            .navigationTitle("添加轨道")
            .toolbar { Button("取消") { dismiss() } }
        }
    }
}

private struct KeyframeEditor: View {
    @Environment(\.dismiss) private var dismiss
    let device: Device?
    let capability: ZoneCapability?
    let inheritedSceneID: Int?
    let save: (SceneKeyframe) -> Void
    @State private var frame: SceneKeyframe
    @State private var offsetSeconds: Double
    @State private var powerChoice: PowerChoice
    @State private var hasBrightness: Bool
    @State private var hasCCT: Bool
    @State private var hasRGB: Bool
    @State private var hasScene: Bool
    @State private var hasSpeed: Bool
    @State private var hasRatio: Bool
    @State private var hasWhite: Bool
    @State private var hasSegments: Bool
    @State private var color: Color
    @State private var leftColor: Color
    @State private var rightColor: Color

    private var nativeScenes: [NativeScene] { device?.capabilities.nativeScenes ?? [] }
    private var selectedNativeScene: NativeScene? {
        let sceneID = hasScene ? (frame.sceneId ?? nativeScenes.first?.id) : inheritedSceneID
        guard let sceneID else { return nil }
        return nativeScenes.first { $0.id == sceneID }
    }

    init(
        frame: SceneKeyframe,
        device: Device?,
        capability: ZoneCapability?,
        inheritedSceneID: Int?,
        save: @escaping (SceneKeyframe) -> Void
    ) {
        self.device = device
        self.capability = capability
        self.inheritedSceneID = inheritedSceneID
        self.save = save
        _frame = State(initialValue: frame)
        _offsetSeconds = State(initialValue: Double(frame.offsetMs) / 1_000)
        _powerChoice = State(initialValue: frame.power.map { $0 ? .on : .off } ?? .keep)
        _hasBrightness = State(initialValue: frame.brightness != nil)
        _hasCCT = State(initialValue: frame.colorTemperatureKelvin != nil)
        _hasRGB = State(initialValue: frame.rgb != nil)
        _hasScene = State(initialValue: frame.sceneId != nil)
        _hasSpeed = State(initialValue: frame.speed != nil)
        _hasRatio = State(initialValue: frame.ratio != nil)
        _hasWhite = State(initialValue: frame.whiteChannels != nil)
        _hasSegments = State(initialValue: frame.segmentRgb != nil)
        _color = State(initialValue: frame.rgb.map(Color.init(rgb:)) ?? .orange)
        _leftColor = State(initialValue: frame.segmentRgb.map { Color(rgb: $0.left) } ?? .red)
        _rightColor = State(initialValue: frame.segmentRgb.map { Color(rgb: $0.right) } ?? .blue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("时间与过渡") {
                    LabeledContent("偏移秒数") {
                        TextField("秒", value: $offsetSeconds, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }
                    Picker("Easing", selection: $frame.easing) {
                        Text("线性").tag("linear")
                        Text("立即切换").tag("step")
                    }
                }
                Section("电源") {
                    Picker("电源状态", selection: $powerChoice) {
                        ForEach(PowerChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let range = capability?.brightness {
                    optionalSlider("亮度", enabled: $hasBrightness, value: Binding(
                        get: { Double(frame.brightness ?? range.min) },
                        set: { frame.brightness = Int($0) }
                    ), range: Double(range.min)...Double(range.max), suffix: "%")
                }
                if let range = capability?.colorTemperature {
                    optionalSlider("色温", enabled: $hasCCT, value: Binding(
                        get: { Double(frame.colorTemperatureKelvin ?? range.min) },
                        set: { frame.colorTemperatureKelvin = Int($0) }
                    ), range: Double(range.min)...Double(range.max), step: 50, suffix: "K")
                }
                if capability?.rgb == true {
                    Section {
                        Toggle("设置 RGB", isOn: $hasRGB)
                        if hasRGB { ColorPicker("颜色", selection: $color, supportsOpacity: false) }
                    }
                }
                if !nativeScenes.isEmpty {
                    Section {
                        Toggle("设置原生效果", isOn: $hasScene)
                        if hasScene {
                            Picker("效果", selection: Binding(
                                get: { frame.sceneId ?? nativeScenes[0].id },
                                set: { selectNativeScene($0) }
                            )) {
                                ForEach(nativeScenes) { Text($0.name).tag($0.id) }
                            }
                        }
                        if let effect = selectedNativeScene, effect.dynamic {
                            Toggle("设置效果速度", isOn: $hasSpeed)
                            if hasSpeed {
                                let range = (effect.speedMin ?? 20)...(effect.speedMax ?? 200)
                                Stepper("速度 \(frame.speed ?? 100)", value: Binding(
                                    get: { min(max(frame.speed ?? 100, range.lowerBound), range.upperBound) },
                                    set: { frame.speed = $0 }
                                ), in: range)
                            }
                        } else if hasScene {
                            Text("静态效果不使用速度参数")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if device?.capabilities.supportsRatio == true {
                    optionalSlider("双区比例", enabled: $hasRatio, value: Binding(
                        get: { Double(frame.ratio ?? 50) },
                        set: { frame.ratio = Int($0) }
                    ), range: 0...100, suffix: "%")
                }
                if capability?.whiteChannels == true {
                    Section {
                        Toggle("设置冷暖白通道", isOn: $hasWhite)
                        if hasWhite {
                            Stepper("冷白 \(frame.whiteChannels?.cold ?? 0)", value: whiteBinding(\.cold), in: 0...255)
                            Stepper("暖白 \(frame.whiteChannels?.warm ?? 0)", value: whiteBinding(\.warm), in: 0...255)
                        }
                    }
                }
                if capability?.segmentRgb == true {
                    Section {
                        Toggle("设置左右分段", isOn: $hasSegments)
                        if hasSegments {
                            ColorPicker("左侧", selection: $leftColor, supportsOpacity: false)
                            ColorPicker("右侧", selection: $rightColor, supportsOpacity: false)
                        }
                    }
                }
            }
            .navigationTitle("关键帧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        normalize()
                        save(frame)
                        dismiss()
                    }
                }
            }
            .onChange(of: hasCCT) { _, enabled in if enabled { selectAppearance(.cct) } }
            .onChange(of: hasRGB) { _, enabled in if enabled { selectAppearance(.rgb) } }
            .onChange(of: hasScene) { _, enabled in if enabled { selectAppearance(.scene) } }
            .onChange(of: hasWhite) { _, enabled in if enabled { selectAppearance(.white) } }
            .onChange(of: hasSegments) { _, enabled in if enabled { selectAppearance(.segments) } }
        }
    }

    @ViewBuilder
    private func optionalSlider(
        _ title: String,
        enabled: Binding<Bool>,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        suffix: String
    ) -> some View {
        Section {
            Toggle("设置\(title)", isOn: enabled)
            if enabled.wrappedValue {
                Slider(value: value, in: range, step: step)
                LabeledContent(title, value: "\(Int(value.wrappedValue))\(suffix)")
            }
        }
    }

    private func whiteBinding(_ keyPath: WritableKeyPath<WhiteChannels, Int>) -> Binding<Int> {
        Binding(
            get: { (frame.whiteChannels ?? .init(cold: 0, warm: 0))[keyPath: keyPath] },
            set: { value in
                var channels = frame.whiteChannels ?? .init(cold: 0, warm: 0)
                channels[keyPath: keyPath] = value
                frame.whiteChannels = channels
            }
        )
    }

    private func normalize() {
        frame.offsetMs = Int64(max(0, offsetSeconds) * 1_000)
        frame.power = powerChoice.value
        if hasBrightness {
            frame.brightness = frame.brightness ?? capability?.brightness?.min
        } else { frame.brightness = nil }
        if hasCCT {
            frame.colorTemperatureKelvin = frame.colorTemperatureKelvin ?? capability?.colorTemperature?.min
        } else { frame.colorTemperatureKelvin = nil }
        frame.rgb = hasRGB ? color.rgbValue : nil
        if hasScene {
            if frame.sceneId == nil { frame.sceneId = nativeScenes.first?.id }
        } else { frame.sceneId = nil }
        if hasSpeed, let effect = selectedNativeScene, effect.dynamic {
            let range = (effect.speedMin ?? 20)...(effect.speedMax ?? 200)
            frame.speed = min(max(frame.speed ?? 100, range.lowerBound), range.upperBound)
        } else { frame.speed = nil }
        if hasRatio { frame.ratio = frame.ratio ?? 50 }
        else { frame.ratio = nil }
        if hasWhite { frame.whiteChannels = frame.whiteChannels ?? .init(cold: 0, warm: 0) }
        else { frame.whiteChannels = nil }
        frame.segmentRgb = hasSegments ? .init(left: leftColor.rgbValue, right: rightColor.rgbValue) : nil
    }

    private func selectNativeScene(_ sceneID: Int) {
        frame.sceneId = sceneID
        guard let effect = nativeScenes.first(where: { $0.id == sceneID }), effect.dynamic else {
            hasSpeed = false
            frame.speed = nil
            return
        }
        if hasSpeed {
            let range = (effect.speedMin ?? 20)...(effect.speedMax ?? 200)
            frame.speed = min(max(frame.speed ?? 100, range.lowerBound), range.upperBound)
        }
    }

    private func selectAppearance(_ selection: AppearanceSelection) {
        hasCCT = selection == .cct
        hasRGB = selection == .rgb
        hasScene = selection == .scene
        hasWhite = selection == .white
        hasSegments = selection == .segments
        if selection != .scene { hasSpeed = false }
    }
}

private struct ScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    let save: (SceneSchedule) -> Void
    @State private var schedule: SceneSchedule
    @State private var time: Date

    init(schedule: SceneSchedule, save: @escaping (SceneSchedule) -> Void) {
        self.save = save
        _schedule = State(initialValue: schedule)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        _time = State(initialValue: formatter.date(from: schedule.time) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("启用", isOn: $schedule.enabled)
                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                Section("星期") {
                    FlowLayout {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(dayName(day), isOn: Binding(
                                get: { schedule.daysOfWeek.contains(day) },
                                set: { selected in
                                    if selected { schedule.daysOfWeek.append(day) }
                                    else { schedule.daysOfWeek.removeAll { $0 == day } }
                                    schedule.daysOfWeek = Array(Set(schedule.daysOfWeek)).sorted()
                                }
                            ))
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                        }
                    }
                }
                TextField("IANA 时区", text: $schedule.timezone)
                    .textInputAutocapitalization(.never)
                Text("例如 Europe/Zurich。夏令时由 Hub 按此时区处理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("周计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        schedule.time = formatter.string(from: time)
                        if schedule.id.isEmpty { schedule.id = "schedule-\(UUID().uuidString.lowercased())" }
                        save(schedule)
                        dismiss()
                    }
                    .disabled(schedule.daysOfWeek.isEmpty || TimeZone(identifier: schedule.timezone) == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private enum PowerChoice: String, CaseIterable, Identifiable {
    case keep, on, off
    var id: String { rawValue }
    var title: String { switch self { case .keep: "保持"; case .on: "打开"; case .off: "关闭" } }
    var value: Bool? { switch self { case .keep: nil; case .on: true; case .off: false } }
}

private enum AppearanceSelection { case cct, rgb, scene, white, segments }

private struct IndexedFrame: Identifiable {
    let index: Int
    let frame: SceneKeyframe
    var id: Int { index }
}

private struct IndexedSchedule: Identifiable {
    let index: Int
    let schedule: SceneSchedule
    var id: Int { index }
}

private func offsetLabel(_ ms: Int64) -> String {
    let total = ms / 1_000
    let minutes = total / 60
    let seconds = total % 60
    return String(format: "%02lld:%02lld", minutes, seconds)
}

private func dayName(_ day: Int) -> String {
    [1: "周一", 2: "周二", 3: "周三", 4: "周四", 5: "周五", 6: "周六", 7: "周日"][day] ?? "?"
}

private func daySummary(_ days: [Int]) -> String {
    if Set(days) == Set(1...7) { return "每天" }
    if Set(days) == Set(1...5) { return "工作日" }
    return days.sorted().map(dayName).joined(separator: "、")
}
