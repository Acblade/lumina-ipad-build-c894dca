[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DestinationPath,

    [switch]$InitializeRepository
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'This script must run inside the Lumina Git repository.'
}
$repoRoot = [IO.Path]::GetFullPath($repoRoot)
$destination = [IO.Path]::GetFullPath($DestinationPath)
$repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($destination.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The build-only export must be outside the private source repository.'
}
if (Test-Path -LiteralPath $destination) {
    throw "Refusing to overwrite an existing export: $destination"
}

$sourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve the source commit.'
}

$archive = Join-Path ([IO.Path]::GetTempPath()) ("lumina-ipad-build-{0}.zip" -f [guid]::NewGuid().ToString('N'))
try {
    & git archive --format=zip --output=$archive HEAD ipad .github/workflows/ipad-xcode.yml
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw 'git archive did not produce the build-only source archive.'
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $destination
} finally {
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
        $resolvedArchive = [IO.Path]::GetFullPath($archive)
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedArchive.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove a temporary archive outside the temp directory: $resolvedArchive"
        }
        Remove-Item -LiteralPath $resolvedArchive -Force
    }
}

$textExtensions = @('.md', '.swift', '.plist', '.xcprivacy', '.entitlements', '.pbxproj', '.xcscheme', '.sh', '.ps1', '.mjs', '.yml', '.yaml', '.json')
$secretPatterns = [ordered]@{
    PrivateKey = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    GitHubToken = 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]+'
    OpenAIKey = 'sk-[A-Za-z0-9_-]{20,}'
    AwsKey = 'AKIA[0-9A-Z]{16}'
    BearerToken = 'Bearer\s+[A-Za-z0-9_.-]{20,}'
    CloudflareSecret = 'CF-Access-Client-Secret.{0,20}[:=].{0,5}[A-Za-z0-9_-]{20,}'
    PrivateLanSnapshot = '(?<![0-9])(?:10(?:\.[0-9]{1,3}){3}|192\.168(?:\.[0-9]{1,3}){2}|172\.(?:1[6-9]|2[0-9]|3[01])(?:\.[0-9]{1,3}){2})(?![0-9])'
}
$findings = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $destination -Recurse -File) {
    if ($file.Extension -notin $textExtensions -and $file.Name -notin @('Package.swift', 'project.pbxproj')) {
        continue
    }
    $contents = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in $secretPatterns.GetEnumerator()) {
        if ($contents -match $pattern.Value) {
            $findings.Add([pscustomobject]@{
                File = [IO.Path]::GetRelativePath($destination, $file.FullName)
                Rule = $pattern.Key
            })
        }
    }
}
if ($findings.Count -gt 0) {
    $findings | Format-Table -AutoSize | Out-String | Write-Error
    throw 'The build-only export failed its privacy scan.'
}

$manifestFiles = Get-ChildItem -LiteralPath $destination -Recurse -File | ForEach-Object {
    [ordered]@{
        path = [IO.Path]::GetRelativePath($destination, $_.FullName).Replace('\', '/')
        bytes = $_.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    }
}
$manifest = [ordered]@{
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    sourceCommit = $sourceCommit
    scope = 'ipad-build-only'
    excludes = @('hub', 'android', 'cloudflare-relay', '.codex', 'device data', 'credentials')
    privacyScan = 'passed'
    files = @($manifestFiles | Sort-Object path)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'BUILD_ONLY_MANIFEST.json') -Encoding utf8

@(
    'artifacts/'
    'ipad/.build/'
    'ipad/DerivedData/'
) | Set-Content -LiteralPath (Join-Path $destination '.gitignore') -Encoding utf8

if ($InitializeRepository) {
    & git -C $destination init -b codex/ipad-public-build
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the build-only Git repository.' }
    & git -C $destination add --all
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stage the build-only Git repository.' }
    & git -C $destination commit -m 'Build Lumina iPad target on Xcode'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the build-only Git repository.' }
}

[pscustomobject]@{
    Destination = $destination
    SourceCommit = $sourceCommit
    Files = $manifestFiles.Count + 2
    PrivacyScan = 'passed'
    RepositoryInitialized = [bool]$InitializeRepository
}
