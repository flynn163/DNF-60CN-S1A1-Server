[CmdletBinding()]
param([string] $OutputDirectory)

$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repo 'artifacts/ci/package'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) {
    throw "Use a new output directory: $output"
}

foreach ($relative in @('artifacts/native/random/Release/DFLegacy.RandomNative.dll',
                       'artifacts/native/ijl15/Release/ijl15.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $relative))) {
        throw "Build the Release native modules first: $relative"
    }
}

$payload = Join-Path $output 'application'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
foreach ($module in @('Server', 'Launcher')) {
    $publish = Join-Path $payload $module
    dotnet publish (Join-Path $repo "src/DFLegacy.$module/DFLegacy.$module.csproj") `
        -c Release -r win-x64 --self-contained true -p:BuildRandomNativeReference=false -o $publish
    if ($LASTEXITCODE -ne 0) { throw "Publish failed: $module" }
}

$configuration = Get-Content -LiteralPath (Join-Path $repo 'server.json') -Raw | ConvertFrom-Json
$configuration.DFLegacy.ScriptPvfPath = 'data/Script.pvf'
$configuration.DFLegacy.SkillScriptPath = ''
$configuration.DFLegacy.DataPath = 'data/state.json'
$configuration.DFLegacy.EnablePacketTracing = $false
$configuration | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath (Join-Path $payload 'Server/server.json') -Encoding utf8NoBOM

$launcher = [ordered]@{
    ClientPath = '../client/DNF.exe'
    EntranceHost = '127.0.0.1'
    EntrancePort = 2311
    Account = 'test'
    Password = 'test'
    Accounts = @([ordered]@{ Account = 'test'; Password = 'test' })
    AccountIndex = 0
    StartServer = $false
    D3D9Adapter = 0
    D3D9TimeoutSeconds = 30
    D3D9RetryIntervalSeconds = 1
}
$launcher | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $payload 'Launcher/launcher.json') -Encoding utf8NoBOM

foreach ($name in @('LICENSE', 'README.md', 'ADMIN_API.md')) {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $payload
}
foreach ($name in @('Server/DFLegacy.Server.exe', 'Launcher/DFLegacy.Launcher.exe',
                   'Launcher/ijl15.dll', 'Server/DFLegacy.RandomNative.dll',
                   'Server/coreclr.dll', 'Server/hostfxr.dll',
                   'Launcher/coreclr.dll', 'Launcher/hostfxr.dll',
                   'Server/Microsoft.AspNetCore.dll', 'Launcher/System.Windows.Forms.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $payload $name))) {
        throw "Missing packaged component: $name"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $payload 'Server/wwwroot/admin/index.html'))) {
    throw 'Missing admin web assets.'
}
foreach ($binary in @(@('Server/DFLegacy.Server.exe', 'Amd64'),
                      @('Launcher/DFLegacy.Launcher.exe', 'Amd64'),
                      @('Server/DFLegacy.RandomNative.dll', 'Amd64'),
                      @('Launcher/ijl15.dll', 'I386'))) {
    $stream = [IO.File]::OpenRead((Join-Path $payload $binary[0]))
    $reader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
    try {
        if ($reader.PEHeaders.CoffHeader.Machine.ToString() -ne $binary[1]) {
            throw "Unexpected binary architecture: $($binary[0])"
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}
$privateFiles = @(Get-ChildItem -LiteralPath $payload -Recurse -File | Where-Object {
    $_.Extension -in @('.pvf', '.npk', '.log') -or $_.Name -match '^(state.*\.json|AGENTS\.md)$'
})
if ($privateFiles.Count -gt 0) { throw 'Private resources or runtime data entered the package.' }

$hashes = Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($payload, $_.FullName).Replace('\', '/')
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant(), $relative
}
$hashes | Set-Content -LiteralPath (Join-Path $payload 'SHA256SUMS.txt') -Encoding utf8NoBOM
$revision = (git -C $repo rev-parse --short=12 HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify package revision.' }
$archive = Join-Path $output "DFLegacy-win-x64-$revision.zip"
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $archive -CompressionLevel Optimal
'{0}  {1}' -f (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant(), (Split-Path $archive -Leaf) |
    Set-Content -LiteralPath "$archive.sha256" -Encoding utf8NoBOM
Write-Output "Created self-contained package: $archive"
