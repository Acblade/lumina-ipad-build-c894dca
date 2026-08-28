import Foundation
import Security

protocol ConnectionStore {
    func loadConnection() -> HubConnection
    func saveConnection(_ connection: HubConnection) throws
}

protocol CacheStore {
    func loadDevices() -> [Device]
    func loadScenes() -> [Scene]
    func loadModes() -> [LightMode]
    func save(devices: [Device], scenes: [Scene], modes: [LightMode])
}

enum LuminaShared {
    enum SecretStorageRoute: Equatable {
        case sharedProtectedFile
        case appPrivateKeychain
        case configuredKeychain
    }

    private static let canonicalBundleRoot = "com.sigo.lumina"
    static let canonicalAppGroup = "group.\(canonicalBundleRoot)"

    static func isXtoolProvisioned(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier,
              let rootRange = bundleIdentifier.range(of: canonicalBundleRoot) else {
            return false
        }
        let provisioningPrefix = String(bundleIdentifier[..<rootRange.lowerBound])
        return provisioningPrefix.hasPrefix("XTL-") && provisioningPrefix.hasSuffix(".")
    }

    static func appGroupCandidates(for bundleIdentifier: String?) -> [String] {
        var candidates = [canonicalAppGroup]
        guard isXtoolProvisioned(bundleIdentifier: bundleIdentifier),
              let bundleIdentifier,
              let rootRange = bundleIdentifier.range(of: canonicalBundleRoot) else {
            return candidates
        }
        let provisioningPrefix = String(bundleIdentifier[..<rootRange.lowerBound])
        candidates.append("group.\(provisioningPrefix)\(canonicalBundleRoot)")
        return candidates
    }

    /// Xtool prefixes free-provisioned bundle identifiers with `XTL-<TeamID>.`.
    /// The signing prefix itself does not include `XTL-`, so derive the Keychain
    /// access group that both the app and its widget extension can open.
    static func keychainGroupCandidates(
        for bundleIdentifier: String?,
        configuredGroup: String?
    ) -> [String] {
        var candidates: [String] = []
        if let bundleIdentifier,
           bundleIdentifier.hasPrefix("XTL-"),
           let separator = bundleIdentifier.firstIndex(of: ".") {
            let encodedTeam = bundleIdentifier[bundleIdentifier.index(bundleIdentifier.startIndex, offsetBy: 4)..<separator]
            if !encodedTeam.isEmpty {
                candidates.append("\(encodedTeam).\(canonicalBundleRoot).shared")
            }
        }
        if let configuredGroup = configuredGroup?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredGroup.isEmpty,
           !candidates.contains(configuredGroup) {
            candidates.append(configuredGroup)
        }
        return candidates
    }

    private static var sharedContainer: (identifier: String, url: URL)? {
        for identifier in appGroupCandidates(for: Bundle.main.bundleIdentifier) {
            if let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            ) {
                return (identifier, url)
            }
        }
        return nil
    }

    static var appGroup: String {
        sharedContainer?.identifier
            ?? appGroupCandidates(for: Bundle.main.bundleIdentifier)[0]
    }
    static var appGroupContainerURL: URL? { sharedContainer?.url }
    static var hasSharedContainer: Bool { sharedContainer != nil }
    static var usesXtoolProvisioning: Bool {
        isXtoolProvisioned(bundleIdentifier: Bundle.main.bundleIdentifier)
    }
    static func secretStorageRoute(
        usesXtoolProvisioning: Bool,
        hasSharedContainer: Bool
    ) -> SecretStorageRoute {
        guard usesXtoolProvisioning else { return .configuredKeychain }
        return hasSharedContainer ? .sharedProtectedFile : .appPrivateKeychain
    }
    static var secretStorageRoute: SecretStorageRoute {
        secretStorageRoute(
            usesXtoolProvisioning: usesXtoolProvisioning,
            hasSharedContainer: hasSharedContainer
        )
    }
    static var defaults: UserDefaults {
        guard let identifier = sharedContainer?.identifier,
              let defaults = UserDefaults(suiteName: identifier) else {
            return .standard
        }
        return defaults
    }

    static var keychainGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "LuminaKeychainAccessGroup") as? String
    }
    static var keychainGroupCandidates: [String] {
        keychainGroupCandidates(
            for: Bundle.main.bundleIdentifier,
            configuredGroup: keychainGroup
        )
    }
}

struct SharedSettings: ConnectionStore {
    private enum Key {
        static let baseURL = "hub.baseURL"
        static let localBaseURL = "hub.localBaseURL"
        static let cloudflareID = "hub.cloudflareID"
        static let bearerToken = "hub.bearerToken"
        static let cloudflareSecret = "hub.cloudflareSecret"
    }

    private let defaults = LuminaShared.defaults

    func loadConnection() -> HubConnection {
        HubConnection(
            baseURL: defaults.string(forKey: Key.baseURL) ?? "",
            bearerToken: SharedSecretStore.read(Key.bearerToken),
            cloudflareClientID: defaults.string(forKey: Key.cloudflareID) ?? "",
            cloudflareClientSecret: SharedSecretStore.read(Key.cloudflareSecret),
            localBaseURL: defaults.string(forKey: Key.localBaseURL) ?? ""
        )
    }

    func saveConnection(_ connection: HubConnection) throws {
        let value = connection.normalized
        defaults.set(value.baseURL, forKey: Key.baseURL)
        defaults.set(value.localBaseURL, forKey: Key.localBaseURL)
        defaults.set(value.cloudflareClientID, forKey: Key.cloudflareID)
        try SharedSecretStore.write(value.bearerToken, key: Key.bearerToken)
        try SharedSecretStore.write(value.cloudflareClientSecret, key: Key.cloudflareSecret)
    }
}

