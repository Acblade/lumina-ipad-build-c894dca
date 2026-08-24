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
        _ = try await LuminaAPIClient.shared.runScene(connection, sceneID: sceneID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TurnOffAllIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "关闭全部灯光"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let connection = try widgetConnection()
        let devices = try await LuminaAPIClient.shared.devices(connection)
        // Keep this deliberately sequential. Several bulbs share one local UDP
        // transport and concurrent control-many requests can be dropped by a Hub
        // that is already forwarding a previous packet.
        for device in devices where device.online {
            for zone in device.capabilities.zones where zone.power {
                try await LuminaAPIClient.shared.control(
                    connection,
                    deviceID: device.id,
                    action: .init(zone: zone.id, power: false)
                )
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
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
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

enum WidgetActionError: LocalizedError {
    case notConfigured
    var errorDescription: String? { "请先打开 Lumina 并连接 Hub" }
}

private func widgetConnection() throws -> HubConnection {
    let connection = SharedSettings().loadConnection()
    guard connection.isConfigured, !connection.bearerToken.isEmpty else {
        throw WidgetActionError.notConfigured
    }
    return connection
}
