[CmdletBinding()]
param(
    [ValidateRange(1, 2147483647)]
    [int]$ProcessId,
    [ValidateRange(5, 90)]
    [int]$WaitSeconds = 30,
    [switch]$CurrentState
)

$ErrorActionPreference = 'Stop'
$sessionId = (Get-Process -Id $PID).SessionId
$targets = @(Get-Process -Name PClientUI -ErrorAction SilentlyContinue |
    Where-Object { $_.SessionId -eq $sessionId -and (-not $ProcessId -or $_.Id -eq $ProcessId) })
if ($targets.Count -ne 1) {
    throw '이 Windows 세션에서 PClientUI를 하나로 찾을 수 없습니다. PClient 로그인 창을 열고 다시 실행하세요.'
}

$target = $targets[0]
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$element = [System.Windows.Automation.AutomationElement]
$processCondition = [System.Windows.Automation.PropertyCondition]::new($element::ProcessIdProperty, $target.Id)
$visibleCondition = [System.Windows.Automation.PropertyCondition]::new($element::IsOffscreenProperty, $false)
$statusCondition = [System.Windows.Automation.AndCondition]::new(
    $processCondition, $visibleCondition,
    [System.Windows.Automation.PropertyCondition]::new($element::AutomationIdProperty, '1013'))
if ($CurrentState) {
    $textCondition = [System.Windows.Automation.OrCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($element::ClassNameProperty, 'Static'),
        [System.Windows.Automation.PropertyCondition]::new(
            $element::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text))
    $labelCondition = [System.Windows.Automation.AndCondition]::new($processCondition, $visibleCondition, $textCondition)
}

$logoutText = @('로그아웃 상태입니다.', '로그아웃 상태입니다')
$successText = @('인증되었습니다.', '인증되었습니다', '로그인 상태입니다.', '로그인 상태입니다',
    '로그인되었습니다.', '로그인되었습니다', '로그인에 성공했습니다.', '로그인에 성공했습니다')
$signedInPattern = '\A[0-9]+\s*님으로\s+로그인\s+상태입니다\.?\z'
$statusKeywords = @('로그인', '로그아웃', '인증', '성공', '완료', '실패', '거부', '오류', '연결', '대기')

function Read-LoginState {
    $snapshot = [ordered]@{
        State = 'ProcessExited'
        VisibleWindowCount = 0
        StatusControlCount = 0
        StatusName = $null
        StatusKeywords = @()
        AutomationId = $null
        ControlType = $null
    }
    if ($target.HasExited) {
        return [pscustomobject]$snapshot
    }

    try {
        $windows = @($element::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $processCondition) |
            Where-Object { -not $_.Current.IsOffscreen })
        $snapshot.VisibleWindowCount = $windows.Count
        $descendants = [System.Windows.Automation.TreeScope]::Descendants
        $statuses = @(
            foreach ($window in $windows) {
                $window.FindAll($descendants, $statusCondition) |
                    ForEach-Object { $_.Current }
            }
        )
        if ($CurrentState -and $statuses.Count -eq 0) {
            # 다시 열린 화면에 기존 상태 ID가 없을 때 같은 프로세스의 상태 문구 탐색
            $statuses = @(
                foreach ($window in $windows) {
                    $window.FindAll($descendants, $labelCondition) | ForEach-Object { $_.Current } |
                        Where-Object { -not $_.IsPassword -and ([string]$_.Name).Trim() -match $signedInPattern }
                }
            )
        }
        $snapshot.StatusControlCount = $statuses.Count
        $snapshot.State = if ($snapshot.VisibleWindowCount -eq 0) { 'NoVisibleWindow' }
            elseif ($statuses.Count -eq 0) { 'StatusNotVisible' }
            elseif ($statuses.Count -gt 1) { 'AmbiguousStatus' }
            else { 'StatusTextUnrecognized' }
        if ($statuses.Count -eq 1) {
            $status = $statuses[0]
            $snapshot.AutomationId = $status.AutomationId
            $snapshot.ControlType = $status.ControlType.ProgrammaticName
            # 입력 컨트롤 제외 및 공유 결과에서 알 수 없는 원문 제외
            if ($status.IsPassword -or $status.ClassName -match 'Edit' -or $snapshot.ControlType -eq 'ControlType.Edit') {
                $snapshot.State = 'UnexpectedStatusControl'
            } else {
                $name = ([string]$status.Name).Trim()
                if ($name -in $logoutText) {
                    $snapshot.State = 'LoginRequired'
                    $snapshot.StatusName = $name
                } elseif ($name -in $successText) {
                    $snapshot.State = 'SuccessTextObserved'
                    $snapshot.StatusName = $name
                } elseif ($name -match $signedInPattern) {
                    $snapshot.State = 'SuccessTextObserved'
                    $snapshot.StatusName = '[ID] 님으로 로그인 상태입니다.'
                } else {
                    $snapshot.StatusKeywords = @($statusKeywords | Where-Object { $name.Contains($_) })
                }
            }
        }
    } catch [System.Windows.Automation.ElementNotAvailableException], [System.Runtime.InteropServices.COMException] {
        $snapshot.State = 'WindowChangedDuringScan'
    }
    [pscustomobject]$snapshot
}

try {
    $fileVersion = $null
    try {
        $fileVersion = $target.MainModule.FileVersionInfo.FileVersion
    } catch [System.ComponentModel.Win32Exception], [System.InvalidOperationException] {
        # 버전 조회가 제한된 환경에서도 상태 확인 가능
    }

    $report = [ordered]@{
        ProcessId = $target.Id
        ProcessName = 'PClientUI'
        FileVersion = $fileVersion
    }
    $before = Read-LoginState
    if ($CurrentState) {
        $report.Result = if ($before.State -in 'LoginRequired', 'SuccessTextObserved') { $before.State } else { 'UnknownState' }
        $report.Current = $before
        [pscustomobject]$report | ConvertTo-Json -Depth 6
        return
    }

    $after = $null
    $changes = [System.Collections.Generic.List[object]]::new()
    $result = 'BaselineNotConfirmed'
    if ($before.State -eq 'LoginRequired') {
        Write-Host "로그아웃 상태를 확인했습니다. $WaitSeconds 초 안에 PClient에서 로그인 버튼을 직접 한 번 눌러 주세요."
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $previous = $before | ConvertTo-Json -Compress
        $result = 'UnknownState'
        do {
            Start-Sleep -Milliseconds 250
            $after = Read-LoginState
            $current = $after | ConvertTo-Json -Compress
            if ($previous -cne $current) {
                $changes.Add([pscustomobject]@{ ElapsedMilliseconds = $clock.ElapsedMilliseconds; Snapshot = $after })
                $previous = $current
            }
            if ($after.State -eq 'SuccessTextObserved') {
                $result = 'SuccessTextObserved'
                break
            }
        } while ($after.State -ne 'ProcessExited' -and $clock.Elapsed.TotalSeconds -lt $WaitSeconds)
    } else {
        Write-Host '로그인 전 상태를 확인하지 못했습니다. 로그아웃 상태의 PClient 창을 열고 다시 실행하세요.'
    }

    $report.Result = $result
    $report.Before = $before
    $report.After = $after
    $report.Changes = $changes.ToArray()
    [pscustomobject]$report | ConvertTo-Json -Depth 6
} finally {
    $target.Dispose()
}
