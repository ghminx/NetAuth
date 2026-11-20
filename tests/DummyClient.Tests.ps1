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

function Read-LoginResult {
    $state = & $netAuthExe --login-dummy
    Assert-Equal $LASTEXITCODE 0 'Dummy login exit code'
    $state
}

$scenarios = [ordered]@{
    Success = 'Authenticated'
    AlreadyAuthenticated = 'Authenticated'
    Rejected = 'CredentialsRejected'
    Delayed = 'Authenticated'
    NoResponse = 'UnknownState'
    WindowClosed = 'UnknownState'
    ConnectionError = 'ConnectionError'
    AdditionalVerification = 'ManualActionRequired'
    MissingControl = 'UiMismatch'
}

Assert-Equal (Read-State) 'WaitingForPClient' 'Close any running dummy client before testing'

foreach ($scenario in $scenarios.Keys) {
    $fixtureScenario = if ($scenario -eq 'WindowClosed') { 'NoResponse' } else { $scenario }
    $launch = New-Object System.Diagnostics.ProcessStartInfo($dummyExe, $fixtureScenario)
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
            Assert-Equal (Read-LoginResult) $scenarios[$scenario] "$scenario login result"
            Assert-Equal (Find-Control $window 'SignIn').Current.IsEnabled $false "$scenario submit enabled"
            Assert-Equal ([regex]::Match($count.Current.Name, '[0-9]+').Value) '0' "$scenario submission count"
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

        if ($scenario -eq 'Success') {
            $id.GetCurrentPattern($valuePattern).SetValue('old-demo-id')
            $rememberId.GetCurrentPattern($togglePattern).Toggle()
            $autoLogin.GetCurrentPattern($togglePattern).Toggle()
            Assert-Equal (Read-LoginResult) 'Authenticated' 'Dummy login result'
            Assert-Equal (Read-State) 'Authenticated' 'Dummy window state'
            Assert-Equal ([regex]::Match($count.Current.Name, '[0-9]+').Value) '1' 'Successful submission count'
            Assert-Equal $id.GetCurrentPattern($valuePattern).Current.Value 'demo-user' 'ID replacement'
            Assert-Equal $rememberId.GetCurrentPattern($togglePattern).Current.ToggleState 'Off' 'ID checkbox preserved'
            Assert-Equal $autoLogin.GetCurrentPattern($togglePattern).Current.ToggleState 'On' 'Auto-login checkbox preserved'
            continue
        }

        if ($scenario -in 'Delayed', 'NoResponse', 'WindowClosed') {
            $loginLaunch = New-Object System.Diagnostics.ProcessStartInfo($netAuthExe, '--login-dummy')
            $loginLaunch.UseShellExecute = $false
            $loginLaunch.RedirectStandardOutput = $true
            $loginLaunch.CreateNoWindow = $true
            $loginElapsed = [System.Diagnostics.Stopwatch]::StartNew()
            $login = [System.Diagnostics.Process]::Start($loginLaunch)
            try {
                $timeout.Restart()
                do {
                    $state = Read-State
                    if ($state -eq 'CheckingState') { break }
                    Start-Sleep -Milliseconds 100
                } while (-not $login.HasExited -and $timeout.Elapsed.TotalSeconds -lt 5)
                Assert-Equal $state 'CheckingState' 'Pending response'
                Assert-Equal (Find-Control $window 'SignIn').Current.IsEnabled $false 'Pending submit enabled'
                Assert-Equal ([regex]::Match($count.Current.Name, '[0-9]+').Value) '1' "$scenario pending count"
                if ($scenario -eq 'Delayed') {
                    Assert-Equal (Read-LoginResult) 'LoginInProgress' 'Concurrent login result'
                } elseif ($scenario -eq 'WindowClosed') {
                    Assert-Equal $process.CloseMainWindow() $true 'Close dummy during login'
                    if (-not $process.WaitForExit(3000)) { throw 'Dummy window did not close.' }
                }
                if (-not $login.WaitForExit(10000)) { throw "$scenario login did not finish." }
                Assert-Equal $login.ExitCode 0 "$scenario login exit code"
                if ($scenario -eq 'NoResponse') {
                    Assert-Equal ($loginElapsed.Elapsed.TotalSeconds -ge 8) $true 'Wait before timing out'
                }
                $state = $login.StandardOutput.ReadToEnd().Trim()
            } finally {
                if (-not $login.HasExited) { $login.Kill(); $login.WaitForExit() }
                $login.Dispose()
            }
        } else {
            $state = Read-LoginResult
        }

        Assert-Equal $state $scenarios[$scenario] "$scenario final state"
        if ($scenario -ne 'WindowClosed') {
            Assert-Equal ([regex]::Match($count.Current.Name, '[0-9]+').Value) '1' "$scenario submission count"
            $expectedWindowState = if ($scenario -eq 'NoResponse') { 'CheckingState' } else { $scenarios[$scenario] }
            Assert-Equal (Read-State) $expectedWindowState "$scenario final window state"
        }
    } finally {
        if (-not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

Write-Output "Passed $($scenarios.Count) dummy client scenarios."
