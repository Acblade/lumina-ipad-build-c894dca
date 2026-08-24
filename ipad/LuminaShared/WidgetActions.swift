import AppIntents
import WidgetKit

/// LiveActivityIntent is deliberately used for interactive widget actions.
/// iPadOS executes it in the main app process without foregrounding the app,
/// so a free-signed widget can reuse the app-private Keychain connection.
struct RunSceneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "运行 Lumina 场景"
    static var description = IntentDescription("通过家庭 Hub 运行一个灯光场景。")
    static var openAppWhenRun = false

    @Parameter(title: "场景 ID")
    var sceneID: String

    init() { sceneID = "" }
    init(sceneID: String) { self.sceneID = sceneID }

    func perform() async throws -> some IntentResult {
        let connection = try widgetConnection()
        let store = SharedWidgetControlStore()
        let previous = store.load()
        store.save(.init(anyOn: true, selectedBrightness: nil))
        WidgetCenter.shared.reloadAllTimelines()
        do {
            _ = try await LuminaAPIClient.shared.runScene(connection, sceneID: sceneID)
            let devices = try? await LuminaAPIClient.shared.devices(connection)
            store.save(devices.map(WidgetControlSnapshot.inferred(from:))
                ?? .init(anyOn: true, selectedBrightness: nil))
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        } catch {
            if let previous { store.save(previous) }
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }
}

struct ToggleAllPowerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "切换全部灯光"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let connection = try widgetConnection()
        let devices = try await LuminaAPIClient.shared.devices(connection)
        let shouldTurnOn = !devices.contains { device in
            device.online && device.capabilities.zones.contains { zone in
                zone.power && device.zoneState(zone.id).power
            }
        }
        let store = SharedWidgetControlStore()
        let previous = store.load() ?? .inferred(from: devices)
        store.save(.init(anyOn: shouldTurnOn, selectedBrightness: nil))
        WidgetCenter.shared.reloadAllTimelines()
        // Keep this deliberately sequential. Several bulbs share one local UDP
        // transport and concurrent control-many requests can be dropped by a Hub
        // that is already forwarding a previous packet.
        do {
            for device in devices where device.online {
                for zone in device.capabilities.zones where zone.power {
                    try await LuminaAPIClient.shared.control(
                        connection,
                        deviceID: device.id,
                        action: .init(zone: zone.id, power: shouldTurnOn)
                    )
                }
            }
            let refreshed = (try? await LuminaAPIClient.shared.devices(connection)) ?? devices
            let inferred = WidgetControlSnapshot.inferred(from: refreshed)
            store.save(.init(
                anyOn: shouldTurnOn,
                selectedBrightness: shouldTurnOn ? inferred.selectedBrightness : previous.selectedBrightness
            ))
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        } catch {
            store.save(previous)
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }
}

struct SetAllBrightnessIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Lumina 总亮度"
    static var openAppWhenRun = false

    @Parameter(title: "亮度")
    var brightness: Int

    init() { brightness = 50 }
    init(brightness: Int) { self.brightness = brightness }

    func perform() async throws -> some IntentResult {
        let connection = try widgetConnection()
        let devices = try await LuminaAPIClient.shared.devices(connection)
        let store = SharedWidgetControlStore()
        let previous = store.load() ?? .inferred(from: devices)
        let selected = min(max(brightness, 1), 100)
        store.save(.init(anyOn: true, selectedBrightness: selected))
        WidgetCenter.shared.reloadAllTimelines()
        do {
            for device in devices where device.online {
                for zone in device.capabilities.zones {
                    guard let range = zone.brightness else { continue }
                    try await LuminaAPIClient.shared.control(
                        connection,
                        deviceID: device.id,
                        action: DeviceControlRequest(
                            zone: zone.id,
                            power: true,
                            brightness: min(max(brightness, range.min), range.max)
                        )
                    )
                }
            }
            // Preserve the exact preset the user chose. Some lamps clamp 1% to
            // their own minimum and their immediate read-back therefore cannot
            // be used to identify the selected widget button reliably.
            store.save(.init(anyOn: true, selectedBrightness: selected))
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        } catch {
            store.save(previous)
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }
}

enum WidgetActionError: LocalizedError {
    case notConfigured
    var errorDescription: String? { "请先打开 Lumina 并连接 Hub" }
}

func widgetConnection() throws -> HubConnection {
    let connection = SharedSettings().loadConnection()
    guard connection.isConfigured, !connection.bearerToken.isEmpty else {
        throw WidgetActionError.notConfigured
    }
    return connection
}
