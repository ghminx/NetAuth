$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UiTestHelpers.ps1')

$netAuth = Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe'
$dummy = Join-Path $PSScriptRoot 'NetAuth.DummyClient/bin/Debug/net10.0-windows/NetAuth.DummyClient.exe'
$accountPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'NetAuth/Dummy/account.dat'
$valuePattern = [System.Windows.Automation.ValuePattern]::Pattern
$invokePattern = [System.Windows.Automation.InvokePattern]::Pattern

function Get-Window($Process) {
    Wait-For { $Process.Refresh(); $Process.MainWindowHandle -ne [IntPtr]::Zero } 'App window'
    [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
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
    $productDescription = Find-Control $settings 'ProductDescription'
    if ($null -eq $productDescription -or $productDescription.Current.IsOffscreen -or
        ($productDescription.Current.Name -replace '\s+', ' ').Trim() -ne
            '창원대 네트워크 접근제어 PClient 로그인 정보 자동 입력 프로그램') {
        throw 'The sidebar does not describe the purpose of NetAuth.'
    }
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
    Close-App $app
    $app = $null

    Add-Type -AssemblyName System.Security
    $data = [Text.Encoding]::UTF8.GetBytes('{}')
    $scope = [Text.Encoding]::UTF8.GetBytes('NetAuth.Dummy.v1')
    $invalidRecord = [Security.Cryptography.ProtectedData]::Protect($data, $scope,
        [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($accountPath, $invalidRecord)
    $app = Open-App $netAuth '--settings-dummy'
    $settings = Get-Window $app
    Wait-For {
        (Find-Control $settings 'AccountFeedback').Current.Name -like '저장된 계정을 읽을 수 없습니다.*'
    } 'Malformed account reported without closing settings'

    $launch = [Diagnostics.ProcessStartInfo]::new($netAuth, '--login-pclient-preview-at-logon')
    $launch.UseShellExecute = $false
    $launch.CreateNoWindow = $true
    $launch.RedirectStandardError = $true
    $worker = [Diagnostics.Process]::Start($launch)
    try {
        if (-not $worker.WaitForExit(5000) -or $worker.ExitCode -ne 6 -or
            $worker.StandardError.ReadToEnd().Trim() -ne 'AccountStoreUnavailable') {
            throw 'The logon worker did not report the malformed account.'
        }
    } finally {
        Close-App $worker
    }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($accountPath)) -ne [Convert]::ToBase64String($invalidRecord)) {
        throw 'Opening settings or starting the logon worker changed the malformed account file.'
    }
} finally {
    Close-App $app
    Close-App $client
    if (Test-Path -LiteralPath $accountPath) { Remove-Item -LiteralPath $accountPath }
}

Write-Output 'Account settings lifecycle, saved dummy login, custom caption buttons and malformed storage handling passed.'
