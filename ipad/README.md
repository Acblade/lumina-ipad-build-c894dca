# Lumina for iPad

Native iPadOS 17+ client for the existing Lumina Hub. It is intentionally a client: device inventory, scene storage, weekly schedules, active runs, and restart recovery remain authoritative in the Hub.

## Implemented

- iPad-first `NavigationSplitView` with adaptive light, mode, scene, and settings pages.
- Runtime-capability-driven WiZ and Yeelight controls: power, brightness, CCT, RGB, native scene/speed, dual-zone ratio, white channels, and guarded experimental segment RGB.
- Whole-home power and brightness controls with optimistic UI and Hub read-back.
- Complete 37-mode catalog consumption with multi-zone target selection, brightness, and dynamic speed.
- Scene run/stop/create/update/delete.
- Absolute timeline editor with per-device/per-zone tracks, sorted keyframes, `linear`/`step` easing, and every state field accepted by Hub API v1.
- Weekly schedule editor using IANA time zones; the Hub remains the executor.
- Keychain-protected Hub bearer token and Cloudflare Access secret, plus shared non-secret cache when the provisioning profile supplies an App Group.
- Configurable interactive WidgetKit scene panel for small, medium, large, and extra-large iPad widgets.
- Local-network privacy purpose string, scoped local-network ATS allowance, privacy manifest, iPad-only orientations, and a 1024px app icon.
- XCTest coverage for device decoding, scene normalization/encoding, path escaping, headers, response envelopes, Hub errors, catalog refresh, optimistic control, and authoritative Hub read-back reconciliation.

## Open in Xcode

Requirements:

- macOS with current Xcode;
- an iPad running iPadOS 17 or later (simulator is sufficient for UI tests, not LAN/device acceptance);
- an Apple development team that owns `com.sigo.lumina.ipad`, `com.sigo.lumina.ipad.widget`, and the `group.com.sigo.lumina` App Group.

Open `LuminaPad.xcodeproj`, select the **LuminaPad** scheme, choose the development team for both app and widget targets, then run.

Command-line build and tests on a Mac:

```bash
xcodebuild -project LuminaPad.xcodeproj \
  -scheme LuminaPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  clean test
```

The exact simulator name depends on the installed Xcode runtime. For a compile-only check that does not require signing:

```bash
xcodebuild -project LuminaPad.xcodeproj \
  -scheme LuminaPad \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
```

The repository also includes `.github/workflows/ipad-xcode.yml`. After this project is committed to a GitHub repository, it selects an installed iPad simulator on `macos-15`, runs the portable Swift and Hub suites, executes the real Xcode tests, compiles the arm64 iPad target, and uploads `LuminaPad-unsigned.ipa` together with its SHA-256, binary UUID, `.xcresult`, and raw build logs. The IPA is deliberately unsigned and cannot be installed until it is signed for the target iPad and Apple development team. No workflow has been dispatched from this local repository because it currently has no remote.

The same Apple-platform gate can be run directly on any Mac with a current Xcode installation:

```bash
bash ipad/scripts/verify-apple.sh
```

It creates a timestamped evidence directory containing toolchain and simulator records, simulator and device build logs, the unsigned device IPA and hash, `.xcresult`, source SHA-256 ledger, and final status. Set `LUMINA_EVIDENCE_DIR` to choose another new output directory or `LUMINA_SIMULATOR_UDID` to require a specific available iPad simulator.

After the IPA has been signed for the target iPad, Windows can perform a guarded install with go-ios:

```powershell
pwsh -NoProfile -File .\scripts\install-signed-device.ps1 `
  -IpaPath C:\path\to\LuminaPad-signed.ipa `
  -Udid 00000000-0000000000000000 `
  -IosTool C:\path\to\ios.exe
