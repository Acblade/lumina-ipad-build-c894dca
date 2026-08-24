[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IpaPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$')]
    [string]$Udid,

    [string]$IosTool = 'ios',

    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$BundleIdentifier = 'com.sigo.lumina.ipad',

    [string]$EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Ios {
    param(
        [Parameter(Mandatory)]
        [string[]]$IosArguments,

        [switch]$AllowFailure
    )

    $lines = @(& $script:IosToolPath @IosArguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "go-ios failed with exit code ${exitCode}: $($lines -join [Environment]::NewLine)"
    }
    [pscustomobject]@{ ExitCode = $exitCode; Lines = $lines }
}

function Find-JsonRecord {
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    foreach ($line in $Lines) {
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $record.PSObject.Properties[$PropertyName]) {
                return $record
            }
        } catch {
            continue
        }
    }
    return $null
}

$resolvedIpa = (Resolve-Path -LiteralPath $IpaPath).Path
if ([IO.Path]::GetExtension($resolvedIpa) -ne '.ipa') {
    throw "Expected an .ipa file: $resolvedIpa"
}

if (Test-Path -LiteralPath $IosTool -PathType Leaf) {
    $script:IosToolPath = (Resolve-Path -LiteralPath $IosTool).Path
} else {
    $command = Get-Command $IosTool -ErrorAction Stop
    $script:IosToolPath = $command.Source
}

$timestamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $EvidenceDirectory = Join-Path $repoRoot "artifacts\ipad-device-install-$timestamp"
}
$evidencePath = [IO.Path]::GetFullPath($EvidenceDirectory)
if (Test-Path -LiteralPath $evidencePath) {
    throw "Refusing to overwrite an existing evidence directory: $evidencePath"
}
New-Item -ItemType Directory -Path $evidencePath | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolvedIpa)
try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
} finally {
    $archive.Dispose()
}

$requiredEntries = [ordered]@{
    MainAppSignature = '^Payload/[^/]+\.app/_CodeSignature/CodeResources$'
    MainAppProfile = '^Payload/[^/]+\.app/embedded\.mobileprovision$'
    WidgetBundle = '^Payload/[^/]+\.app/PlugIns/LuminaWidget\.appex/'
    WidgetSignature = '^Payload/[^/]+\.app/PlugIns/LuminaWidget\.appex/_CodeSignature/CodeResources$'
    WidgetProfile = '^Payload/[^/]+\.app/PlugIns/LuminaWidget\.appex/embedded\.mobileprovision$'
}
foreach ($item in $requiredEntries.GetEnumerator()) {
    if (-not ($entryNames | Where-Object { $_ -match $item.Value })) {
        throw "Signed IPA validation failed: missing $($item.Key)."
    }
}
foreach ($forbidden in @(
    '\.xctest(?:/|$)',
    '/(?:XCTest[^/]*|XCUnit|Testing)\.framework/'
)) {
    if ($entryNames | Where-Object { $_ -match $forbidden }) {
        throw "Signed IPA validation failed: test payload matching $forbidden must not be installed."
    }
}

$ipaFile = Get-Item -LiteralPath $resolvedIpa
$ipaHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedIpa).Hash
$preflight = [ordered]@{
    checkedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    ipaFileName = $ipaFile.Name
    ipaBytes = $ipaFile.Length
    ipaSha256 = $ipaHash
    targetUdid = $Udid
    bundleIdentifier = $BundleIdentifier
    hasMainSignature = $true
    hasMainProvisioningProfile = $true
    hasWidget = $true
    hasWidgetSignature = $true
    hasWidgetProvisioningProfile = $true
}
$preflight | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidencePath 'preflight.json') -Encoding utf8

$deviceListResult = Invoke-Ios -IosArguments @('list')
$deviceList = Find-JsonRecord -Lines $deviceListResult.Lines -PropertyName 'deviceList'
if ($null -eq $deviceList -or $Udid -notin @($deviceList.deviceList)) {
    throw "Target iPad is not attached: $Udid"
}

