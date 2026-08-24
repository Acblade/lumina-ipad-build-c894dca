import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { test } from "node:test";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const ipad = path.join(root, "ipad");
const read = (relative) => readFile(path.join(root, relative), "utf8");

const expectedClientRoutes = [
  "/api/v1/health",
  "/api/v1/devices",
  "/api/v1/modes",
  "/api/v1/scenes",
  "/api/v1/runs",
  "/api/v1/discovery",
  "/control",
  "/control-many",
  "/apply",
  "/run",
  "/stop"
];

test("iPad client covers every Hub API family it claims", async () => {
  const [client, server] = await Promise.all([
    read("ipad/LuminaShared/APIClient.swift"),
    read("hub/src/server.js")
  ]);
  for (const route of expectedClientRoutes) {
    assert.ok(client.includes(route), `Swift client is missing ${route}`);
  }
  for (const route of ["/api/v1/health", "/api/v1/devices", "/api/v1/modes", "/api/v1/scenes", "/api/v1/runs", "/api/v1/discovery"]) {
    assert.ok(server.includes(route), `Hub no longer exposes ${route}`);
  }
  assert.match(client, /CF-Access-Client-Id/);
  assert.match(client, /CF-Access-Client-Secret/);
  assert.match(client, /Authorization/);
});

test("portable Swift package declares the async URLSession deployment floor", async () => {
  const packageManifest = await read("ipad/Package.swift");
  assert.match(packageManifest, /\.macOS\(\.v12\)/);
  assert.match(packageManifest, /\.iOS\(\.v17\)/);
});

test("SwiftUI app entry is not shadowed by the lighting Scene model", async () => {
  const appEntry = await read("ipad/LuminaPad/LuminaPadApp.swift");
  assert.match(appEntry, /var body: some SwiftUI\.Scene/);
});

test("scene cards resolve their stored color before applying a gradient", async () => {
  const scenesView = await read("ipad/LuminaPad/ScenesView.swift");
  assert.match(scenesView, /colors: \[sceneColor\(scene\.color\)\.opacity\(0\.72\), sceneColor\(scene\.color\)\]/);
  assert.doesNotMatch(scenesView, /sceneColor\.gradient/);
});

