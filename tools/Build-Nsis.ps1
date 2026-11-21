[CmdletBinding()]
param(
    [ValidatePattern('\A\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z')]
    [string]$Version,

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$MakeNsisPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repoRoot 'src/NetAuth/NetAuth.csproj'
$installer = Join-Path $repoRoot 'packaging/nsis/NetAuth.nsi'
$icon = Join-Path $repoRoot 'src/NetAuth/Assets/netauth.ico'
$localDotnet = Join-Path $repoRoot '.dotnet/dotnet.exe'
$dotnet = if (Test-Path -LiteralPath $localDotnet) { $localDotnet } else { (Get-Command dotnet.exe).Source }
$compiler = if ($MakeNsisPath) { (Resolve-Path -LiteralPath $MakeNsisPath).ProviderPath }

$output = Join-Path $repoRoot 'artifacts/nsis'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$output = (Resolve-Path -LiteralPath $output).ProviderPath
$stage = Join-Path $output ('.build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null

Push-Location -LiteralPath $repoRoot
try {
    if (-not $compiler) {
        $nsisVersion = '3.13'
        $expectedHash = 'BA63DFFC4410EE89193E1CB5A41989991BD77C61068DA17E3156D136B7B0B3D8'
        $archive = Join-Path $output "nsis-$nsisVersion.zip"

        if (-not (Test-Path -LiteralPath $archive)) {
            $download = Join-Path $stage "nsis-$nsisVersion.zip"
            $url = "https://downloads.sourceforge.net/project/nsis/NSIS%203/$nsisVersion/nsis-$nsisVersion.zip"
            & curl.exe --fail --silent --show-error --location --proto '=https' --max-time 120 --output $download $url
            if ($LASTEXITCODE -ne 0) { throw "NSIS download failed ($LASTEXITCODE)." }
            if ((Get-FileHash -LiteralPath $download).Hash -ne $expectedHash) {
                throw "Downloaded NSIS $nsisVersion archive SHA-256 does not match."
            }
            Move-Item -LiteralPath $download -Destination $archive -Force
        }

        if ((Get-FileHash -LiteralPath $archive).Hash -ne $expectedHash) {
            throw "Cached NSIS archive SHA-256 does not match. Remove '$archive' and retry."
        }

        Expand-Archive -LiteralPath $archive -DestinationPath $stage
        $compiler = Join-Path $stage "nsis-$nsisVersion/makensis.exe"
    }

    $payload = Join-Path $stage 'app'
    $publishArgs = @(
        'publish', $project, '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true',
        '-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true',
        '-p:EnableCompressionInSingleFile=true', '-p:DebugType=None', '-p:DebugSymbols=false', '-o', $payload
    )
    if ($Version) { $publishArgs += "-p:Version=$Version" }
    & $dotnet @publishArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)." }

    $app = Join-Path $payload 'NetAuth.exe'
    $files = @(Get-ChildItem -LiteralPath $payload -Recurse -File -Force)
    if ($files.Count -ne 1 -or $files[0].FullName -ne $app) {
        throw 'The NSIS installer requires a self-contained publish containing only NetAuth.exe.'
    }

    $metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($app)
    $displayVersion = $metadata.ProductVersion.Split('+')[0]
    if ($displayVersion -notmatch '\A\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z') {
        throw "Unsupported NetAuth product version '$displayVersion'."
    }
    $fileVersion = '{0}.{1}.{2}.{3}' -f $metadata.FileMajorPart, $metadata.FileMinorPart,
        $metadata.FileBuildPart, $metadata.FilePrivatePart
    $name = "NetAuth-Setup-$displayVersion-win-x64.exe"
    $stagedSetup = Join-Path $stage $name

    & $compiler /V3 /WX /INPUTCHARSET UTF8 "/DAPP_EXE=$app" "/DAPP_ICON=$icon" "/DSETUP_EXE=$stagedSetup" `
        "/DAPP_VERSION=$displayVersion" "/DAPP_FILE_VERSION=$fileVersion" $installer
    if ($LASTEXITCODE -ne 0) { throw "MakeNSIS failed ($LASTEXITCODE)." }

    $setup = Join-Path $output $name
    Move-Item -LiteralPath $stagedSetup -Destination $setup -Force
    Get-Item -LiteralPath $setup
} finally {
    Pop-Location
    $resolvedStage = Get-Item -LiteralPath $stage
    if ($resolvedStage.FullName -eq $stage -and (Split-Path -Parent $resolvedStage.FullName) -eq $output -and
        -not ($resolvedStage.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Remove-Item -LiteralPath $resolvedStage.FullName -Recurse -Force
    }
}
