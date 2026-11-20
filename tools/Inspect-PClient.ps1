[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 2147483647)]
    [int]$ProcessId
)

$ErrorActionPreference = 'Stop'
$result = [ordered]@{
    ProcessId = $null
    ProcessName = $null
    State = 'UnknownState'
    Reason = 'ProcessNotFound'
    WindowCount = 0
    StatusName = $null
    AutomationId = $null
    ControlType = $null
}

$sessionId = (Get-Process -Id $PID).SessionId
if ($PSBoundParameters.ContainsKey('ProcessId')) {
    $result.ProcessId = $ProcessId
    $target = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $target) {
        return [pscustomobject]$result
    }
    $result.ProcessName = $target.ProcessName
    if ($target.SessionId -ne $sessionId) {
        $result.Reason = 'DifferentSession'
        return [pscustomobject]$result
    }
} else {
    $result.ProcessName = 'PClientUI'
    $targets = @(Get-Process -Name 'PClientUI' -ErrorAction SilentlyContinue |
        Where-Object SessionId -eq $sessionId)
    if ($targets.Count -eq 0) {
        $result.Reason = 'PClientUiNotInSession'
        return [pscustomobject]$result
    }
    if ($targets.Count -gt 1) {
        $result.Reason = 'MultiplePClientUiProcesses'
        return [pscustomobject]$result
    }
    $ProcessId = $targets[0].Id
    $result.ProcessId = $ProcessId
}

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$processCondition = [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId)
$statusNames = '로그아웃 상태입니다.', '로그아웃 상태입니다'
$nameConditions = foreach ($name in $statusNames) {
    [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
}
$statusCondition = [System.Windows.Automation.OrCondition]::new(
    [System.Windows.Automation.Condition[]]$nameConditions)

$windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children, $processCondition)
$result.WindowCount = $windows.Count
if ($windows.Count -eq 0) {
    $result.Reason = 'WindowNotFound'
    return [pscustomobject]$result
}

$result.Reason = 'LogoutTextNotExposed'
foreach ($window in $windows) {
    try {
        $matches = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $statusCondition)
        foreach ($match in $matches) {
            $status = $match.Current
            if ($status.ProcessId -ne $ProcessId -or $status.IsOffscreen -or $status.IsPassword) {
                continue
            }

            $result.State = 'LoginRequired'
            $result.Reason = 'VisibleLogoutText'
            $result.StatusName = $status.Name
            $result.AutomationId = $status.AutomationId
            $result.ControlType = $status.ControlType.ProgrammaticName
            return [pscustomobject]$result
        }
    } catch [System.Windows.Automation.ElementNotAvailableException] {
        $result.Reason = 'WindowChanged'
    }
}

[pscustomobject]$result
