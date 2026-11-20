$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot '../src/NetAuth/NetAuth.csproj'
$output = dotnet run --project $project --no-build -- --check-ui-automation
if ($LASTEXITCODE -ne 0 -or $output -ne 'NetAuth | UI Automation: UIAutomationClient') {
    throw "NetAuth 시작 검증 실패 (종료 코드 $LASTEXITCODE). 출력: $output"
}
Write-Output 'NetAuth 시작 검증 통과'
