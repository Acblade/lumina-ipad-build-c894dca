[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ipadRoot = Split-Path -Parent $PSScriptRoot
$swiftRoot = Join-Path $env:LOCALAPPDATA 'Programs\Swift'

$swiftC = Get-Command swiftc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
if (-not $swiftC) {
    $swiftC = Get-ChildItem -LiteralPath (Join-Path $swiftRoot 'Toolchains') -Filter swiftc.exe -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -ExpandProperty FullName -First 1
}
if (-not $swiftC) {
    throw 'Swift compiler not found. Install Swift 6 for Windows or add swiftc.exe to PATH.'
}

$sdk = Get-ChildItem -LiteralPath (Join-Path $swiftRoot 'Platforms') -Directory -Filter Windows.sdk -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -ExpandProperty FullName -First 1
if (-not $sdk) { throw 'Swift Windows SDK not found.' }

$xctestLibrary = Get-ChildItem -LiteralPath (Join-Path $swiftRoot 'Platforms') -Directory -Filter XCTest.swiftmodule -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    ForEach-Object { $_.Parent.FullName }
if (-not $xctestLibrary) { throw 'Swift XCTest module not found.' }

$toolchainBin = Split-Path -Parent $swiftC
$runtimeBin = Get-ChildItem -LiteralPath (Join-Path $swiftRoot 'Runtimes') -Directory -Filter bin -Recurse -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'swiftCore.dll') } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -ExpandProperty FullName -First 1
if (-not $runtimeBin) { throw 'Swift runtime not found.' }

$xctestBin = Join-Path (Split-Path -Parent (Split-Path -Parent $xctestLibrary)) 'bin64'
$originalPath = $env:PATH
$env:PATH = "$toolchainBin;$runtimeBin;$xctestBin;$originalPath"

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("LuminaIpadCore-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

$models = Join-Path $ipadRoot 'LuminaShared\Models.swift'
$client = Join-Path $ipadRoot 'LuminaShared\APIClient.swift'
$smoke = Join-Path $ipadRoot 'test\CoreSmoke.swift'
$modelTests = Join-Path $ipadRoot 'LuminaPadTests\ModelsTests.swift'
$clientTests = Join-Path $ipadRoot 'LuminaPadTests\APIClientTests.swift'
$module = Join-Path $temporaryRoot 'LuminaCore.swiftmodule'
$executable = Join-Path $temporaryRoot 'LuminaCoreSmoke.exe'

function Invoke-SwiftCompiler {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & $swiftC @Arguments
    if ($LASTEXITCODE -ne 0) { throw "swiftc failed with exit code $LASTEXITCODE" }
}

try {
    Write-Host '[1/4] Type-checking platform-independent Hub models and HTTP client'
    Invoke-SwiftCompiler @('-swift-version', '5', '-sdk', $sdk, '-parse-as-library', '-typecheck', $models, $client)

    Write-Host '[2/4] Emitting the testable LuminaCore module'
    Invoke-SwiftCompiler @('-swift-version', '5', '-sdk', $sdk, '-parse-as-library', '-enable-testing', '-emit-module', '-module-name', 'LuminaCore', $models, $client, '-emit-module-path', $module)

    Write-Host '[3/4] Type-checking XCTest sources'
    Invoke-SwiftCompiler @('-swift-version', '5', '-sdk', $sdk, '-parse-as-library', '-typecheck', '-I', $temporaryRoot, '-I', $xctestLibrary, $modelTests, $clientTests)

    Write-Host '[4/4] Compiling and running the end-to-end core smoke test'
    Invoke-SwiftCompiler @('-swift-version', '5', '-sdk', $sdk, '-use-ld=lld', $models, $client, $smoke, '-o', $executable)
    & $executable
    if ($LASTEXITCODE -ne 0) { throw "Core smoke test failed with exit code $LASTEXITCODE" }

    Write-Host 'Lumina iPad core verification passed.'
}
finally {
    $env:PATH = $originalPath
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('LuminaIpadCore-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
