[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IpaPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedIpaSha256,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$')]
    [string]$Udid,

    [string]$WslDistribution = 'Ubuntu',
    [string]$XtoolPath,
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$ExpectedXtoolVersion = '1.17.0',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedXtoolSha256 = '7566d62b829a4deadb01b5389c94f45763d851f204c5d22fa36e9f9d1c88d57b',
    [string]$IosTool = 'ios',
    [string]$NodeTool = 'node',

    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$BundleIdentifierSuffix = 'com.sigo.lumina.ipad',

    [string]$EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Ios {
    param([Parameter(Mandatory)][string[]]$IosArguments, [switch]$AllowFailure)
    $lines = @(& $script:IosToolPath @IosArguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "go-ios failed with exit code ${exitCode}: $($lines -join [Environment]::NewLine)"
    }
    [pscustomobject]@{ ExitCode = $exitCode; Lines = $lines }
}

function Find-JsonRecord {
    param([Parameter(Mandatory)][string[]]$Lines, [Parameter(Mandatory)][string]$PropertyName)
    foreach ($line in $Lines) {
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $record.PSObject.Properties[$PropertyName]) { return $record }
        } catch { continue }
    }
    return $null
}

function Invoke-Wsl {
    param(
        [Parameter(Mandatory)][string[]]$WslArguments,
        [switch]$AllowFailure,
        [switch]$Live
    )
    $lines = @(& wsl.exe -d $WslDistribution -- @WslArguments 2>&1 | ForEach-Object {
        $line = $_.ToString()
        if ($Live) { Write-Host $line }
        $line
    })
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "WSL command failed with exit code ${exitCode}: $($lines -join [Environment]::NewLine)"
    }
    [pscustomobject]@{ ExitCode = $exitCode; Lines = $lines }
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)
    $fullPath = [IO.Path]::GetFullPath($WindowsPath)
    if ($fullPath -notmatch '^(?<drive>[A-Za-z]):\\(?<rest>.+)$') {
        throw "Only a local drive path can be mapped into WSL: $fullPath"
    }
    $drive = $Matches.drive.ToLowerInvariant()
    $rest = $Matches.rest.Replace('\', '/')
    "/mnt/$drive/$rest"
}

$resolvedIpa = (Resolve-Path -LiteralPath $IpaPath).Path
if ([IO.Path]::GetExtension($resolvedIpa) -ne '.ipa') { throw "Expected an .ipa file: $resolvedIpa" }
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedIpa).Hash.ToLowerInvariant()
if ($actualHash -ne $ExpectedIpaSha256.ToLowerInvariant()) {
    throw "Unsigned IPA SHA-256 mismatch. Expected $ExpectedIpaSha256, got $actualHash."
}

if (Test-Path -LiteralPath $IosTool -PathType Leaf) {
    $script:IosToolPath = (Resolve-Path -LiteralPath $IosTool).Path
} else {
    $script:IosToolPath = (Get-Command $IosTool -ErrorAction Stop).Source
}
$nodePath = (Get-Command $NodeTool -ErrorAction Stop).Source
$null = Get-Command wsl.exe -ErrorAction Stop

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolvedIpa)
try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
} finally {
    $archive.Dispose()
}
foreach ($required in @(
    '^Payload/[^/]+\.app/[^/]+$',
    '^Payload/[^/]+\.app/PlugIns/LuminaWidget\.appex/LuminaWidget$',
    '^Payload/[^/]+\.app/Info\.plist$',
    '^Payload/[^/]+\.app/PlugIns/LuminaWidget\.appex/Info\.plist$'
)) {
    if (-not ($entryNames | Where-Object { $_ -match $required })) {
        throw "Unsigned IPA validation failed: missing entry matching $required"
    }
}
foreach ($forbidden in @(
    '\.xctest(?:/|$)',
    '/(?:XCTest[^/]*|XCUnit|Testing)\.framework/'
)) {
    if ($entryNames | Where-Object { $_ -match $forbidden }) {
        throw "Unsigned IPA validation failed: test payload matching $forbidden must not be installed."
    }
}

