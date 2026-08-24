import Foundation
import SwiftUI
import WidgetKit

struct PendingPairing: Identifiable, Equatable {
    let id = UUID()
    let connection: HubConnection
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [Device]
    @Published private(set) var modes: [LightMode]
    @Published private(set) var scenes: [Scene]
    @Published private(set) var runs: [RunInfo] = []
    @Published private(set) var connection: HubConnection
    @Published private(set) var isLoading = false
    @Published private(set) var isOnline = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?
    @Published var pendingPairing: PendingPairing?

    private let api: LuminaAPIClient
    private let settings: any ConnectionStore
    private let cache: any CacheStore
    private var refreshTask: Task<Void, Never>?

    init(
        api: LuminaAPIClient = .shared,
        settings: any ConnectionStore = SharedSettings(),
        cache: any CacheStore = SharedCache()
    ) {
        self.api = api
        self.settings = settings
        self.cache = cache
        connection = settings.loadConnection()
        devices = cache.loadDevices()
        modes = cache.loadModes()
        scenes = cache.loadScenes()
    }

    deinit { refreshTask?.cancel() }

    var activeRuns: [RunInfo] {
        runs.filter { ["running", "scheduled"].contains($0.status ?? "") }
    }

    var isConfigured: Bool { connection.isConfigured && !connection.bearerToken.isEmpty }

