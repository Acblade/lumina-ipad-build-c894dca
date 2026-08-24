import XCTest
#if canImport(LuminaPad)
@testable import LuminaPad
#else
@testable import LuminaCore
#endif

final class ModelsTests: XCTestCase {
    func testDeviceAcceptsVendorKeyAndCapabilityState() throws {
        let data = Data(#"""
        {
          "id":"wiz:kitchen",
          "name":"厨房",
          "vendor":"wiz",
          "online":true,
          "capabilities":{
            "zones":[{
              "id":"main","label":"主灯","power":true,
              "brightness":{"min":1,"max":100,"reportedMin":10},
              "colorTemperature":{"min":2200,"max":6500},
              "rgb":true,"whiteChannels":true
            }],
            "nativeScenes":[],"supportsRatio":false
          },
          "state":{"zones":{"main":{"power":true,"brightness":10,"rgb":{"r":1,"g":2,"b":3}}}}
        }
        """#.utf8)

        let device = try JSONDecoder().decode(Device.self, from: data)
        XCTAssertEqual(device.vendor, "wiz")
        XCTAssertEqual(device.capabilities.zones[0].brightness?.reportedMin, 10)
        XCTAssertEqual(device.zoneState("main").rgb?.hex, "#010203")
    }

    func testSceneNormalizationSortsFramesAndInfersDuration() throws {
        let scene = Scene(
            name: "  睡眠  ",
            tracks: [
                SceneTrack(
                    deviceId: "yeelight:screen",
                    zone: "main",
                    keyframes: [
                        .init(offsetMs: 60_000, brightness: 1),
                        .init(offsetMs: 0, power: true, brightness: 40),
                    ]
                )
            ]
        ).normalized

        XCTAssertEqual(scene.name, "睡眠")
        XCTAssertEqual(scene.durationMs, 60_000)
        XCTAssertEqual(scene.tracks[0].keyframes.map(\.offsetMs), [0, 60_000])

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scene)) as? [String: Any]
        let tracks = json?["tracks"] as? [[String: Any]]
        XCTAssertEqual(tracks?[0]["repeat"] as? Bool, false)
        XCTAssertNil(tracks?[0]["repeatTrack"])
    }

    func testRGBHexRoundTripAndClamp() {
        XCTAssertEqual(RGBColor(hex: "#F2B84B"), RGBColor(r: 242, g: 184, b: 75))
        XCTAssertEqual(RGBColor(r: -4, g: 300, b: 12).hex, "#00FF0C")
        XCTAssertNil(RGBColor(hex: "bad"))
    }

#if canImport(LuminaPad)
    func testAppGroupCandidatesKeepCanonicalIdentifierAndTryXtoolFallback() {
        XCTAssertEqual(
            LuminaShared.appGroupCandidates(for: "com.sigo.lumina.ipad"),
            ["group.com.sigo.lumina"]
        )
        XCTAssertEqual(
            LuminaShared.appGroupCandidates(for: "XTL-1234ABCD.com.sigo.lumina.ipad"),
            ["group.com.sigo.lumina", "group.XTL-1234ABCD.com.sigo.lumina"]
        )
        XCTAssertEqual(
            LuminaShared.appGroupCandidates(for: "XTL-1234ABCD.com.sigo.lumina.ipad.widget"),
            ["group.com.sigo.lumina", "group.XTL-1234ABCD.com.sigo.lumina"]
        )
        XCTAssertTrue(LuminaShared.isXtoolProvisioned(bundleIdentifier: "XTL-1234ABCD.com.sigo.lumina.ipad"))
        XCTAssertFalse(LuminaShared.isXtoolProvisioned(bundleIdentifier: "com.sigo.lumina.ipad"))
        XCTAssertEqual(
            LuminaShared.keychainGroupCandidates(
                for: "XTL-1234ABCD.com.sigo.lumina.ipad",
                configuredGroup: "com.sigo.lumina.shared"
            ),
            ["1234ABCD.com.sigo.lumina.shared", "com.sigo.lumina.shared"]
        )
        XCTAssertEqual(
            LuminaShared.keychainGroupCandidates(
                for: "XTL-1234ABCD.com.sigo.lumina.ipad.widget",
                configuredGroup: nil
            ),
            ["1234ABCD.com.sigo.lumina.shared"]
        )
        XCTAssertEqual(
            LuminaShared.keychainGroupCandidates(
                for: "com.sigo.lumina.ipad",
                configuredGroup: "TEAMID.com.sigo.lumina.shared"
            ),
            ["TEAMID.com.sigo.lumina.shared"]
        )
        XCTAssertEqual(
            LuminaShared.secretStorageRoute(usesXtoolProvisioning: true, hasSharedContainer: false),
            .appPrivateKeychain
        )
        XCTAssertEqual(
            LuminaShared.secretStorageRoute(usesXtoolProvisioning: true, hasSharedContainer: true),
            .sharedProtectedFile
        )
        XCTAssertEqual(
            LuminaShared.secretStorageRoute(usesXtoolProvisioning: false, hasSharedContainer: false),
            .configuredKeychain
        )
    }
#endif
}