$deviceList = Find-JsonRecord -Lines (Invoke-Ios -IosArguments @('list')).Lines -PropertyName 'deviceList'
if ($null -eq $deviceList -or $Udid -notin @($deviceList.deviceList)) { throw "Target iPad is not attached: $Udid" }
$developerMode = Find-JsonRecord -Lines (Invoke-Ios -IosArguments @('devmode', 'get', "--udid=$Udid")).Lines -PropertyName 'DeveloperModeEnabled'
if ($null -eq $developerMode -or $developerMode.DeveloperModeEnabled -ne $true) { throw 'Developer Mode is disabled on the target iPad.' }

$wslHome = ((Invoke-Wsl -WslArguments @('sh', '-lc', 'printf %s "$HOME"')).Lines -join '').Trim()
if ([string]::IsNullOrWhiteSpace($XtoolPath)) { $XtoolPath = "$wslHome/.local/lib/lumina-xtool/xtool-1.17.0" }
if ((Invoke-Wsl -WslArguments @('test', '-x', $XtoolPath) -AllowFailure).ExitCode -ne 0) { throw "xtool is not executable in WSL: $XtoolPath" }
if ((Invoke-Wsl -WslArguments @('sh', '-lc', 'command -v zip >/dev/null && command -v unzip >/dev/null') -AllowFailure).ExitCode -ne 0) {
    throw "xtool requires both zip and unzip in WSL. Install them with: sudo apt-get install zip unzip"
}
$xtoolVersion = ((Invoke-Wsl -WslArguments @($XtoolPath, '--version')).Lines -join ' ').Trim()
if ($xtoolVersion -notmatch "\b$([regex]::Escape($ExpectedXtoolVersion))\b") {
    throw "Unexpected xtool version. Expected $ExpectedXtoolVersion, got: $xtoolVersion"
}
$xtoolHashOutput = ((Invoke-Wsl -WslArguments @('sha256sum', '--', $XtoolPath)).Lines -join ' ').Trim()
if ($xtoolHashOutput -notmatch '^(?<hash>[0-9A-Fa-f]{64})\s') { throw "Unable to parse xtool SHA-256: $xtoolHashOutput" }
$xtoolHash = $Matches.hash.ToLowerInvariant()
if ($xtoolHash -ne $ExpectedXtoolSha256.ToLowerInvariant()) {
    throw "xtool SHA-256 mismatch. Expected $ExpectedXtoolSha256, got $xtoolHash."
}
if ((Invoke-Wsl -WslArguments @($XtoolPath, 'auth', 'status') -AllowFailure).ExitCode -ne 0) {
    throw "xtool is not authenticated. In a private visible terminal, run: $XtoolPath auth login"
}

$route = (Invoke-Wsl -WslArguments @('ip', 'route', 'show', 'default')).Lines -join ' '
if ($route -notmatch '\bvia\s+(?<gateway>(?:\d{1,3}\.){3}\d{1,3})\b') { throw "Unable to resolve the WSL gateway from: $route" }
$gateway = $Matches.gateway
$gatewayOctets = $gateway.Split('.') | ForEach-Object { [int]$_ }
$privateGateway = $gatewayOctets.Count -eq 4 -and (
    $gatewayOctets[0] -eq 10 -or
    ($gatewayOctets[0] -eq 172 -and $gatewayOctets[1] -ge 16 -and $gatewayOctets[1] -le 31) -or
    ($gatewayOctets[0] -eq 192 -and $gatewayOctets[1] -eq 168)
)
if (-not $privateGateway) { throw "Refusing to bind the usbmux relay to a non-private address: $gateway" }
if (-not (Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort 27015 -ErrorAction SilentlyContinue)) {
    throw 'Apple Mobile Device Service is not listening on 127.0.0.1:27015.'
}
if (Get-NetTCPConnection -State Listen -LocalAddress $gateway -LocalPort 27015 -ErrorAction SilentlyContinue) {
    throw "TCP $gateway`:27015 is already in use."
}

$timestamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $EvidenceDirectory = Join-Path $repoRoot "artifacts\ipad-xtool-install-$timestamp"
}
$evidencePath = [IO.Path]::GetFullPath($EvidenceDirectory)
if (Test-Path -LiteralPath $evidencePath) { throw "Refusing to overwrite an existing evidence directory: $evidencePath" }
New-Item -ItemType Directory -Path $evidencePath | Out-Null
$preflight = [ordered]@{
    checkedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    ipaFileName = [IO.Path]::GetFileName($resolvedIpa)
    ipaBytes = (Get-Item -LiteralPath $resolvedIpa).Length
    ipaSha256 = $actualHash
    targetUdid = $Udid
    wslDistribution = $WslDistribution
    xtoolPath = $XtoolPath
    xtoolVersion = $ExpectedXtoolVersion
    xtoolSha256 = $xtoolHash
    usbmuxRelay = "$gateway`:27015 -> 127.0.0.1:27015"
    hasMainApp = $true
    hasWidget = $true
}
$preflight | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidencePath 'preflight.json') -Encoding utf8

if (-not $PSCmdlet.ShouldProcess("iPad $Udid", "Provision, sign, and install $([IO.Path]::GetFileName($resolvedIpa)) with xtool")) { return }

$relayScript = Join-Path $PSScriptRoot 'usbmux-relay.mjs'
$relayStdout = Join-Path $evidencePath 'usbmux-relay.stdout.log'
$relayStderr = Join-Path $evidencePath 'usbmux-relay.stderr.log'
$relay = Start-Process -FilePath $nodePath `
    -ArgumentList @("`"$relayScript`"", $gateway, '27015') `
    -WindowStyle Hidden `
    -RedirectStandardOutput $relayStdout `
    -RedirectStandardError $relayStderr `
    -PassThru
$tunnelStartedByScript = $false
try {
    $relayReady = $false
    foreach ($attempt in 1..20) {
        Start-Sleep -Milliseconds 250
        if ($relay.HasExited) { throw "usbmux relay exited early: $(Get-Content -LiteralPath $relayStderr -Raw)" }
        if ((Get-Content -LiteralPath $relayStdout -Raw -ErrorAction SilentlyContinue) -match 'LUMINA_USBMUX_RELAY_READY') {
            $relayReady = $true
            break
        }
    }
    if (-not $relayReady) { throw 'usbmux relay did not become ready within five seconds.' }

    $socketAddress = "USBMUXD_SOCKET_ADDRESS=$gateway`:27015"
    $xtoolDevices = Invoke-Wsl -WslArguments @('env', $socketAddress, $XtoolPath, 'devices', '--usb', '--no-wait')
    if (-not ($xtoolDevices.Lines | Where-Object { $_ -match [regex]::Escape($Udid) })) { throw 'xtool could not see the target iPad through the scoped relay.' }
    $wslIpa = ConvertTo-WslPath -WindowsPath $resolvedIpa
    if ((Invoke-Wsl -WslArguments @('test', '-f', $wslIpa) -AllowFailure).ExitCode -ne 0) {
        throw "The IPA is not visible inside WSL: $wslIpa"
    }
    $install = Invoke-Wsl -WslArguments @('env', $socketAddress, $XtoolPath, 'install', '--udid', $Udid, '--usb', $wslIpa) -Live
    $install.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'xtool-install.log') -Encoding utf8
} finally {
    if (-not $relay.HasExited) { Stop-Process -Id $relay.Id -Force -ErrorAction SilentlyContinue }
    $relay.WaitForExit()
}