struct SharedCache: CacheStore {
    private enum Key {
        static let devices = "cache.devices"
        static let scenes = "cache.scenes"
        static let modes = "cache.modes"
    }

    private let defaults = LuminaShared.defaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadDevices() -> [Device] { load([Device].self, key: Key.devices) ?? [] }
    func loadScenes() -> [Scene] { load([Scene].self, key: Key.scenes) ?? [] }
    func loadModes() -> [LightMode] { load([LightMode].self, key: Key.modes) ?? [] }

    func save(devices: [Device], scenes: [Scene], modes: [LightMode]) {
        store(devices, key: Key.devices)
        store(scenes, key: Key.scenes)
        store(modes, key: Key.modes)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func store<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }
}

struct WidgetControlSnapshot: Codable, Equatable, Sendable {
    var anyOn: Bool
    var selectedBrightness: Int?

    static func inferred(from devices: [Device]) -> WidgetControlSnapshot {
        let reportedZones = devices.flatMap { device in
            device.capabilities.zones.compactMap { capability -> ZoneState? in
                guard device.online else { return nil }
                return device.state.zones[capability.id]
            }
        }
        let brightnessValues = devices.flatMap { device in
            device.capabilities.zones.compactMap { capability -> Int? in
                guard device.online,
                      capability.brightness != nil,
                      let state = device.state.zones[capability.id],
                      state.power else { return nil }
                return state.brightness
            }
        }
        let uniformBrightness = Set(brightnessValues).count == 1
            ? brightnessValues.first
            : nil
        let selectable = uniformBrightness.flatMap { [1, 25, 50, 75, 100].contains($0) ? $0 : nil }
        return WidgetControlSnapshot(
            anyOn: reportedZones.contains(where: \.power),
            selectedBrightness: selectable
        )
    }
}

struct SharedWidgetControlStore {
    private static let key = "widget.control-state.v1"
    private let defaults = LuminaShared.defaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> WidgetControlSnapshot? {
        for accessGroup in LuminaShared.keychainGroupCandidates {
            let encoded = Keychain.read(Self.key, accessGroup: accessGroup)
            guard let data = Data(base64Encoded: encoded),
                  let value = try? decoder.decode(WidgetControlSnapshot.self, from: data) else {
                continue
            }
            return value
        }
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? decoder.decode(WidgetControlSnapshot.self, from: data)
    }

    func save(_ value: WidgetControlSnapshot) {
        guard let data = try? encoder.encode(value) else { return }
        let encoded = data.base64EncodedString()
        for accessGroup in LuminaShared.keychainGroupCandidates {
            try? Keychain.write(encoded, key: Self.key, accessGroup: accessGroup)
        }
        defaults.set(data, forKey: Self.key)
        // Widget actions and timeline generation may run in different processes.
        // Force the tiny control snapshot to disk before asking WidgetKit to
        // rebuild the timeline, otherwise a reload can observe the old value.
        defaults.synchronize()
    }
}

private enum SharedSecretStore {
    static func read(_ key: String) -> String {
        switch LuminaShared.secretStorageRoute {
        case .sharedProtectedFile:
            let shared = ProtectedAppGroupSecrets.read(key)
            return shared.isEmpty ? Keychain.read(key, accessGroup: nil) : shared
        case .appPrivateKeychain:
            return Keychain.read(key, accessGroup: nil)
        case .configuredKeychain:
            return Keychain.read(key)
        }
    }

    static func write(_ value: String, key: String) throws {
        switch LuminaShared.secretStorageRoute {
        case .sharedProtectedFile:
            try ProtectedAppGroupSecrets.write(value, key: key)
        case .appPrivateKeychain:
            try Keychain.write(value, key: key, accessGroup: nil)
        case .configuredKeychain:
            try Keychain.write(value, key: key)
        }
    }
}

private enum ProtectedAppGroupSecrets {
    enum Error: Swift.Error { case appGroupUnavailable }

    private struct Payload: Codable {
        var values: [String: String] = [:]
    }

    static func read(_ key: String) -> String {
        guard let url = try? fileURL(),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return ""
        }
        return payload.values[key] ?? ""
    }

    static func write(_ value: String, key: String) throws {
        let url = try fileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var payload = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) } ?? Payload()
        if value.isEmpty {
            payload.values.removeValue(forKey: key)
        } else {
            payload.values[key] = value
        }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var protectedURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try protectedURL.setResourceValues(resourceValues)
    }

    private static func fileURL() throws -> URL {
        guard let container = LuminaShared.appGroupContainerURL else {
            throw Error.appGroupUnavailable
        }
        return container
            .appendingPathComponent("Library/Application Support/Lumina", isDirectory: true)
            .appendingPathComponent("secrets.json", isDirectory: false)
    }
}

enum Keychain {
    enum Error: Swift.Error { case unhandled(OSStatus) }

    static func read(_ key: String, accessGroup: String? = LuminaShared.keychainGroup) -> String {
        var query = baseQuery(key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func write(
        _ value: String,
        key: String,
        accessGroup: String? = LuminaShared.keychainGroup
    ) throws {
        let query = baseQuery(key, accessGroup: accessGroup)
        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Error.unhandled(addStatus) }
        } else if status != errSecSuccess {
            throw Error.unhandled(status)
        }
    }

    private static func baseQuery(_ key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.sigo.lumina.credentials",
            kSecAttrAccount as String: key,
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
