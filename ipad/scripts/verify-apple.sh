#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="${LUMINA_EVIDENCE_DIR:-$repo_root/artifacts/apple-verification-$timestamp}"
result_bundle="$evidence_dir/LuminaPad.xcresult"
derived_data="$evidence_dir/DerivedData"
device_derived_data="$evidence_dir/DeviceDerivedData"
device_staging="$evidence_dir/device-package"
unsigned_ipa="$evidence_dir/LuminaPad-unsigned.ipa"
simulator_udid=""
booted_by_script=0

mkdir -p "$evidence_dir"
if [[ -e "$result_bundle" ]]; then
  echo "Refusing to overwrite existing result bundle: $result_bundle" >&2
  exit 2
fi

exec > >(tee "$evidence_dir/verify-apple.log") 2>&1

finish() {
  local exit_code=$?
  if [[ "$booted_by_script" == "1" && -n "$simulator_udid" ]]; then
    xcrun simctl shutdown "$simulator_udid" >/dev/null 2>&1 || true
  fi
  python3 - "$evidence_dir/run-status.json" "$exit_code" "$timestamp" <<'PY'
import json, pathlib, sys
path, code, started = sys.argv[1:]
pathlib.Path(path).write_text(json.dumps({
    "startedAtUtc": started,
    "finishedAtUtc": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
    "exitCode": int(code),
    "status": "passed" if int(code) == 0 else "failed",
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}
trap finish EXIT

cd "$repo_root"

apple_only=0
if [[ ! -d "$repo_root/hub" ]]; then
  apple_only=1
  echo "Hub source is absent; running the Apple-only public build gate."
fi

required_commands=(xcodebuild xcrun python3 swift)
if [[ "$apple_only" == "0" ]]; then
  required_commands+=(node)
fi
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 3
  fi
done
if [[ "$apple_only" == "0" ]] && ! command -v pnpm >/dev/null 2>&1; then
  if ! command -v corepack >/dev/null 2>&1; then
    echo "pnpm and corepack are both unavailable" >&2
    exit 3
  fi
  corepack enable
fi

{
  sw_vers
  xcodebuild -version
  xcodebuild -showsdks
  swift --version
  if [[ "$apple_only" == "0" ]]; then
    node --version
    pnpm --version
  fi
} | tee "$evidence_dir/toolchain.txt"

if [[ "$apple_only" == "0" ]]; then
  pnpm --dir hub install --frozen-lockfile
  pnpm --dir hub test
  node --test ipad/test/contract.test.mjs
fi
swift test --package-path ipad

xcrun simctl list devices available -j > "$evidence_dir/simulators.json"
selection="$(python3 - "$evidence_dir/simulators.json" "${LUMINA_SIMULATOR_UDID:-}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
preferred = sys.argv[2]
candidates = []
for runtime, devices in data.get("devices", {}).items():
    for device in devices:
        if device.get("isAvailable") and "iPad" in device.get("name", ""):
            candidates.append((runtime, device.get("name", ""), device["udid"], device.get("state", "Shutdown")))
if preferred:
    candidates = [entry for entry in candidates if entry[2] == preferred]
    if not candidates:
        raise SystemExit(f"Requested iPad simulator is unavailable: {preferred}")
if not candidates:
    raise SystemExit("No available iPad simulator is installed")
candidates.sort(reverse=True)
runtime, name, udid, state = candidates[0]
print("\t".join((udid, state, name, runtime)))
PY
)"
IFS=$'\t' read -r simulator_udid simulator_state simulator_name simulator_runtime <<< "$selection"
printf 'Selected %s (%s) from %s\n' "$simulator_name" "$simulator_udid" "$simulator_runtime" | tee "$evidence_dir/simulator.txt"

if [[ "$simulator_state" != "Booted" ]]; then
  xcrun simctl boot "$simulator_udid"
  booted_by_script=1
fi
xcrun simctl bootstatus "$simulator_udid" -b

xcodebuild \
  -project ipad/LuminaPad.xcodeproj \
  -scheme LuminaPad \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -destination-timeout 120 \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$result_bundle" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  clean test | tee "$evidence_dir/xcodebuild.log"

# Compile the actual arm64 iPad target as well as the simulator target. This
# package is intentionally unsigned: a later signing step must bind it to the
# connected iPad and the user's Apple development team before installation.
xcodebuild \
  -project ipad/LuminaPad.xcodeproj \
  -scheme LuminaPad \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$device_derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  clean build | tee "$evidence_dir/xcodebuild-device.log"

device_app="$device_derived_data/Build/Products/Debug-iphoneos/Lumina.app"
if [[ ! -x "$device_app/Lumina" ]]; then
  echo "Expected iPad device app was not produced: $device_app" >&2
  exit 4
fi
if find "$device_app" -type d \( -name '*.xctest' -o -name 'XCTest*.framework' -o -name 'XCUnit.framework' -o -name 'Testing.framework' \) -print -quit | grep -q .; then
  echo "Refusing to package a device app containing test bundles or test frameworks" >&2
  exit 4
fi
mkdir -p "$device_staging/Payload"
ditto "$device_app" "$device_staging/Payload/Lumina.app"
ditto -c -k --sequesterRsrc --keepParent "$device_staging/Payload" "$unsigned_ipa"
xcrun dwarfdump --uuid "$device_app/Lumina" | tee "$evidence_dir/device-binary-uuid.txt"
shasum -a 256 "$unsigned_ipa" | tee "$evidence_dir/LuminaPad-unsigned.ipa.sha256"

python3 - "$repo_root" "$evidence_dir/SOURCE_SHA256.txt" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
included = [root / "ipad", root / "hub" / "src", root / "hub" / "test", root / ".github" / "workflows" / "ipad-xcode.yml"]
excluded_parts = {".build", "DerivedData", "xcuserdata", "artifacts", "node_modules"}
files = []
for item in included:
    if item.is_file():
        files.append(item)
    elif item.is_dir():
        files.extend(path for path in item.rglob("*") if path.is_file() and not excluded_parts.intersection(path.parts))
lines = []
for path in sorted(set(files)):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    lines.append(f"{digest}  {path.relative_to(root).as_posix()}")
output.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "Apple simulator verification and unsigned iPad device build passed. Evidence: $evidence_dir"