$apps = Invoke-Ios -IosArguments @('apps', '--list', "--udid=$Udid")
$apps.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'installed-apps.log') -Encoding utf8
$bundlePattern = "(?<id>[A-Za-z0-9.-]*$([regex]::Escape($BundleIdentifierSuffix)))\s"
$installedLine = $apps.Lines | Where-Object { $_ -match $bundlePattern } | Select-Object -First 1
if (-not $installedLine -or $installedLine -notmatch $bundlePattern) { throw "Installation returned success but no app ending in $BundleIdentifierSuffix was listed." }
$installedBundleIdentifier = $Matches.id
$installedResult = [ordered]@{
    installedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    status = 'provisioned-signed-and-installed-awaiting-launch-verification'
    ipaSha256 = $actualHash
    targetUdid = $Udid
    installedBundleIdentifier = $installedBundleIdentifier
}
$installedResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidencePath 'install-result.json') -Encoding utf8

$tunnelProcess = $null
try {
    $launch = Invoke-Ios -IosArguments @('launch', $installedBundleIdentifier, '--kill-existing', "--udid=$Udid") -AllowFailure
    if ($launch.ExitCode -ne 0) {
        $tunnelStdout = Join-Path $evidencePath 'tunnel.stdout.log'
        $tunnelStderr = Join-Path $evidencePath 'tunnel.stderr.log'
        $tunnelProcess = Start-Process -FilePath $script:IosToolPath `
            -ArgumentList @('tunnel', 'start', '--userspace', "--udid=$Udid") `
            -WindowStyle Hidden `
            -WorkingDirectory $evidencePath `
            -RedirectStandardOutput $tunnelStdout `
            -RedirectStandardError $tunnelStderr `
            -PassThru
        $tunnelStartedByScript = $true
        $ready = $false
        foreach ($attempt in 1..15) {
            Start-Sleep -Seconds 2
            $tunnelList = Invoke-Ios -IosArguments @('tunnel', 'ls') -AllowFailure
            if ($tunnelList.ExitCode -eq 0 -and ($tunnelList.Lines -join "`n") -match [regex]::Escape($Udid)) { $ready = $true; break }
        }
        if (-not $ready) { throw 'The iOS 17+ userspace tunnel did not become ready within 30 seconds.' }
        $launch = Invoke-Ios -IosArguments @('launch', $installedBundleIdentifier, '--kill-existing', "--udid=$Udid") -AllowFailure
        if ($launch.ExitCode -ne 0) {
            $launchDetails = $launch.Lines -join [Environment]::NewLine
            if ($launchDetails -match 'deviceprocesscontrolservice|Error code:\s*2') {
                throw 'Lumina is installed, but iPadOS refused its first launch. On the iPad, open Settings > General > VPN & Device Management, trust the Apple development profile, then run this verification again.'
            }
            throw "Lumina is installed, but launch verification failed: $launchDetails"
        }
    }
    $launch.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'launch.log') -Encoding utf8
    Start-Sleep -Seconds 3
    $screenshot = Join-Path $evidencePath 'lumina-first-launch.png'
    $shot = Invoke-Ios -IosArguments @('screenshot', "--output=$screenshot", "--udid=$Udid")
    $shot.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'screenshot.log') -Encoding utf8
    if (-not (Test-Path -LiteralPath $screenshot -PathType Leaf)) { throw 'Screenshot command returned success without producing an image.' }
} finally {
    if ($tunnelStartedByScript) { $null = Invoke-Ios -IosArguments @('tunnel', 'stopagent', "--udid=$Udid") -AllowFailure }
    if ($null -ne $tunnelProcess -and -not $tunnelProcess.HasExited) {
        Stop-Process -Id $tunnelProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $tunnelIdentity = Join-Path $evidencePath 'selfIdentity.plist'
    if (Test-Path -LiteralPath $tunnelIdentity -PathType Leaf) {
        Remove-Item -LiteralPath $tunnelIdentity -Force
    }
}

$result = [ordered]@{
    finishedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    status = 'provisioned-signed-installed-and-launched'
    ipaSha256 = $actualHash
    targetUdid = $Udid
    installedBundleIdentifier = $installedBundleIdentifier
    screenshot = 'lumina-first-launch.png'
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidencePath 'result.json') -Encoding utf8
Write-Host "Lumina was provisioned, signed, installed, and launched. Evidence: $evidencePath"
