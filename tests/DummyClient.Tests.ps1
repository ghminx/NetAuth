$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$dummyExe = Join-Path $PSScriptRoot 'NetAuth.DummyClient/bin/Debug/net10.0-windows/NetAuth.DummyClient.exe'
$netAuthExe = Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe'
$inspectPClient = Join-Path $PSScriptRoot '../tools/Inspect-PClient.ps1'

function Assert-Equal($Actual, $Expected, $Context) {
    if ($Actual -cne $Expected) {
        throw "${Context}: expected '$Expected', got '$Actual'."
    }
}

function Find-Control($Window, $Id) {
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Read-State {
    $state = & $netAuthExe --probe-dummy
    Assert-Equal $LASTEXITCODE 0 'NetAuth exit code'
    $state
}

$scenarios = [ordered]@{
    Success = 'Authenticated'
    AlreadyAuthenticated = 'Authenticated'
    Rejected = 'CredentialsRejected'
    Delayed = 'Authenticated'
    ConnectionError = 'ConnectionError'
    AdditionalVerification = 'ManualActionRequired'
    MissingControl = 'UiMismatch'
}

Assert-Equal (Read-State) 'WaitingForPClient' 'Close any running dummy client before testing'

foreach ($scenario in $scenarios.Keys) {
    $launch = New-Object System.Diagnostics.ProcessStartInfo($dummyExe, $scenario)
    $launch.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($launch)
    try {
        $timeout = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            $process.Refresh()
            $handle = $process.MainWindowHandle
            if ($handle -ne [IntPtr]::Zero) { break }
            Start-Sleep -Milliseconds 100
        } while (-not $process.HasExited -and $timeout.Elapsed.TotalSeconds -lt 10)

        if ($handle -eq [IntPtr]::Zero) { throw "Dummy window did not open for $scenario." }
        $window = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
        $count = Find-Control $window 'SubmissionCount'
        Assert-Equal ([regex]::Match($count.Current.Name, '[0-9]+').Value) '0' "$scenario initial count"

        if ($scenario -in 'AlreadyAuthenticated', 'AdditionalVerification', 'MissingControl') {
            Assert-Equal (Read-State) $scenarios[$scenario] $scenario
            Assert-Equal (Find-Control $window 'SignIn').Current.IsEnabled $false "$scenario submit enabled"
            if ($scenario -eq 'AlreadyAuthenticated') {
                $inspection = & $inspectPClient -ProcessId $process.Id
                Assert-Equal $inspection.State 'UnknownState' 'PClient diagnostic without logout signal'
            }
            continue
        }

        Assert-Equal (Read-State) 'LoginRequired' $scenario
        if ($scenario -eq 'Success') {
            $inspection = & $inspectPClient -ProcessId $process.Id
            Assert-Equal $inspection.State 'LoginRequired' 'PClient diagnostic with logout signal'
            Assert-Equal $inspection.AutomationId 'AuthenticationStatus' 'Logout signal identifier'
        }
        $id = Find-Control $window 'UserId'
        $password = Find-Control $window 'Password'
        $rememberId = Find-Control $window 'RememberId'
        $autoLogin = Find-Control $window 'AutoLogin'
        $valuePattern = [System.Windows.Automation.ValuePattern]::Pattern
        $togglePattern = [System.Windows.Automation.TogglePattern]::Pattern
        Assert-Equal $id.GetCurrentPattern($valuePattern).Current.Value 'demo-user' 'Initial ID'
        Assert-Equal $password.Current.IsPassword $true 'Password masking'
        Assert-Equal $rememberId.GetCurrentPattern($togglePattern).Current.ToggleState 'On' 'ID checkbox'
        Assert-Equal $autoLogin.GetCurrentPattern($togglePattern).Current.ToggleState 'Off' 'Auto-login checkbox'
        $password.GetCurrentPattern($valuePattern).SetValue('demo-pass')
        $submit = Find-Control $window 'SignIn'
        $submit.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()

        if ($scenario -eq 'Delayed') {
            Assert-Equal (Read-State) 'CheckingState' 'Pending response'
            Assert-Equal $submit.Current.IsEnabled $false 'Pending submit enabled'
        }

        $timeout.Restart()
        do {
            $state = Read-State
            if ($state -eq $scenarios[$scenario]) { break }
            Start-Sleep -Milliseconds 100
        } while ($timeout.Elapsed.TotalSeconds -lt 8)
        Assert-Equal $state $scenarios[$scenario] "$scenario final state"
        Assert-Equal ([regex]::Match($count.Current.Name, '[0-9]+').Value) '1' "$scenario submission count"
    } finally {
        if (-not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

Write-Output "Passed $($scenarios.Count) dummy client scenarios."
