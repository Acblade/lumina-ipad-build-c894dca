import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum APIError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "Hub 地址必须以 http:// 或 https:// 开头"
        case .invalidResponse: "Hub 返回了无效响应"
        case let .server(status, message): "\(message)（HTTP \(status)）"
        case let .decoding(message): "无法读取 Hub 数据：\(message)"
        }
    }
}

enum HubEvent: Sendable {
    case connected
    case deviceChanged(Device)
    case sceneChanged(Scene)
    case runChanged(RunInfo)
}

struct SceneCommandResult: Sendable {
    let run: RunInfo
    let devices: [Device]
}

actor LuminaAPIClient {
    static let shared = LuminaAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var localFailedAt: [String: Date] = [:]
    private var localHealthyUntil: [String: Date] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    func health(_ connection: HubConnection) async throws {
        _ = try await request(connection, path: "/api/v1/health")
    }

    func devices(_ connection: HubConnection) async throws -> [Device] {
        try decodeList(try await request(connection, path: "/api/v1/devices"), key: "devices")
    }

    func modes(_ connection: HubConnection) async throws -> [LightMode] {
        try decodeList(try await request(connection, path: "/api/v1/modes"), key: "modes")
    }

    func scenes(_ connection: HubConnection) async throws -> [Scene] {
        try decodeList(try await request(connection, path: "/api/v1/scenes"), key: "scenes")
    }

    func runs(_ connection: HubConnection) async throws -> [RunInfo] {
        try decodeList(try await request(connection, path: "/api/v1/runs"), key: "runs")
    }

    func discover(_ connection: HubConnection) async throws {
        _ = try await request(connection, path: "/api/v1/discovery", method: "POST", body: EmptyBody())
    }

    func control(
        _ connection: HubConnection,
        deviceID: String,
        action: DeviceControlRequest
    ) async throws -> Device {
        try decodeObject(try await request(
            connection,
            path: "/api/v1/devices/\(pathComponent(deviceID))/control",
            method: "POST",
            body: action
        ), key: "device")
    }

    func controlMany(
        _ connection: HubConnection,
        deviceID: String,
        actions: [DeviceControlRequest]
    ) async throws -> Device {
        try decodeObject(try await request(
            connection,
            path: "/api/v1/devices/\(pathComponent(deviceID))/control-many",
            method: "POST",
            body: ActionList(actions: actions)
        ), key: "device")
    }

    func patch(_ connection: HubConnection, deviceID: String, patch: DevicePatch) async throws {
        _ = try await request(
            connection,
            path: "/api/v1/devices/\(pathComponent(deviceID))",
            method: "PATCH",
            body: patch
        )
    }

    func applyMode(_ connection: HubConnection, modeID: String, request body: ApplyModeRequest) async throws {
        let data = try await request(
            connection,
            path: "/api/v1/modes/\(pathComponent(modeID))/apply",
            method: "POST",
            body: body
        )
        let object = try jsonObject(from: unwrap(data))
        let failures = (object["results"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            guard item["status"] as? String == "failed" else { return nil }
            return item["error"] as? String ?? "模式应用失败"
        }
        if !failures.isEmpty { throw APIError.server(status: 502, message: failures.joined(separator: "；")) }
    }

    func createScene(_ connection: HubConnection, scene: Scene) async throws -> Scene {
        let data = try await request(connection, path: "/api/v1/scenes", method: "POST", body: scene.normalized)
        return try decodeObject(data, key: "scene")
    }

    func updateScene(_ connection: HubConnection, scene: Scene) async throws -> Scene {
        let data = try await request(
            connection,
            path: "/api/v1/scenes/\(pathComponent(scene.id))",
            method: "PUT",
            body: scene.normalized
        )
        return try decodeObject(data, key: "scene")
    }

    func deleteScene(_ connection: HubConnection, sceneID: String) async throws {
        _ = try await request(
            connection,
            path: "/api/v1/scenes/\(pathComponent(sceneID))",
            method: "DELETE"
        )
    }

    func runScene(_ connection: HubConnection, sceneID: String) async throws -> RunInfo {
        try await runSceneWithReadBack(connection, sceneID: sceneID).run
    }

    func runSceneWithReadBack(_ connection: HubConnection, sceneID: String) async throws -> SceneCommandResult {
        let data = try await request(
            connection,
            path: "/api/v1/scenes/\(pathComponent(sceneID))/run",
            method: "POST",
            body: EmptyBody()
        )
        return try decodeSceneCommand(data)
    }

    func stopRun(_ connection: HubConnection, runID: String) async throws {
        _ = try await stopRunWithReadBack(connection, runID: runID)
    }

    func stopRunWithReadBack(_ connection: HubConnection, runID: String) async throws -> SceneCommandResult {
        let data = try await request(
            connection,
            path: "/api/v1/runs/\(pathComponent(runID))/stop",
            method: "POST",
            body: EmptyBody()
        )
        return try decodeSceneCommand(data)
    }

    func events(_ connection: HubConnection) -> AsyncThrowingStream<HubEvent, Error> {
        let connection = connection.normalized
        let local = connection.effectiveLocalBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return AsyncThrowingStream { continuation in
            guard !local.isEmpty, !local.localizedCaseInsensitiveContains(".workers.dev"),
                  let url = URL(string: local + "/api/v1/events") else {
                continuation.finish(throwing: APIError.invalidBaseURL)
                return
            }
#if canImport(Darwin)
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                await self.consumeEventStream(
                    connection: connection,
                    local: local,
                    url: url,
                    continuation: continuation
                )
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
#else
            continuation.finish(throwing: APIError.invalidResponse)
#endif
        }
    }

#if canImport(Darwin)
    private func consumeEventStream(
        connection: HubConnection,
        local: String,
        url: URL,
        continuation: AsyncThrowingStream<HubEvent, Error>.Continuation
    ) async {
        do {
            var request = directURLRequest(connection, url: url, method: "GET", encodedBody: nil)
            request.timeoutInterval = 60 * 60
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard 200..<300 ~= http.statusCode else {
                throw APIError.server(status: http.statusCode, message: "Hub 事件流连接失败")
            }
            markLocalSuccess(local)
            continuation.yield(.connected)
            var eventType: String?
            for try await line in bytes.lines {
                try Task.checkCancellation()
                if line.hasPrefix("event:") {
                    eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let event = try parseEvent(type: eventType, payload: payload) {
                        continuation.yield(event)
                    }
                } else if line.isEmpty {
                    eventType = nil
                }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            markLocalFailure(local)
            continuation.finish(throwing: error)
        }
    }
#endif

    private func request(
        _ connection: HubConnection,
        path: String,
        method: String = "GET"
    ) async throws -> Data {
        try await request(connection, path: path, method: method, encodedBody: nil)
    }

    private func request<Body: Encodable>(
        _ connection: HubConnection,
        path: String,
        method: String,
        body: Body
    ) async throws -> Data {
        try await request(connection, path: path, method: method, encodedBody: try encoder.encode(body))
    }

    private func request(
        _ connection: HubConnection,
        path: String,
        method: String,
        encodedBody: Data?
    ) async throws -> Data {
        let connection = connection.normalized
        let local = connection.effectiveLocalBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relay = connection.relayBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let canTryLocal = !local.isEmpty && (relay.isEmpty || shouldTryLocal(local))

        if canTryLocal {
            if !relay.isEmpty, method != "GET", !localIsKnownHealthy(local) {
                do {
                    _ = try await directRequest(connection, base: local, path: "/api/v1/health", method: "GET", encodedBody: nil)
                    markLocalSuccess(local)
                } catch {
                    guard isTransportFailure(error) else { throw error }
                    markLocalFailure(local)
                    return try await relayRequest(connection, base: relay, path: path, method: method, encodedBody: encodedBody)
                }
            }
            do {
                let data = try await directRequest(connection, base: local, path: path, method: method, encodedBody: encodedBody)
                markLocalSuccess(local)
                return data
            } catch {
                guard !relay.isEmpty, method == "GET", isTransportFailure(error) else { throw error }
                markLocalFailure(local)
            }
        }

        if !relay.isEmpty {
            return try await relayRequest(connection, base: relay, path: path, method: method, encodedBody: encodedBody)
        }
        guard !local.isEmpty else { throw APIError.invalidBaseURL }
        return try await directRequest(connection, base: local, path: path, method: method, encodedBody: encodedBody)
    }

    private func directRequest(
        _ connection: HubConnection,
        base: String,
        path: String,
        method: String,
        encodedBody: Data?
    ) async throws -> Data {
        guard !base.localizedCaseInsensitiveContains(".workers.dev"),
              (base.hasPrefix("http://") || base.hasPrefix("https://")),
              let url = URL(string: base + path) else { throw APIError.invalidBaseURL }

        let request = directURLRequest(connection, url: url, method: method, encodedBody: encodedBody)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw APIError.server(status: http.statusCode, message: errorMessage(data) ?? "Hub 请求失败")
        }
        return data
    }

    private func directURLRequest(
        _ connection: HubConnection,
        url: URL,
        method: String,
        encodedBody: Data?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !connection.bearerToken.isEmpty {
            request.setValue("Bearer \(connection.bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if !connection.cloudflareClientID.isEmpty {
            request.setValue(connection.cloudflareClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        }
        if !connection.cloudflareClientSecret.isEmpty {
            request.setValue(connection.cloudflareClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        if let encodedBody {
            request.httpBody = encodedBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func relayRequest(_ connection: HubConnection, base: String, path: String, method: String, encodedBody: Data?) async throws -> Data {
        guard base.hasPrefix("https://"), !connection.bearerToken.isEmpty,
              !connection.cloudflareClientID.isEmpty, !connection.cloudflareClientSecret.isEmpty else { throw APIError.invalidBaseURL }
        let id = UUID().uuidString.lowercased()
        let payload = RelayPayload(method: method, path: path, body: encodedBody.flatMap { String(data: $0, encoding: .utf8) })
        let plain = try encoder.encode(payload)
        let envelope = try relayEncrypt(id: id, plaintext: plain, token: connection.bearerToken, direction: "request")
        var submit = URLRequest(url: URL(string: base + "/v1/relay/requests")!)
        submit.httpMethod = "POST"; submit.httpBody = try encoder.encode(envelope)
        submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        relayHeaders(&submit, connection)
        let (_, submitted) = try await session.data(for: submit)
        guard let submittedHTTP = submitted as? HTTPURLResponse, 200..<300 ~= submittedHTTP.statusCode else { throw APIError.server(status: 502, message: "Relay 未接受请求") }
        for _ in 0..<3 {
            var poll = URLRequest(url: URL(string: base + "/v1/relay/responses/\(id)?wait_ms=12000")!)
            poll.httpMethod = "GET"; relayHeaders(&poll, connection)
            let (data, response) = try await session.data(for: poll)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if http.statusCode == 204 { continue }
            guard 200..<300 ~= http.statusCode else { throw APIError.server(status: http.statusCode, message: "Relay 请求失败") }
            let outer = try decoder.decode(RelayOuterResponse.self, from: data)
            guard let inner = outer.response else { throw APIError.invalidResponse }
            let decoded = try decoder.decode(RelayResult.self, from: relayDecrypt(inner, token: connection.bearerToken, direction: "response"))
            guard 200..<300 ~= decoded.status else { throw APIError.server(status: decoded.status, message: errorMessage(Data(decoded.body.utf8)) ?? "Hub 请求失败") }
            return Data(decoded.body.utf8)
        }
        throw APIError.server(status: 504, message: "远程 Hub 在 36 秒内没有回应")
    }

    private func relayHeaders(_ request: inout URLRequest, _ connection: HubConnection) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(connection.cloudflareClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(connection.cloudflareClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
    }

    private func relayEncrypt(id: String, plaintext: Data, token: String, direction: String) throws -> RelayEnvelope {
        let key = SymmetricKey(data: SHA256.hash(data: Data(token.utf8)))
        let nonce = AES.GCM.Nonce(); let aad = Data("LUMINA-RELAY/1\n\(id)\n\(direction)".utf8)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        return RelayEnvelope(id: id, nonce: Data(nonce).base64URLEncodedString(), ciphertext: box.ciphertext.base64URLEncodedString(), tag: box.tag.base64URLEncodedString())
    }

    private func relayDecrypt(_ envelope: RelayEnvelope, token: String, direction: String) throws -> Data {
        let key = SymmetricKey(data: SHA256.hash(data: Data(token.utf8)))
        guard let nonceData = Data(base64URLEncoded: envelope.nonce), let ciphertext = Data(base64URLEncoded: envelope.ciphertext), let tag = Data(base64URLEncoded: envelope.tag) else { throw APIError.invalidResponse }
        let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonceData), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: key, authenticating: Data("LUMINA-RELAY/1\n\(envelope.id)\n\(direction)".utf8))
    }

    private func decodeList<T: Decodable>(_ data: Data, key: String) throws -> [T] {
        do {
            let payload = try unwrap(data)
            if let array = payload as? [Any] {
                return try decoder.decode([T].self, from: JSONSerialization.data(withJSONObject: array))
            }
            if let object = payload as? [String: Any], let array = object[key] {
                return try decoder.decode([T].self, from: JSONSerialization.data(withJSONObject: array))
            }
            throw APIError.invalidResponse
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func decodeObject<T: Decodable>(_ data: Data, key: String) throws -> T {
        do {
            let payload = try unwrap(data)
            let value = (payload as? [String: Any])?[key] ?? payload
            return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value))
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func decodeSceneCommand(_ data: Data) throws -> SceneCommandResult {
        do {
            let payload = try unwrap(data)
            if let object = payload as? [String: Any], let runValue = object["run"] {
                let run = try decoder.decode(RunInfo.self, from: JSONSerialization.data(withJSONObject: runValue))
                let devices = try object["devices"].map {
                    try decoder.decode([Device].self, from: JSONSerialization.data(withJSONObject: $0))
                } ?? []
                return .init(run: run, devices: devices)
            }
            let run = try decoder.decode(RunInfo.self, from: JSONSerialization.data(withJSONObject: payload))
            return .init(run: run, devices: [])
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func parseEvent(type: String?, payload: String) throws -> HubEvent? {
        let data = Data(payload.utf8)
        switch type {
        case "device": return .deviceChanged(try decoder.decode(Device.self, from: data))
        case "scene": return .sceneChanged(try decoder.decode(Scene.self, from: data))
        case "run": return .runChanged(try decoder.decode(RunInfo.self, from: data))
        default: return nil
        }
    }

    private func shouldTryLocal(_ base: String) -> Bool {
        guard let failedAt = localFailedAt[base] else { return true }
        return Date().timeIntervalSince(failedAt) >= 30
    }

    private func localIsKnownHealthy(_ base: String) -> Bool {
        (localHealthyUntil[base] ?? .distantPast) > Date()
    }

    private func markLocalSuccess(_ base: String) {
        localFailedAt.removeValue(forKey: base)
        localHealthyUntil[base] = Date().addingTimeInterval(30)
    }

    private func markLocalFailure(_ base: String) {
        localHealthyUntil.removeValue(forKey: base)
        localFailedAt[base] = Date()
    }

    private func isTransportFailure(_ error: Error) -> Bool {
        error is URLError || (error as NSError).domain == NSURLErrorDomain
    }

    private func unwrap(_ data: Data) throws -> Any {
        let root = try JSONSerialization.jsonObject(with: data)
        if let object = root as? [String: Any], let data = object["data"] { return data }
        return root
    }

    private func jsonObject(from value: Any) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw APIError.invalidResponse }
        return object
    }

    private func errorMessage(_ data: Data) -> String? {
        guard let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) else { return nil }
        let summary = envelope.error.message
        let details = envelope.error.details ?? []
        let detailText = details.joined(separator: "；")
        return details.isEmpty ? summary : "\(summary)：\(detailText)"
    }

    private func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct RelayPayload: Codable { let method: String; let path: String; let body: String? }
private struct RelayEnvelope: Codable { let id: String; let nonce: String; let ciphertext: String; let tag: String }
private struct RelayOuterResponse: Codable { let response: RelayEnvelope? }
private struct RelayResult: Codable { let status: Int; let body: String }
private extension Data {
    init?(base64URLEncoded value: String) { var text = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); text += String(repeating: "=", count: (4 - text.count % 4) % 4); self.init(base64Encoded: text) }
    func base64URLEncodedString() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

private struct EmptyBody: Codable {}
private struct ActionList: Codable { let actions: [DeviceControlRequest] }
private struct ErrorEnvelope: Decodable { let error: ErrorPayload }
private struct ErrorPayload: Decodable {
    let message: String
    let details: [String]?
}