test("second-round iPad UI keeps the accepted Android interactions and removes rejected chrome", async () => {
  const [dashboard, detail, modes, rootView, settings, scenes, widget, widgetActions, appModel, sceneMark] = await Promise.all([
    read("ipad/LuminaPad/DashboardView.swift"),
    read("ipad/LuminaPad/DeviceDetailView.swift"),
    read("ipad/LuminaPad/ModesView.swift"),
    read("ipad/LuminaPad/RootView.swift"),
    read("ipad/LuminaPad/SettingsView.swift"),
    read("ipad/LuminaPad/ScenesView.swift"),
    read("ipad/LuminaWidget/LuminaWidget.swift"),
    read("ipad/LuminaShared/WidgetActions.swift"),
    read("ipad/LuminaPad/AppModel.swift"),
    read("ipad/LuminaShared/SceneMark.swift")
  ]);

  assert.match(dashboard, /LuminaPageHeader\("灯光"\)/);
  assert.match(dashboard, /LuminaPillSlider/);
  assert.match(dashboard, /LuminaSlidingPowerSwitch/);
  assert.match(dashboard, /DragGesture\(minimumDistance: 7\)/);
  assert.match(dashboard, /DeviceDetailView\(deviceID: zone\.device\.id, zoneID: zone\.capability\.id\)/);
  assert.doesNotMatch(dashboard, /直接控制每一个光源|总亮度与总开关|台设备在线|个光源|Divider\(\)/);
  assert.match(appModel, /setAllBrightness[\s\S]*power: true/);

  assert.doesNotMatch(rootView, /Hub 在线|使用缓存/);
  assert.match(detail, /LuminaColorField/);
  assert.match(detail, /frame\(height: 260\)/);
  assert.match(detail, /mappedKelvin/);
  assert.match(detail, /mapsTemperatureToRGB/);
  assert.match(detail, /capability\.rgb \|\| capability\.colorTemperature != nil[\s\S]*colorSection[\s\S]*capability\.segmentRgb[\s\S]*segmentSection/);
  assert.match(detail, /ControlLabel\("左右分区"/);
  assert.match(detail, /segmentRgb: \.init\(left: leftRGB, right: rightRGB\)/);
  assert.match(detail, /SegmentHexApplyField/);
  assert.doesNotMatch(detail, /运行时能力|设备原生效果|冷暖白通道|Text\("Home"\)/);

  assert.match(modes, /LongPressGesture/);
  assert.match(modes, /ModeApplyView/);
  assert.match(modes, /luminaModeSymbol/);
  assert.doesNotMatch(modes, /WiZ 使用灯泡原生模式/);
  assert.doesNotMatch(settings, /配置桌面场景面板/);
  assert.match(scenes, /sceneID: scene\.id/);
  assert.match(scenes, /case "scene_concentrate": return "scope"/);
  assert.match(scenes, /Text\(scene\.icon/);

  assert.doesNotMatch(widget, /Text\("Lumina"\)|家庭 Hub/);
  assert.match(widget, /Button\(intent: ToggleAllPowerIntent\(\)\)/);
  assert.match(widget, /Label\("开关", systemImage: "power"\)/);
  assert.match(widget, /family == \.systemSmall \|\| family == \.systemMedium/);
  assert.match(widget, /private var powerTile/);
  assert.match(widget, /SigoWidgetBackground/);
  assert.match(widget, /Color\(red: 214\.0 \/ 255\.0, green: 188\.0 \/ 255\.0, blue: 120\.0 \/ 255\.0\)/);
  assert.match(widget, /SigoWidgetTheme\.gold/);
  assert.match(widget, /case "scene_concentrate": return "scope"/);
  assert.doesNotMatch(widgetActions, /SetAllPowerIntent|controlMany/);
  assert.match(widgetActions, /let shouldTurnOn = !devices\.contains/);
  assert.match(widgetActions, /power: shouldTurnOn/);
  assert.match(widget, /scene_true_colors/);
  assert.match(widget, /scene_daylight/);
  assert.match(widget, /name: "日光", icon: "sun\.max\.fill", color: "#65AEE8"/);
  assert.match(sceneMark, /case "scene_daylight"/);
  assert.match(appModel, /Task\.sleep\(for: \.seconds\(3\)\)/);
  assert.match(dashboard, /DashboardZoneOrder\.save/);
  assert.match(dashboard, /DashboardZoneDropDelegate/);
  assert.match(dashboard, /\.onDrag/);
  assert.match(dashboard, /\.onDrop/);
});

test("Darwin URLProtocol tests accept streamed request bodies", async () => {
  const appModelTests = await read("ipad/LuminaPadTests/AppModelTests.swift");
  assert.match(appModelTests, /request\.httpBodyStream/);
  assert.match(appModelTests, /requestBody\(request\)/);
});

test("all Swift sources and required resources belong to the Xcode project", async () => {
  const project = await read("ipad/LuminaPad.xcodeproj/project.pbxproj");
  for (const directory of ["LuminaPad", "LuminaShared", "LuminaWidget", "LuminaPadTests"]) {
    for (const file of await readdir(path.join(ipad, directory))) {
      if (file.endsWith(".swift")) {
        assert.ok(project.includes(`/* ${file} */`), `${directory}/${file} is not referenced by Xcode`);
      }
    }
  }
  for (const resource of ["Assets.xcassets", "PrivacyInfo.xcprivacy", "LuminaPad.entitlements", "LuminaWidget.entitlements"]) {
    assert.ok(project.includes(resource), `${resource} is not referenced by Xcode`);
  }
  assert.match(project, /LuminaWidget\.appex in Embed App Extensions/);
  assert.match(project, /TARGETED_DEVICE_FAMILY = 2/);
  assert.match(project, /IPHONEOS_DEPLOYMENT_TARGET = 17\.0/);
  assert.match(project, /ENABLE_TESTABILITY = YES/);
});

test("widget configuration stays within the iPadOS 17 API surface", async () => {
  const widget = await read("ipad/LuminaWidget/LuminaWidget.swift");
  assert.doesNotMatch(widget, /@Parameter\([^\n]*size:/, "collection-sized parameters require iPadOS 18");
  for (let slot = 1; slot <= 8; slot += 1) {
    assert.match(widget, new RegExp(`var scene${slot}: SceneEntity\\?`));
  }
  assert.match(widget, /var selectedScenes: \[SceneEntity\]/);
});

test("privacy, local network, App Group, and Keychain declarations agree", async () => {
  const [appInfo, widgetInfo, appEntitlements, widgetEntitlements, shared] = await Promise.all([
    read("ipad/LuminaPad/Info.plist"),
    read("ipad/LuminaWidget/Info.plist"),
    read("ipad/LuminaPad/LuminaPad.entitlements"),
    read("ipad/LuminaWidget/LuminaWidget.entitlements"),
    read("ipad/LuminaShared/SharedStore.swift")
  ]);
  for (const plist of [appInfo, widgetInfo]) {
    assert.match(plist, /NSLocalNetworkUsageDescription/);
    assert.match(plist, /NSAllowsLocalNetworking/);
    assert.match(plist, /\$\(AppIdentifierPrefix\)com\.sigo\.lumina\.shared/);
  }
  assert.match(appInfo, /ITSAppUsesNonExemptEncryption/);
  assert.match(appInfo, /<string>lumina<\/string>/);
  for (const entitlements of [appEntitlements, widgetEntitlements]) {
    assert.match(entitlements, /group\.com\.sigo\.lumina/);
    assert.match(entitlements, /keychain-access-groups/);
  }
  assert.match(shared, /kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly/);
  assert.doesNotMatch(shared, /defaults\.set\(connection\.bearerToken/);
  assert.doesNotMatch(shared, /defaults\.string\(forKey: Key\.bearerToken/);
  const privacy = await read("ipad/LuminaPad/PrivacyInfo.xcprivacy");
  assert.match(privacy, /NSPrivacyAccessedAPICategoryUserDefaults/);
  assert.match(privacy, /1C8F\.1/);
});

test("app icon is a nontransparent 1024px PNG asset", async () => {
  const icon = await readFile(path.join(ipad, "LuminaPad", "Assets.xcassets", "AppIcon.appiconset", "LuminaIcon.png"));
  assert.deepEqual([...icon.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(icon.readUInt32BE(16), 1024);
  assert.equal(icon.readUInt32BE(20), 1024);
  assert.equal(icon[25], 2, "PNG must use truecolor without alpha");
});

test("source and documentation do not capture current private LAN snapshots or secrets", async () => {
  const files = [
    "ipad/LuminaShared/Models.swift",
    "ipad/LuminaShared/APIClient.swift",
    "ipad/LuminaShared/SharedStore.swift",
    "ipad/LuminaPad/AppModel.swift",
    "ipad/README.md"
  ];
  for (const file of files) {
    const contents = await read(file);
    assert.doesNotMatch(contents, /192\.168\.1\.\d+/);
    assert.doesNotMatch(contents, /CF-Access-Client-Secret:\s*\S+/);
    assert.doesNotMatch(contents, /Bearer\s+[A-Za-z0-9_-]{20,}/);
  }
});

test("macOS CI tests the simulator and compiles an unsigned iPad device artifact", async () => {
  const [workflow, verifier] = await Promise.all([
    read(".github/workflows/ipad-xcode.yml"),
    read("ipad/scripts/verify-apple.sh")
  ]);
  assert.match(workflow, /runs-on: macos-15/);
  assert.match(workflow, /DEVELOPER_DIR: \/Applications\/Xcode_16\.4\.app\/Contents\/Developer/);
  assert.match(workflow, /bash ipad\/scripts\/verify-apple\.sh/);
  assert.match(workflow, /path: \|[\s\S]*artifacts\//);
  assert.match(workflow, /!artifacts\/DerivedData\/\*\*/);
  assert.match(workflow, /!artifacts\/DeviceDerivedData\/\*\*/);
  assert.match(verifier, /xcrun simctl list devices available -j/);
  assert.match(verifier, /-project ipad\/LuminaPad\.xcodeproj/);
  assert.match(verifier, /-scheme LuminaPad/);
  assert.match(verifier, /CODE_SIGNING_ALLOWED=NO/);
  assert.match(verifier, /clean test \| tee "\$evidence_dir\/xcodebuild\.log"/);
  assert.match(verifier, /-destination 'generic\/platform=iOS'/);
  assert.match(verifier, /xcodebuild-device\.log/);
  assert.match(verifier, /LuminaPad-unsigned\.ipa/);
  assert.match(verifier, /device-binary-uuid\.txt/);
  assert.match(verifier, /LuminaPad\.xcresult/);
  assert.match(verifier, /SOURCE_SHA256\.txt/);
});

test("physical installer rejects incomplete signing and records launch evidence", async () => {
  const installer = await read("ipad/scripts/install-signed-device.ps1");
  assert.match(installer, /SupportsShouldProcess/);
  assert.match(installer, /ConfirmImpact = 'High'/);
  assert.match(installer, /DeveloperModeEnabled/);
  assert.match(installer, /MainAppSignature/);
  assert.match(installer, /MainAppProfile/);
  assert.match(installer, /WidgetSignature/);
  assert.match(installer, /WidgetProfile/);
  assert.match(installer, /Get-FileHash -Algorithm SHA256/);
  assert.match(installer, /'install'/);
  assert.match(installer, /'launch'/);
  assert.match(installer, /'screenshot'/);
  assert.match(installer, /lumina-first-launch\.png/);
});

test("xtool installer keeps the USB relay private and verifies the unsigned artifact", async () => {
  const [installer, relay] = await Promise.all([
    read("ipad/scripts/install-unsigned-with-xtool.ps1"),
    read("ipad/scripts/usbmux-relay.mjs")
  ]);
  assert.match(installer, /SupportsShouldProcess/);
  assert.match(installer, /ConfirmImpact = 'High'/);
  assert.match(installer, /ExpectedIpaSha256/);
  assert.match(installer, /ExpectedXtoolVersion = '1\.17\.0'/);
  assert.match(installer, /7566d62b829a4deadb01b5389c94f45763d851f204c5d22fa36e9f9d1c88d57b/);
  assert.match(installer, /sha256sum/);
  assert.match(installer, /DeveloperModeEnabled/);
  assert.match(installer, /auth', 'status/);
  assert.match(installer, /USBMUXD_SOCKET_ADDRESS=/);
  assert.match(installer, /LuminaWidget\\\.appex/);
  assert.match(installer, /'install', '--udid'/);
  assert.match(installer, /\$Live/);
  assert.match(installer, /ConvertTo-WslPath/);
  assert.match(installer, /command -v zip/);
  assert.match(installer, /installedBundleIdentifier/);
  assert.match(installer, /lumina-first-launch\.png/);
  assert.match(installer, /install-result\.json/);
  assert.match(installer, /VPN & Device Management/);
  assert.match(installer, /-WorkingDirectory \$evidencePath/);
  assert.match(installer, /selfIdentity\.plist/);
  assert.match(installer, /\\\.xctest/);
  assert.match(relay, /server\.listen\(port, listenAddress/);
  assert.match(relay, /host: "127\.0\.0\.1"/);
  assert.doesNotMatch(relay, /0\.0\.0\.0/);
});

test("free signing falls back safely when App Group containers are unavailable", async () => {
  const [store, widget, actions, app, project, scheme, verifier] = await Promise.all([
    read("ipad/LuminaShared/SharedStore.swift"),
    read("ipad/LuminaWidget/LuminaWidget.swift"),
    read("ipad/LuminaShared/WidgetActions.swift"),
    read("ipad/LuminaPad/LuminaPadApp.swift"),
    read("ipad/LuminaPad.xcodeproj/project.pbxproj"),
    read("ipad/LuminaPad.xcodeproj/xcshareddata/xcschemes/LuminaPad.xcscheme"),
    read("ipad/scripts/verify-apple.sh")
  ]);
  assert.match(store, /provisioningPrefix\.hasPrefix\("XTL-"\)/);
  assert.match(store, /group\.\\\(provisioningPrefix\)\\\(canonicalBundleRoot\)/);
  assert.match(store, /case appPrivateKeychain/);
  assert.match(store, /hasSharedContainer \? \.sharedProtectedFile : \.appPrivateKeychain/);
  assert.match(store, /Keychain\.write\(value, key: key, accessGroup: nil\)/);
  assert.match(store, /return \.standard/);
  assert.match(store, /completeFileProtectionUntilFirstUserAuthentication/);
  assert.match(store, /isExcludedFromBackup = true/);
  assert.match(widget, /Button\(intent: RunSceneIntent\(sceneID: scene\.id\)\)/);
  assert.doesNotMatch(widget, /Link\(destination:/);
  assert.match(actions, /struct RunSceneIntent: LiveActivityIntent/);
  assert.match(actions, /static var openAppWhenRun = false/);
  assert.match(actions, /SharedSettings\(\)\.loadConnection\(\)/);
  assert.equal((project.match(/WidgetActions\.swift in Sources/g) ?? []).length, 2);
  assert.match(project, /S00100000000000000000001[^\n]+B0010000000000000000001A/);
  assert.match(project, /S00100000000000000000002[^\n]+B0010000000000000000001B/);
  assert.match(app, /model\.handleDeepLink\(url\)/);
  assert.match(scheme, /BuildActionEntry[^>]*buildForRunning="NO"[^>]*>[\s\S]{0,500}BlueprintName="LuminaPadTests"/);
  assert.match(verifier, /Refusing to package a device app containing test bundles or test frameworks/);
});

test("pairing QR requires in-app confirmation before saving secrets", async () => {
  const [app, model, root] = await Promise.all([
    read("ipad/LuminaPad/LuminaPadApp.swift"),
    read("ipad/LuminaPad/AppModel.swift"),
    read("ipad/LuminaPad/RootView.swift")
  ]);
  assert.match(app, /\.onOpenURL \{ url in/);
  assert.match(app, /model\.handleDeepLink\(url\)/);
  assert.match(model, /url\.scheme\?\.lowercased\(\) == "lumina"/);
  assert.match(model, /pendingPairing = PendingPairing/);
  assert.match(model, /confirmPendingPairing/);
  assert.match(model, /if await saveConnection\(pendingPairing\.connection\)/);
  assert.match(model, /await refreshAll\(silent: true\)/);
  assert.match(root, /连接并验证/);
  assert.match(root, /打开系统设置/);
  assert.match(root, /UIApplication\.openSettingsURLString/);
  assert.match(root, /model\.errorMessage != nil && model\.pendingPairing == nil/);
  assert.doesNotMatch(root, /bearerToken/);
});

test("build-only exporter excludes private project state and scans its payload", async () => {
  const [exporter, verifier] = await Promise.all([
    read("ipad/scripts/export-build-only.ps1"),
    read("ipad/scripts/verify-apple.sh")
  ]);
  assert.match(exporter, /git archive --format=zip/);
  assert.match(exporter, /HEAD ipad \.github\/workflows\/ipad-xcode\.yml/);
  assert.match(exporter, /PrivateLanSnapshot/);
  assert.match(exporter, /privacyScan = 'passed'/);
  assert.match(exporter, /'hub', 'android', 'cloudflare-relay', '\.codex'/);
  assert.match(exporter, /init -b codex\/ipad-public-build/);
  assert.match(verifier, /Hub source is absent; running the Apple-only public build gate/);
  assert.match(verifier, /if \[\[ "\$apple_only" == "0" \]\]/);
});