```

The script has a high-impact confirmation prompt and refuses an IPA that lacks the main app or Widget provisioning profile and code-signature resources. It verifies the attached UDID and Developer Mode, records the IPA SHA-256, installs and launches Lumina, captures a first-launch screenshot, and stops only the userspace tunnel it started. The install itself is the authoritative signature check; the preflight checks package structure, not cryptographic validity.

On Windows with WSL, the unsigned Xcode artifact can instead be provisioned, signed, and installed in one guarded step with the open-source `xtool` 1.17.0 release:

```powershell
pwsh -NoProfile -File .\scripts\install-unsigned-with-xtool.ps1 `
  -IpaPath C:\path\to\LuminaPad-unsigned.ipa `
  -ExpectedIpaSha256 64_HEX_CHARACTERS `
  -Udid 00000000-0000000000000000 `
  -IosTool C:\path\to\ios.exe
```

Install WSL's `zip` and `unzip` packages, then authenticate in a private visible WSL terminal with `xtool auth login`; never pass Apple credentials on the command line or store them in project files. The installer pins xtool 1.17.0 and its published SHA-256, and refuses missing archive tools, an unexpected tool or IPA hash, test payload, missing main app or Widget, disabled Developer Mode, non-private WSL gateway, missing Apple Mobile Device service, or unauthenticated xtool. It starts an in-memory relay bound only to the private WSL gateway, signs the main app and Widget through Apple Developer Services, installs through USB, discovers xtool's account-specific bundle-ID prefix, launches the app, captures a screenshot, and stops only the relay and iOS tunnel it started. Lumina tries the canonical and xtool-prefixed App Group identifiers at runtime. When free provisioning supplies neither container, the main App safely falls back to its private Keychain and `UserDefaults`; Widget scene buttons then open the main App through a scoped `lumina://run-scene` deep link instead of attempting unavailable background sharing. When an App Group is available, the Widget continues to run scenes directly in the background and secrets use a file-protected, backup-excluded shared store. Regular Xcode signing continues to use Keychain. Free Apple Account profiles expire after seven days and must be refreshed periodically.

If private GitHub Actions is unavailable, `scripts/export-build-only.ps1` can create a separate minimal repository containing only the iPad project and its Xcode workflow. It excludes Hub, Android, Cloudflare, `.codex`, device state, and credentials; scans the exported text for high-confidence secrets and private-LAN snapshots; and records every exported file hash. Publishing that repository is a separate externally visible action and requires explicit approval.

## Pairing

1. Start the unchanged Hub.
2. Prefer a locally generated `lumina://pair` QR code containing one Hub LAN URL and its token. Scan it with the iPad Camera, open Lumina, verify the displayed Hub URL, then choose **连接并验证**. The app never displays the token and does not save it until this confirmation.
3. Alternatively, on the Hub computer open `http://127.0.0.1:17890/api/v1/pairing`, then enter one listed LAN URL and its token in Lumina > Settings.
4. Accept iPadOS's local-network prompt. For manual pairing, choose **Save and Test**.

Cloudflare Access client fields are optional and match the Android client. Regular provisioning stores secrets in a this-device-only shared Keychain access group. Free provisioning without App Groups stores them in the main App's private Keychain; its Widget opens the App to run the selected scene without exposing credentials in widget configuration.

## Verification boundary

The repository can verify API coverage, project membership, resources, privacy keys, and source invariants on Windows with:

```powershell
node --test .\test\contract.test.mjs
npm exec --yes --package=@ast-grep/cli@0.45.2 -- ast-grep scan --rule .\test\swift-syntax.yml .
pwsh -NoProfile -File .\scripts\verify-core.ps1
```

Windows cannot run Xcode, the iPad simulator, Apple code signing, WidgetKit, or physical LAN tests. Do not treat the Node contract suite as proof of compilation or real-device behavior. Follow [`../docs/IPAD_ACCEPTANCE.md`](../docs/IPAD_ACCEPTANCE.md) on a Mac and physical iPad before release.

The platform-independent models and HTTP client also form a Swift Package. On platforms where SwiftPM is healthy, its tests can be run with:

```powershell
swift test --package-path .
```

The checked-in `verify-core.ps1` path is the authoritative Windows fallback: it type-checks the shared sources and platform-independent XCTest files, then compiles and executes a Hub-fixture/authentication smoke test without relying on SwiftPM. AppModel and SwiftUI tests remain part of the Xcode test target because they require Apple frameworks.
