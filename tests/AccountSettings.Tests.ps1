$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$netAuth = Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe'
$dummy = Join-Path $PSScriptRoot 'NetAuth.DummyClient/bin/Debug/net10.0-windows/NetAuth.DummyClient.exe'
$accountPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'NetAuth/Dummy/account.dat'
$valuePattern = [System.Windows.Automation.ValuePattern]::Pattern
$invokePattern = [System.Windows.Automation.InvokePattern]::Pattern

function Wait-For($Condition, $Context) {
    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 80
    } while ($elapsed.Elapsed.TotalSeconds -lt 8)
    throw "Timed out: $Context"
}

function Open-App($Path, $Arguments) {
    $launch = [System.Diagnostics.ProcessStartInfo]::new($Path, $Arguments)
    $launch.UseShellExecute = $false
    $launch.CreateNoWindow = $true
    [System.Diagnostics.Process]::Start($launch)
}

function Close-App($Process) {
    if ($null -eq $Process) { return }
    if (-not $Process.HasExited) {
        if (-not $Process.CloseMainWindow() -or -not $Process.WaitForExit(3000)) {
            $Process.Kill()
            $Process.WaitForExit()
        }
    }
    $Process.Dispose()
}

function Get-Window($Process) {
    Wait-For { $Process.Refresh(); $Process.MainWindowHandle -ne [IntPtr]::Zero } 'App window'
    [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
}

function Find-Control($Window, $Id) {
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Is-Visible($Window, $Id) {
    $control = Find-Control $Window $Id
    $null -ne $control -and -not $control.Current.IsOffscreen
}

function Click-Button($Id) {
    (Find-Control $settings $Id).GetCurrentPattern($invokePattern).Invoke()
}

function Assert-CleanLabels($Window) {
    $elements = $Window.FindAll([System.Windows.Automation.TreeScope]::Subtree,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $elements) {
        if (-not $element.Current.IsOffscreen -and $element.Current.Name -match '더미|테스트') {
            throw 'An internal label is visible in the account window.'
        }
    }
}

function Set-Account($Id, $Password) {
    $passwordBox = Find-Control $settings 'PClientAccountPassword'
    if (-not $passwordBox.Current.IsPassword) { throw 'The password field is unmasked.' }
    (Find-Control $settings 'PClientAccountId').GetCurrentPattern($valuePattern).SetValue($Id)
    $passwordBox.GetCurrentPattern($valuePattern).SetValue($Password)
}

if ((Test-Path -LiteralPath $accountPath) -or (Get-Process -Name 'NetAuth.DummyClient' -ErrorAction SilentlyContinue)) {
    throw 'Use a Windows test account with no saved dummy account and no running dummy window.'
}

$app = $null
$client = $null
try {
    $client = Open-App $dummy 'Success'
    $dummyWindow = Get-Window $client
    $app = Open-App $netAuth '--settings-dummy'
    $settings = Get-Window $app
    Wait-For { Is-Visible $settings 'SaveAccount' } 'First-run account editor'
    Assert-CleanLabels $settings
    $windowPattern = $settings.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
    Click-Button 'MaximizeOrRestoreWindow'
    Wait-For { $windowPattern.Current.WindowVisualState -eq 'Maximized' } 'Custom maximize button'
    Click-Button 'MaximizeOrRestoreWindow'
    Wait-For { $windowPattern.Current.WindowVisualState -eq 'Normal' } 'Custom restore button'
    Click-Button 'MinimizeWindow'
    Wait-For { $windowPattern.Current.WindowVisualState -eq 'Minimized' } 'Custom minimize button'
    $windowPattern.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal)
    Wait-For { $windowPattern.Current.WindowVisualState -eq 'Normal' } 'Restore after minimizing'
    Click-Button 'SaveAccount'
    Wait-For { (Find-Control $settings 'AccountFeedback').Current.Name.Length -gt 0 } 'Required input feedback'
    if (Test-Path -LiteralPath $accountPath) { throw 'An empty account was saved.' }
    Set-Account 'cancel-demo' 'cancel-demo-password'
    Click-Button 'CancelEdit'
    Wait-For { Is-Visible $settings 'RegisterAccount' } 'Cancelled first-run editor'
    if (Test-Path -LiteralPath $accountPath) { throw 'Cancel saved an account.' }

    Click-Button 'RegisterAccount'
    Wait-For { Is-Visible $settings 'SaveAccount' } 'Reopened account editor'
    $initialId = 'persisted-demo'
    $initialPassword = 'dev-only-protection-check'
    Set-Account $initialId $initialPassword
    Click-Button 'SaveAccount'
    Wait-For { Is-Visible $settings 'EditAccount' } 'Saved account overview'
    $encrypted = [IO.File]::ReadAllBytes($accountPath)
    foreach ($encoding in [Text.Encoding]::UTF8, [Text.Encoding]::Unicode) {
        $decoded = $encoding.GetString($encrypted)
        if ($decoded.Contains($initialId) -or $decoded.Contains($initialPassword)) {
            throw 'Account values are visible in the saved file.'
        }
    }

    Close-App $app
    $app = $null
    $app = Open-App $netAuth '--settings-dummy'
    $settings = Get-Window $app
    Wait-For { (Find-Control $settings 'SavedAccountId').Current.Name -eq $initialId } 'Account persisted across relaunch'
    Wait-For { (Find-Control $settings 'AccountStatus').Current.Name -eq '이 PC에 저장됨' } 'Saved account status'
    Wait-For { (Find-Control $settings 'VerificationState').Current.Name -eq '확인 전' } 'Account registration is independent of verification'
    Assert-CleanLabels $settings
    if (Is-Visible $settings 'PClientAccountPassword') { throw 'Password field is visible in the account summary.' }
    Click-Button 'EditAccount'
    Wait-For { Is-Visible $settings 'SaveAccount' } 'Account edit'
    Set-Account 'discard-demo' 'discard-demo-password'
    Click-Button 'CancelEdit'
    Wait-For { (Find-Control $settings 'SavedAccountId').Current.Name -eq $initialId } 'Edit cancel retains saved ID'
    Click-Button 'DeleteAccount'
    Wait-For { Is-Visible $settings 'ConfirmDelete' } 'Delete confirmation'
    Click-Button 'CancelDelete'
    Wait-For { -not (Is-Visible $settings 'ConfirmDelete') } 'Cancel deletes nothing'
    if (-not (Test-Path -LiteralPath $accountPath)) { throw 'Cancelling deletion removed the account.' }

    Click-Button 'EditAccount'
    Wait-For { Is-Visible $settings 'SaveAccount' } 'Account replacement editor'
    Set-Account 'demo-user' 'demo-pass'
    Click-Button 'SaveAccount'
    Wait-For { (Find-Control $settings 'SavedAccountId').Current.Name -eq 'demo-user' } 'Saved replacement ID'
    Click-Button 'TestDummyLogin'
    Wait-For {
        (Find-Control $dummyWindow 'SubmissionCount').Current.Name -match '\d+' -and $Matches[0] -eq '1'
    } 'Exactly one dummy submission'
    $state = & $netAuth --probe-dummy
    if ($state -ne 'Authenticated') { throw "Saved test account did not authenticate. State: $state" }

    Wait-For { (Find-Control $settings 'DeleteAccount').Current.IsEnabled } 'Settings ready after login'
    Wait-For { (Find-Control $settings 'VerificationState').Current.Name -eq '인증 확인됨' } 'Verified dummy status'
    Assert-CleanLabels $settings
    Click-Button 'DeleteAccount'
    Wait-For { Is-Visible $settings 'ConfirmDelete' } 'Confirm removal'
    Click-Button 'ConfirmDelete'
    Wait-For { Is-Visible $settings 'RegisterAccount' } 'Unregistered overview'
    if (Test-Path -LiteralPath $accountPath) { throw 'Deleted account file still exists.' }
    Close-App $app
    $app = $null
    $app = Open-App $netAuth '--settings-dummy'
    $settings = Get-Window $app
    Wait-For { Is-Visible $settings 'SaveAccount' } 'First-run editor after deleting and relaunching'
    if (Is-Visible $settings 'TestDummyLogin') { throw 'Login is available with no saved account.' }
    $submissions = (Find-Control $dummyWindow 'SubmissionCount').Current.Name
    if ($submissions -notmatch '\d+' -or $Matches[0] -ne '1') { throw 'Settings triggered an unexpected login.' }
    Click-Button 'CloseWindow'
    if (-not $app.WaitForExit(3000)) { throw 'Custom close button did not close the window.' }
} finally {
    Close-App $app
    Close-App $client
    if (Test-Path -LiteralPath $accountPath) { Remove-Item -LiteralPath $accountPath }
}

Write-Output 'Account settings lifecycle, saved dummy login and custom caption buttons passed.'
