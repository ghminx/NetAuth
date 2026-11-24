$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot '../src/NetAuth/NetAuth.csproj'
$exe = Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe'
$reader = [IO.BinaryReader]::new([IO.File]::OpenRead($exe))
try {
    $reader.BaseStream.Position = 0x3C
    $peHeader = $reader.ReadInt32()
    # PE 선택 헤더의 Subsystem 값 2는 Windows GUI를 의미
    $reader.BaseStream.Position = $peHeader + 4 + 20 + 68
    if ($reader.ReadUInt16() -ne 2) { throw 'NetAuth must launch as a Windows GUI application.' }
} finally {
    $reader.Dispose()
}
$output = dotnet run --project $project --no-build -- --check-ui-automation
if ($LASTEXITCODE -ne 0 -or $output -ne 'NetAuth | UI Automation: UIAutomationClient') {
    throw "NetAuth 시작 검증 실패 (종료 코드 $LASTEXITCODE). 출력: $output"
}
Write-Output 'NetAuth 시작 검증 통과'