$developerModeResult = Invoke-Ios -IosArguments @('devmode', 'get', "--udid=$Udid")
$developerMode = Find-JsonRecord -Lines $developerModeResult.Lines -PropertyName 'DeveloperModeEnabled'
if ($null -eq $developerMode -or $developerMode.DeveloperModeEnabled -ne $true) {
    throw 'Developer Mode is disabled. Enable it in Settings > Privacy & Security > Developer Mode, restart the iPad, and confirm after restart.'
}

$targetDescription = "iPad $Udid"
if (-not $PSCmdlet.ShouldProcess($targetDescription, "Install signed $($ipaFile.Name) ($ipaHash)")) {
    return
}

$installResult = Invoke-Ios -IosArguments @('install', "--path=$resolvedIpa", "--udid=$Udid")
$installResult.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'install.log') -Encoding utf8

$appsResult = Invoke-Ios -IosArguments @('apps', '--list', "--udid=$Udid")
$appsResult.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'installed-apps.log') -Encoding utf8
if (-not ($appsResult.Lines | Where-Object { $_ -match "^$([regex]::Escape($BundleIdentifier))\s" })) {
    throw "Installation returned success but $BundleIdentifier was not listed on the iPad."
}

$tunnelStartedByScript = $false
try {
    $launchResult = Invoke-Ios -IosArguments @('launch', $BundleIdentifier, '--kill-existing', "--udid=$Udid") -AllowFailure
    if ($launchResult.ExitCode -ne 0) {
        $tunnelStdout = Join-Path $evidencePath 'tunnel.stdout.log'
        $tunnelStderr = Join-Path $evidencePath 'tunnel.stderr.log'
        $null = Start-Process -FilePath $script:IosToolPath `
            -ArgumentList @('tunnel', 'start', '--userspace', "--udid=$Udid") `
            -WindowStyle Hidden `
            -RedirectStandardOutput $tunnelStdout `
            -RedirectStandardError $tunnelStderr `
            -PassThru
        $tunnelStartedByScript = $true

        $ready = $false
        foreach ($attempt in 1..15) {
            Start-Sleep -Seconds 2
            $tunnelList = Invoke-Ios -IosArguments @('tunnel', 'ls') -AllowFailure
            if ($tunnelList.ExitCode -eq 0 -and ($tunnelList.Lines -join "`n") -match [regex]::Escape($Udid)) {
                $ready = $true
                break
            }
        }
        if (-not $ready) {
            throw 'The iOS 17+ userspace tunnel did not become ready within 30 seconds.'
        }
        $launchResult = Invoke-Ios -IosArguments @('launch', $BundleIdentifier, '--kill-existing', "--udid=$Udid")
    }
    $launchResult.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'launch.log') -Encoding utf8

    Start-Sleep -Seconds 3
    $screenshotPath = Join-Path $evidencePath 'lumina-first-launch.png'
    $screenshotResult = Invoke-Ios -IosArguments @('screenshot', "--output=$screenshotPath", "--udid=$Udid")
    $screenshotResult.Lines | Set-Content -LiteralPath (Join-Path $evidencePath 'screenshot.log') -Encoding utf8
    if (-not (Test-Path -LiteralPath $screenshotPath -PathType Leaf)) {
        throw 'Screenshot command returned success without producing an image.'
    }
} finally {
    if ($tunnelStartedByScript) {
        $null = Invoke-Ios -IosArguments @('tunnel', 'stopagent', "--udid=$Udid") -AllowFailure
    }
}

$result = [ordered]@{
    finishedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    status = 'installed-and-launched'
    ipaSha256 = $ipaHash
    targetUdid = $Udid
    bundleIdentifier = $BundleIdentifier
    screenshot = 'lumina-first-launch.png'
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidencePath 'result.json') -Encoding utf8
Write-Host "Lumina was installed and launched. Evidence: $evidencePath"