    func beginForegroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await refreshAll(silent: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { await refreshAll(silent: true) }
            }
        }
    }

    func stopForegroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshAll(silent: Bool = false) async {
        guard isConfigured else {
            if !silent { errorMessage = "请先在设置中连接 Lumina Hub" }
            return
        }
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }
        do {
            async let loadedDevices = api.devices(connection)
            async let loadedModes = api.modes(connection)
            async let loadedScenes = api.scenes(connection)
            async let loadedRuns = api.runs(connection)
            let values = try await (loadedDevices, loadedModes, loadedScenes, loadedRuns)
            devices = values.0.sorted { ($0.room ?? "", $0.name) < ($1.room ?? "", $1.name) }
            modes = values.1
            scenes = values.2
            runs = values.3
            isOnline = true
            lastUpdated = Date()
            cache.save(devices: devices, scenes: scenes, modes: modes)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            isOnline = false
            if !silent { present(error) }
        }
    }

    func refreshDevices(silent: Bool = true) async {
        guard isConfigured else { return }
        do {
            devices = try await api.devices(connection)
            isOnline = true
            lastUpdated = Date()
            cache.save(devices: devices, scenes: scenes, modes: modes)
        } catch {
            isOnline = false
            if !silent { present(error) }
        }
    }

    func saveConnection(_ candidate: HubConnection) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        let candidate = candidate.normalized
        do {
            try await api.health(candidate)
            try settings.saveConnection(candidate)
            connection = candidate
            confirmationMessage = "Hub 已连接"
            await refreshAll(silent: true)
            return true
        } catch {
            present(error)
            return false
        }
    }

    func preparePairing(from url: URL) {
        errorMessage = nil
        guard url.scheme?.lowercased() == "lumina",
              url.host?.lowercased() == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            errorMessage = "无效的 Lumina 配对二维码"
            return
        }
        let values = Dictionary(
            components.queryItems?.compactMap { item in item.value.map { (item.name, $0) } } ?? [],
            uniquingKeysWith: { _, latest in latest }
        )
        let candidate = HubConnection(
            baseURL: values["baseURL"] ?? "",
            bearerToken: values["token"] ?? ""
        ).normalized
        guard candidate.isConfigured,
              !candidate.bearerToken.isEmpty,
              let hubURL = URL(string: candidate.baseURL),
              ["http", "https"].contains(hubURL.scheme?.lowercased() ?? ""),
              hubURL.user == nil,
              hubURL.password == nil,
              hubURL.fragment == nil else {
            errorMessage = "配对二维码缺少有效的 Hub 地址或 Token"
            return
        }
        pendingPairing = PendingPairing(connection: candidate)
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme?.lowercased() == "lumina" else {
            errorMessage = "无效的 Lumina 链接"
            return
        }
        switch url.host?.lowercased() {
        case "pair":
            preparePairing(from: url)
        case "run-scene":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let sceneID = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  !sceneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "场景链接缺少有效的场景 ID"
                return
            }
            await runScene(
                sceneID: sceneID,
                displayName: scenes.first(where: { $0.id == sceneID })?.name
            )
        default:
            errorMessage = "不支持的 Lumina 链接"
        }
    }

    func confirmPendingPairing() async {
        guard let pendingPairing else { return }
        if await saveConnection(pendingPairing.connection) {
            self.pendingPairing = nil
        }
    }

    func cancelPendingPairing() {
        pendingPairing = nil
    }

    func control(deviceID: String, action: DeviceControlRequest) async {
        guard isConfigured else { presentConfigurationError(); return }
        let previous = devices
        applyOptimistic(deviceID: deviceID, action: action)
        do {
            try await api.control(connection, deviceID: deviceID, action: action)
            await refreshDevices()
        } catch {
            devices = previous
            present(error)
            await refreshDevices()
        }
    }

    func setAllPower(_ power: Bool) async {
        guard isConfigured else { presentConfigurationError(); return }
        let snapshot = devices
        for device in devices {
            for zone in device.capabilities.zones where zone.power {
                applyOptimistic(deviceID: device.id, action: .init(zone: zone.id, power: power))
            }
        }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for device in snapshot {
                    let actions = device.capabilities.zones.compactMap { zone in
                        zone.power ? DeviceControlRequest(zone: zone.id, power: power) : nil
                    }
                    guard !actions.isEmpty else { continue }
                    group.addTask { [api, connection] in
                        try await api.controlMany(connection, deviceID: device.id, actions: actions)
                    }
                }
                try await group.waitForAll()
            }
            confirmationMessage = power ? "全部灯光已打开" : "全部灯光已关闭"
            await refreshDevices()
        } catch {
            devices = snapshot
            present(error)
            await refreshDevices()
        }
    }

    func setAllBrightness(_ brightness: Int) async {
        guard isConfigured else { presentConfigurationError(); return }
        let snapshot = devices
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for device in snapshot {
                    let actions = device.capabilities.zones.compactMap { zone -> DeviceControlRequest? in
                        guard let range = zone.brightness else { return nil }
                        return .init(
                            zone: zone.id,
                            power: true,
                            brightness: brightness.clamped(to: range.min...range.max)
                        )
                    }
                    guard !actions.isEmpty else { continue }
                    group.addTask { [api, connection] in
                        try await api.controlMany(connection, deviceID: device.id, actions: actions)
                    }
                }
                try await group.waitForAll()
            }
            confirmationMessage = "全部亮度已设为 \(brightness)%"
            await refreshDevices()
        } catch {
            present(error)
            await refreshDevices()
        }
    }

    func discover() async {
        guard isConfigured else { presentConfigurationError(); return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await api.discover(connection)
            confirmationMessage = "局域网发现完成"
            await refreshAll(silent: true)
        } catch {
            present(error)
            await refreshDevices()
        }
    }

    func rename(deviceID: String, name: String, room: String?) async -> Bool {
        guard isConfigured else { presentConfigurationError(); return false }
        do {
            try await api.patch(connection, deviceID: deviceID, patch: .init(name: name, room: room))
            await refreshDevices()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func applyMode(_ mode: LightMode, targets: [ModeTarget], brightness: Int, speed: Int?) async {
        guard isConfigured else { presentConfigurationError(); return }
        guard !targets.isEmpty else { errorMessage = "请至少选择一个灯区"; return }
        do {
            try await api.applyMode(
                connection,
                modeID: mode.id,
                request: .init(targets: targets, brightness: brightness, speed: mode.dynamic ? speed : nil)
            )
            confirmationMessage = "已应用“\(mode.name)”"
            await refreshDevices()
        } catch {
            present(error)
            await refreshDevices()
        }
    }

    func saveScene(_ scene: Scene) async -> Bool {
        guard isConfigured else { presentConfigurationError(); return false }
        if let validationError = scene.validationError(devices: devices) {
            errorMessage = validationError
            return false
        }
        do {
            if scene.id.isEmpty {
                _ = try await api.createScene(connection, scene: scene)
            } else {
                _ = try await api.updateScene(connection, scene: scene)
            }
            scenes = try await api.scenes(connection)
            cache.save(devices: devices, scenes: scenes, modes: modes)
            WidgetCenter.shared.reloadAllTimelines()
            confirmationMessage = "场景已保存"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteScene(_ scene: Scene) async -> Bool {
        guard isConfigured else { presentConfigurationError(); return false }
        do {
            try await api.deleteScene(connection, sceneID: scene.id)
            scenes.removeAll { $0.id == scene.id }
            cache.save(devices: devices, scenes: scenes, modes: modes)
            WidgetCenter.shared.reloadAllTimelines()
            confirmationMessage = "场景已删除"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func runScene(_ scene: Scene) async {
        await runScene(sceneID: scene.id, displayName: scene.name)
    }

    func runScene(sceneID: String, displayName: String? = nil) async {
        guard isConfigured else { presentConfigurationError(); return }
        do {
            let run = try await api.runScene(connection, sceneID: sceneID)
            runs.removeAll { $0.id == run.id }
            runs.insert(run, at: 0)
            let name = displayName ?? scenes.first(where: { $0.id == sceneID })?.name
            confirmationMessage = name.map { "正在运行“\($0)”" } ?? "场景已启动"
        } catch { present(error) }
    }

    func stopRun(_ run: RunInfo) async {
        do {
            try await api.stopRun(connection, runID: run.id)
            runs.removeAll { $0.id == run.id }
            confirmationMessage = "场景已停止"
        } catch { present(error) }
    }

    func scene(id: String) -> Scene? { scenes.first { $0.id == id } }
    func device(id: String) -> Device? { devices.first { $0.id == id } }

    private func applyOptimistic(deviceID: String, action: DeviceControlRequest) {
        guard let deviceIndex = devices.firstIndex(where: { $0.id == deviceID }),
              let zoneID = action.zone else { return }
        var zone = devices[deviceIndex].state.zones[zoneID] ?? .init()
        if let power = action.power { zone.power = power }
        if let brightness = action.brightness { zone.brightness = brightness }
        if let cct = action.colorTemperatureKelvin {
            zone.colorTemperatureKelvin = cct
            zone.rgb = nil
            zone.sceneId = nil
        }
        if let rgb = action.rgb {
            zone.rgb = rgb
            zone.colorTemperatureKelvin = nil
            zone.sceneId = nil
        }
        if let sceneID = action.sceneId { zone.sceneId = sceneID }
        if let speed = action.speed { zone.speed = speed }
        if let ratio = action.ratio { zone.ratio = ratio }
        if let white = action.whiteChannels { zone.whiteChannels = white }
        if let segment = action.segmentRgb { zone.segmentRgb = segment }
        devices[deviceIndex].state.zones[zoneID] = zone
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func presentConfigurationError() {
        errorMessage = "请先在设置中连接 Lumina Hub"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
