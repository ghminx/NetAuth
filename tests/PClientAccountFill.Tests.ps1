param(
    [string]$NetAuthPath = (Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe'),
    [string]$PreviewDirectory,
    [switch]$CheckLogonTask
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UiTestHelpers.ps1')

$accountPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'NetAuth/Account/account.dat'
$previewAccountPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'NetAuth/Dummy/account.dat'
$netAuth = (Resolve-Path -LiteralPath $NetAuthPath).Path
$inspectPClient = Join-Path $PSScriptRoot '../tools/Inspect-PClient.ps1'
$watchPClientLogin = Join-Path $PSScriptRoot '../tools/Watch-PClientLogin.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ('NetAuth-AccountFill-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $work 'PClientUI.exe'
$otherDirectory = Join-Path $work 'other'
$otherFixture = Join-Path $otherDirectory 'PClientUI.exe'
$otherNetAuth = Join-Path $otherDirectory 'NetAuth.exe'
$previewFixture = Join-Path $work 'NetAuth.PClientPreview.exe'
$valuePattern = [System.Windows.Automation.ValuePattern]::Pattern
$invokePattern = [System.Windows.Automation.InvokePattern]::Pattern
$togglePattern = [System.Windows.Automation.TogglePattern]::Pattern
$startupKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupCommand = '"' + $netAuth + '" --start-in-tray --auto-login'

if ((Test-Path -LiteralPath $accountPath) -or (Test-Path -LiteralPath $previewAccountPath) -or
    (Get-Process -Name NetAuth, PClientUI, NetAuth.PClientPreview -ErrorAction SilentlyContinue) -or
    (Get-ItemProperty -LiteralPath $startupKey -Name NetAuth -ErrorAction SilentlyContinue)) {
    throw 'Run on a development PC with no PClient or NetAuth window and no saved test or operational account.'
}

New-Item -ItemType Directory -Path $work | Out-Null
$app = $null
$client = $null
$overlap = $null
$logonTask = $null
$cleanUpLogonTask = $false
$testAppFiles = @()
try {
    Add-Type -OutputAssembly $fixture -OutputType WindowsApplication -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyFileVersion("5.16.0.93")]

public sealed class AccountFillFixture : Form
{
    private readonly string scenario;
    private bool loginActivated;
    private bool statusAdded;
    private int submissions;

    private AccountFillFixture(string scenario) { this.scenario = scenario; }

    private bool TestsLogin { get { return scenario.StartsWith("login-", StringComparison.Ordinal); } }
    private static string ReopenedStatePath { get { return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "reopened-status.txt"); } }
    private static string SubmissionPath { get { return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "submissions.txt"); } }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(int extra, string kind, string text, int style, int x, int y,
        int width, int height, IntPtr parent, IntPtr id, IntPtr instance, IntPtr args);
    [DllImport("user32.dll")]
    private static extern IntPtr GetDlgItem(IntPtr parent, int controlId);
    [DllImport("user32.dll")]
    private static extern bool EnableWindow(IntPtr window, bool enable);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool SetWindowText(IntPtr window, string text);
    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode)]
    private static extern IntPtr ReadText(IntPtr window, uint message, IntPtr capacity, StringBuilder text);
    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern IntPtr SendNumber(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [STAThread]
    public static void Main(string[] args)
    {
        var scenario = args.Length == 0 ? "login-success" : args[0];
        if (args.Length == 0 && File.Exists(ReopenedStatePath))
            scenario = "real-reopened";
        using (var form = new AccountFillFixture(scenario) { Width = 420, Height = 245 })
        {
            form.Shown += delegate
            {
                var status = scenario == "authenticated" ? "인증되었습니다." : "로그아웃 상태입니다.";
                if (scenario == "real-reopened")
                    status = File.ReadAllText(ReopenedStatePath);
                if (scenario == "real-other-account" || scenario.StartsWith("login-real-cycle", StringComparison.Ordinal))
                    status = (scenario == "real-other-account" ? "55555555" : "76543210") + " 님으로 로그인 상태입니다.";
                var id = scenario == "empty" ? "" : "88888888";
                if (scenario == "diagnostic-reopened")
                    form.AddControl("Static", "91020304 님으로 로그인 상태입니다.", 0x50000000, 18, 1031);
                else
                    form.AddControl("Static", status, 0x50000000, 18, 1013);
                if (scenario == "ambiguous-state" || scenario == "login-ambiguous")
                    form.AddControl("Static", "인증되었습니다.", 0x50000000, 154, 1013);
                if (scenario == "hidden-status")
                    form.AddControl("Static", "인증되었습니다.", 0x40000000, 154, 1013);
                var idField = form.AddControl("Edit", id, 0x50810080, 52, 1024);
                var password = form.AddControl("Edit", scenario == "password" ? "123" : "", 0x508100A0, 86, 1022);
                if (scenario != "login-missing")
                {
                    var enabled = scenario != "login-real-close" && scenario != "login-real-disabled";
                    var caption = scenario == "diagnostic-button-caption" || scenario == "login-real-close" || scenario == "login-caption-mismatch"
                        ? "fixture-private-caption" : "로그인";
                    form.AddControl("Button", caption, enabled ? 0x50010000 : 0x58010000, 120, 1029);
                    if (scenario == "login-real-ambiguous")
                        form.AddControl("Button", "확인", 0x50010000, 154, 1029);
                }
                if (scenario == "partial")
                    new TruncatingEdit().AssignHandle(password);
                if (scenario == "during-selection" || scenario == "during-write")
                    new ConcurrentEdit(scenario == "during-selection" ? 0x00B1 : 0x00C2).AssignHandle(password);
                if (scenario.StartsWith("diagnostic-", StringComparison.Ordinal) && scenario != "diagnostic-reopened")
                {
                    SendNumber(idField, 0x00B1, (IntPtr)2, (IntPtr)6);
                    if (scenario == "diagnostic-during-selection" || scenario == "diagnostic-during-restore")
                        new ConcurrentEdit(0x00B1, scenario == "diagnostic-during-selection" ? 1 : 5).AssignHandle(idField);
                }
                form.Text = form.TestsLogin ? "NetAuth PClient 검증 | 제출 0회" : "Fixture ready";
            };
            Application.Run(form);
        }
    }

    private IntPtr AddControl(string kind, string text, int style, int y, int id)
    {
        var control = CreateWindowEx(0, kind, text, style, 18, y, 320, 28, Handle, (IntPtr)id,
            IntPtr.Zero, IntPtr.Zero);
        if (control == IntPtr.Zero)
            throw new InvalidOperationException("Could not create native control.");
        return control;
    }

    private sealed class TruncatingEdit : NativeWindow
    {
        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x00C2)
                SendNumber(Handle, 0x00C5, (IntPtr)2, IntPtr.Zero);
            base.WndProc(ref message);
        }
    }

    private sealed class ConcurrentEdit : NativeWindow
    {
        private readonly int trigger;
        private int remaining;

        public ConcurrentEdit(int trigger, int occurrence = 1)
        {
            this.trigger = trigger;
            remaining = occurrence;
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == trigger && --remaining == 0)
                SetWindowText(Handle, "manual-entry");
            base.WndProc(ref message);
        }
    }

    protected override void WndProc(ref Message message)
    {
        // 테스트 창 내부에서만 가상 비밀번호를 비교하고 결과만 노출
        if (message.Msg == 0x0111)
        {
            long notification = message.WParam.ToInt64();
            if (notification == 1029)
            {
                loginActivated = true;
                if (TestsLogin)
                    Submit();
                else
                    Text = "Unexpected login activation";
            }
            else if (scenario == "login-real-close" && notification == (0x0300L << 16 | 1022))
            {
                var timer = new Timer { Interval = 150 };
                timer.Tick += delegate
                {
                    timer.Dispose();
                    EnableWindow(GetDlgItem(Handle, 1029), ReadEditText(Handle, 1022).Length != 0);
                };
                timer.Start();
            }
            else if (!TestsLogin && !loginActivated && notification == (0x0300L << 16 | 1022))
            {
                var password = ReadEditText(Handle, 1022);
                Text = password.Length == 0 ? "Fixture password cleared"
                    : password == "manual-entry" ? "Fixture manual entry unchanged"
                    : password.Contains("manual-entry") ? "Fixture manual entry preserved"
                    : password == "fixture-only-password!가" ? "Fixture password matched" : "Fixture password mismatch";
            }
            else if (scenario == "state-after-id" && Text == "Fixture ready" &&
                !statusAdded && notification == (0x0300L << 16 | 1024))
            {
                statusAdded = true;
                AddControl("Static", "인증되었습니다.", 0x50000000, 154, 1013);
                Text = "Fixture status changed";
            }
        }
        base.WndProc(ref message);
    }

    private void Submit()
    {
        Text = "NetAuth PClient 검증 | 제출 " + ++submissions + "회";
        var status = GetDlgItem(Handle, 1013);
        SetWindowText(status, "인증 결과를 기다리는 중입니다.");
        if (scenario.StartsWith("login-real-", StringComparison.Ordinal))
        {
            File.AppendAllLines(SubmissionPath, new[] { "submission" });
            var matchesStored = ReadEditText(Handle, 1024) == "76543210" &&
                ReadEditText(Handle, 1022) == "fixture-only-password!가";
            if (scenario == "login-real-close")
            {
                File.WriteAllText(ReopenedStatePath, matchesStored ? "76543210 님으로 로그인 상태입니다." : "확인되지 않음");
                BeginInvoke(new Action(Close));
            }
            else if (scenario.StartsWith("login-real-cycle", StringComparison.Ordinal))
            {
                SetWindowText(GetDlgItem(Handle, 1022), "");
                SetWindowText(status, matchesStored && scenario == "login-real-cycle"
                    ? "76543210 님으로 로그인 상태입니다." : "로그아웃 상태입니다.");
            }
            return;
        }
        if (scenario == "login-timeout")
            return;
        if (scenario == "login-close")
        {
            BeginInvoke(new Action(Close));
            return;
        }

        var matches = ReadEditText(Handle, 1024) == "demo-user" &&
            ReadEditText(Handle, 1022) == "demo-pass";
        var timer = new Timer { Interval = 300 };
        timer.Tick += delegate
        {
            timer.Dispose();
            SetWindowText(status, matches && scenario != "login-rejected"
                ? "인증되었습니다." : "테스트 자격 증명이 거부되었습니다.");
        };
        timer.Start();
    }

    public static string ReadId(IntPtr parent) { return ReadEditText(parent, 1024); }

    public static void SetDiagnosticStatus(IntPtr parent, string text)
    {
        SetWindowText(GetDlgItem(parent, 1013), text);
    }

    public static int ReadIdSelection(IntPtr parent)
    {
        return SendNumber(GetDlgItem(parent, 1024), 0x00B0, IntPtr.Zero, IntPtr.Zero).ToInt32();
    }

    private static string ReadEditText(IntPtr parent, int controlId)
    {
        var buffer = new StringBuilder(64);
        ReadText(GetDlgItem(parent, controlId), 0x000D, (IntPtr)buffer.Capacity, buffer);
        return buffer.ToString();
    }
}
'@
    [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($fixture)) | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $previewFixture
    New-Item -ItemType Directory -Path $otherDirectory | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $otherFixture

    foreach ($scenario in 'diagnostic-normal', 'diagnostic-during-selection', 'diagnostic-during-restore') {
        $client = Open-App $fixture $scenario
        Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'Fixture ready' } "$scenario window"
        $handle = $client.MainWindowHandle
        $originalSelection = [AccountFillFixture]::ReadIdSelection($handle)
        $json = & {
            function Read-Host($Prompt, [switch]$AsSecureString) {
                ConvertTo-SecureString '76543210' -AsPlainText -Force
            }
            & $inspectPClient -ProcessId $client.Id -CheckIdReplacement -AsJson
        }
        $check = ($json | ConvertFrom-Json).InputCheck
        $actualId = [AccountFillFixture]::ReadId($handle)
        if ($scenario -eq 'diagnostic-normal') {
            if ($check.Reason -ne 'BothCasesMatchedAndRestored' -or -not $check.EmptyIdMatched -or
                -not $check.PrefilledIdMatched -or -not $check.OriginalIdRestored -or -not $check.OriginalSelectionRestored -or
                $actualId -ne '88888888' -or [AccountFillFixture]::ReadIdSelection($handle) -ne $originalSelection) {
                throw 'The ID diagnostic did not confirm both cases and restore the original ID and selection.'
            }
        } elseif ($check.Reason -ne 'RestorationNotVerified' -or $actualId -ne 'manual-entry') {
            throw "$scenario did not preserve the intervening input. Reason: $($check.Reason)."
        }
        $client.Refresh()
        if ($client.MainWindowTitle -ne 'Fixture ready' -or $json -match '76543210|88888888|manual-entry') {
            throw "$scenario submitted, changed the password or reported an ID."
        }
        Close-App $client
        $client = $null
    }
    Write-Output 'Passed 3 ID diagnostic cases, including preservation during selection and restoration.'

    foreach ($scenario in 'prefilled', 'login-real-disabled', 'login-missing', 'diagnostic-button-caption') {
        $client = Open-App $fixture $scenario
        Wait-For {
            $client.Refresh()
            $client.MainWindowTitle -in 'Fixture ready', 'NetAuth PClient 검증 | 제출 0회'
        } "$scenario button diagnostic window"
        $title = $client.MainWindowTitle
        $json = & $inspectPClient -CheckLoginButton -AsJson
        $report = $json | ConvertFrom-Json
        $expected = switch ($scenario) {
            'prefilled' { 'NativeButtonReady' }
            'login-real-disabled' { 'NativeButtonDisabled' }
            'login-missing' { 'NativeButtonNotFound' }
            'diagnostic-button-caption' { 'NativeCaptionDifferent' }
        }
        $client.Refresh()
        if ($report.LoginButtonCheck.Reason -ne $expected -or $json -match 'fixture-private-caption|88888888' -or
            $client.MainWindowTitle -ne $title -or [AccountFillFixture]::ReadId($client.MainWindowHandle) -ne '88888888') {
            throw "${scenario}: the button diagnostic did not explain the result while preserving the fixture."
        }
        Close-App $client
        $client = $null
    }
    Write-Output 'Passed read-only button diagnosis for ready, disabled, missing and mismatched-caption controls.'

    foreach ($observation in 'success', 'unknown-text', 'process-exit') {
        $client = Open-App $fixture 'prefilled'
        Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'Fixture ready' } "$observation diagnostic window"
        $job = Start-Job -ArgumentList $watchPClientLogin, $client.Id -ScriptBlock {
            param($ScriptPath, $TargetId)
            & $ScriptPath -ProcessId $TargetId -WaitSeconds 5
        }
        try {
            Wait-For {
                if ($job.State -eq 'Failed') { Receive-Job $job }
                $job.ChildJobs[0].Information.Count -gt 0
            } 'Login diagnostic recorded the baseline'
            if ($observation -eq 'process-exit') {
                Close-App $client
                $client = $null
            } else {
                $status = if ($observation -eq 'success') { '91020304 님으로 로그인 상태입니다.' } else { '인증 대기 fixture-private-value' }
                [AccountFillFixture]::SetDiagnosticStatus($client.MainWindowHandle, $status)
            }

            if (-not (Wait-Job $job -Timeout 10)) { throw 'The login diagnostic did not finish.' }
            $json = Receive-Job $job 6>$null
            $report = $json | ConvertFrom-Json
            $expectedResult = if ($observation -eq 'success') { 'SuccessTextObserved' } else { 'UnknownState' }
            $expectedState = switch ($observation) {
                'success' { 'SuccessTextObserved' }
                'unknown-text' { 'StatusTextUnrecognized' }
                'process-exit' { 'ProcessExited' }
            }
            if ($report.Result -ne $expectedResult -or $report.Before.State -ne 'LoginRequired' -or
                $report.After.State -ne $expectedState -or $report.Changes.Count -eq 0 -or
                $json -match 'fixture-private-value|88888888|91020304') {
                throw "$observation diagnostic did not report a safe and correct transition."
            }
            if ($observation -eq 'success' -and $report.After.StatusName -ne '[ID] 님으로 로그인 상태입니다.') {
                throw 'The login diagnostic did not redact the authenticated account.'
            }
            if ($client) {
                $client.Refresh()
                if ($client.MainWindowTitle -ne 'Fixture ready' -or
                    [AccountFillFixture]::ReadId($client.MainWindowHandle) -ne '88888888') {
                    throw 'The login diagnostic changed the fixture account or submitted it.'
                }
                Close-App $client
                $client = $null
            }
        } finally {
            Remove-Job $job -Force
        }
    }
    Write-Output 'Passed read-only login diagnosis for explicit success, private unknown text and process exit.'

    $client = Open-App $fixture 'diagnostic-reopened'
    Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'Fixture ready' } 'Reopened authenticated fixture'
    $json = & $watchPClientLogin -CurrentState
    $report = $json | ConvertFrom-Json
    if ($report.Result -ne 'SuccessTextObserved' -or $report.Current.AutomationId -ne '1031' -or
        $report.Current.StatusName -ne '[ID] 님으로 로그인 상태입니다.' -or $json -match '91020304|88888888') {
        throw 'The current-state diagnostic failed to find and redact the authenticated status on a different control.'
    }
    Close-App $client
    $client = $null
    Write-Output 'Passed current-state login diagnosis of a reopened window with a different status control.'

    $worker = Open-App $netAuth '--login-pclient-preview-at-logon'
    try {
        if (-not $worker.WaitForExit(5000) -or $worker.ExitCode -ne 3) {
            throw 'Logon worker should stop when no preview account is registered.'
        }
    } finally {
        Close-App $worker
    }

    $app = Open-App $netAuth ''
    Wait-For { $null -ne (Find-AppWindow $app 'NetAuthAccountSettings') } 'NetAuth account window'
    $settings = Find-AppWindow $app 'NetAuthAccountSettings'
    if ((Find-Control $settings 'PClientExecutablePath') -or (Find-Control $settings 'DetectPClientExecutable')) {
        throw 'The account editor should not ask for an executable path.'
    }
    $storedId = '76543210'
    (Find-Control $settings 'PClientAccountId').GetCurrentPattern($valuePattern).SetValue($storedId)
    (Find-Control $settings 'PClientAccountPassword').GetCurrentPattern($valuePattern).SetValue('fixture-only-password!가')
    (Find-Control $settings 'SaveAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For {
        $button = Find-Control $settings 'FillPClientAccount'
        $null -ne $button -and $button.Current.IsEnabled -and -not $button.Current.IsOffscreen
    } 'Saved account action'
    $fillButton = (Find-Control $settings 'FillPClientAccount').GetCurrentPattern($invokePattern)
    $feedback = Find-Control $settings 'AccountFeedback'
    $statusBadge = Find-Control $settings 'PClientAuthenticationStatus'
    if ($null -eq $statusBadge -or $statusBadge.Current.Name -ne 'PClient 상태 미확인') {
        throw 'NetAuth did not show an unknown authentication state without PClient.'
    }
    $client = Open-App $fixture 'prefilled'
    Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'Fixture ready' } 'Running PClient fixture'
    $overlap = Open-App $otherFixture 'prefilled'
    Wait-For { $overlap.Refresh(); $overlap.MainWindowTitle -eq 'Fixture ready' } 'Second PClient fixture'
    $fillButton.Invoke()
    Wait-For {
        (Find-Control $settings 'FillPClientAccount').Current.IsEnabled -and
            $feedback.Current.Name -eq 'PClient 연결되지 않음' -and
            $statusBadge.Current.Name -eq 'PClient 상태 미확인'
    } 'Discovery with two running PClient copies'
    foreach ($discoveryFixture in $client, $overlap) {
        $discoveryFixture.Refresh()
        if ($discoveryFixture.MainWindowTitle -ne 'Fixture ready' -or
            [AccountFillFixture]::ReadId($discoveryFixture.MainWindowHandle) -ne '88888888') {
            throw 'Ambiguous discovery changed the fixture account.'
        }
    }
    Close-App $overlap
    $overlap = $null

    (Find-Control $settings 'EditAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Find-Control $settings 'CancelEdit').Current.IsOffscreen } 'Open editor to reset account feedback'
    (Find-Control $settings 'CancelEdit').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { $feedback.Current.Name -eq '입력을 취소했습니다.' } 'Account feedback reset'
    $fillButton.Invoke()
    Wait-For {
        (Find-Control $settings 'FillPClientAccount').Current.IsEnabled -and
            $feedback.Current.Name -eq 'PClient 연결되지 않음'
    } 'Unsigned PClient was rejected without a dialog'
    $client.Refresh()
    if ($statusBadge.Current.Name -ne 'PClient 상태 미확인' -or $client.MainWindowTitle -ne 'Fixture ready' -or
        [AccountFillFixture]::ReadId($client.MainWindowHandle) -ne '88888888') {
        throw 'An unsigned PClient lookalike received credentials.'
    }

    Close-App $app
    $app = $null
    Add-Type -AssemblyName System.Security
    # 기존에 등록된 실행 파일과 가상 계정을 재현하는 검증용 레코드
    $record = @{
        UserId = $storedId
        Password = 'fixture-only-password!가'
        ExecutableIdentity = @{ Path = $fixture; Sha256 = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash }
    } | ConvertTo-Json -Compress
    $protectedRecord = [Security.Cryptography.ProtectedData]::Protect(
        [Text.Encoding]::UTF8.GetBytes($record), [Text.Encoding]::UTF8.GetBytes('NetAuth.Account.v1'),
        [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($accountPath, $protectedRecord)
    $app = Open-App $netAuth ''
    Wait-For { $null -ne (Find-AppWindow $app 'NetAuthAccountSettings') } 'NetAuth with a previously registered executable'
    $settings = Find-AppWindow $app 'NetAuthAccountSettings'
    Wait-For { (Find-Control $settings 'PClientAuthenticationStatus').Current.Name -eq 'PClient 로그아웃됨' } 'Signed-out badge on opening with automatic login off'
    (Find-Control $settings 'FillPClientAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For {
        $client.Refresh()
        $client.MainWindowTitle -eq 'Fixture password matched' -and
            [AccountFillFixture]::ReadId($client.MainWindowHandle) -eq $storedId
    } 'Previously registered PClient fills the account without a popup or submission'
    Close-App $client
    $client = $null
    Write-Output 'Passed signed-out and unknown badges, automatic detection, and rejection of ambiguous or unsigned executables without a confirmation dialog.'

    $realAutomaticLogin = Find-Control $settings 'AutoLoginAtLogon'
    if ($null -eq $realAutomaticLogin -or -not $realAutomaticLogin.Current.IsEnabled -or
        $realAutomaticLogin.GetCurrentPattern($togglePattern).Current.ToggleState -ne 'Off') {
        throw 'PClient automatic login must be available and initially off.'
    }

    $reopenedStatePath = Join-Path $work 'reopened-status.txt'
    $submissionsPath = Join-Path $work 'submissions.txt'
    foreach ($scenario in 'real-other-account', 'login-real-disabled', 'login-real-close', 'login-real-ambiguous', 'login-real-timeout') {
        $client = Open-App $fixture $scenario
        try {
            Wait-For {
                $client.Refresh()
                $client.MainWindowTitle -in 'Fixture ready', 'NetAuth PClient 검증 | 제출 0회'
            } "$scenario login window"
            $button = Find-Control $settings 'LoginPClient'
            $button.GetCurrentPattern($invokePattern).Invoke()
            if ($scenario -eq 'login-real-timeout') {
                Wait-For { (Find-Control $settings 'PClientAuthenticationStatus').Current.Name -eq 'PClient 확인 중' } 'Badge while signing in'
            }
            $expected = switch ($scenario) {
                'real-other-account' { 'PClient에 다른 계정으로 로그인되어 있습니다.' }
                'login-real-close' { 'PClient에서 등록한 계정의 로그인 상태를 확인했습니다.' }
                'login-real-ambiguous' { 'PClient의 로그인 버튼을 확인할 수 없습니다.' }
                'login-real-disabled' { 'PClient의 로그인 버튼을 확인할 수 없습니다.' }
                'login-real-timeout' { 'PClient에서 로그인 결과를 확인할 수 없습니다. PClient 상태 창을 확인하세요.' }
            }
            Wait-For {
                $button.Current.IsEnabled -and ((Find-Control $settings 'AccountFeedback').Current.Name -eq $expected -or
                    ($scenario -eq 'login-real-close' -and
                     (Find-Control $settings 'AccountFeedback').Current.Name -eq 'PClient의 로그인 버튼을 확인할 수 없습니다.'))
            } "$scenario result" 17
            $actual = (Find-Control $settings 'AccountFeedback').Current.Name
            if ($actual -ne $expected) { throw "${scenario} result: $actual" }

            $expectedState = if ($scenario -eq 'login-real-close') { '인증 확인됨' } else { '미확인' }
            $expectedSubmissions = if ($scenario -in 'real-other-account', 'login-real-disabled', 'login-real-ambiguous') { 0 } else { 1 }
            $submissions = if (Test-Path -LiteralPath $submissionsPath) { @(Get-Content -LiteralPath $submissionsPath).Count } else { 0 }
            if ((Find-Control $settings 'VerificationState').Current.Name -ne $expectedState -or
                $submissions -ne $expectedSubmissions) {
                throw "$scenario did not preserve the authentication result and single submission contract."
            }
            if ($scenario -eq 'login-real-close' -and -not $client.HasExited) {
                throw 'The fixture did not exercise confirmation after PClient was reopened.'
            }
            if ($scenario -eq 'login-real-disabled' -and [AccountFillFixture]::ReadId($client.MainWindowHandle) -ne $storedId) {
                throw 'The disabled-button case did not reach account entry before stopping.'
            }
            if ($scenario -eq 'login-real-ambiguous' -and [AccountFillFixture]::ReadId($client.MainWindowHandle) -ne '88888888') {
                throw 'The ambiguous-button case changed the ID before it could identify the button.'
            }
        } finally {
            Get-Process -Name PClientUI -ErrorAction SilentlyContinue |
                Where-Object { $_.Id -ne $client.Id -and $_.Path -eq $fixture } |
                ForEach-Object { Close-App $_ }
            Close-App $client
            $client = $null
            foreach ($file in $reopenedStatePath, $submissionsPath) {
                if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
            }
        }
    }
    Write-Output 'Passed version-specific native button identification, delayed enablement, reopened status, and safe stopping for duplicate or disabled controls.'

    (Find-Control $settings 'AutoLoginAtLogon').GetCurrentPattern($togglePattern).Toggle()
    Wait-For {
        (Get-ItemProperty -LiteralPath $startupKey -Name NetAuth -ErrorAction SilentlyContinue).NetAuth -eq $startupCommand
    } 'Automatic login registers the current app for Windows logon'

    function Show-TraySettings($RunningApp) {
        $launcher = Open-App $netAuth ''
        try {
            if (-not $launcher.WaitForExit(5000) -or $launcher.ExitCode -ne 0) { throw 'Could not open settings from the tray.' }
        } finally {
            Close-App $launcher
        }
        Wait-For { $null -ne (Find-AppWindow $RunningApp 'NetAuthAccountSettings') } 'Open automatic-login results'
        Find-AppWindow $RunningApp 'NetAuthAccountSettings'
    }

    foreach ($monitorCase in 'delayed', 'login-real-cycle', 'login-real-cycle-rejected') {
        $alreadyAuthenticated = $monitorCase -ne 'delayed'
        Close-App $app
        $app = $null
        if ($alreadyAuthenticated) {
            $client = Open-App $fixture $monitorCase
            Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'NetAuth PClient 검증 | 제출 0회' } 'Already authenticated PClient'
        }

        $app = Open-App $netAuth '--start-in-tray --auto-login'
        if (-not $app.WaitForInputIdle(5000) -or $app.HasExited -or $app.MainWindowHandle -ne [IntPtr]::Zero) {
            throw 'Automatic login did not start with the settings window hidden.'
        }
        $settings = Show-TraySettings $app

        if (-not $alreadyAuthenticated) {
            Wait-For { (Find-Control $settings 'VerificationState').Current.Name -eq '대기 중' } 'Waiting for delayed PClient'
            $launcher = Open-App $netAuth '--start-in-tray --auto-login'
            try {
                if (-not $launcher.WaitForExit(5000) -or $launcher.ExitCode -ne 0) { throw 'Duplicate startup did not exit.' }
            } finally {
                Close-App $launcher
            }
            $client = Open-App $fixture 'login-real-close'
        }

        $expected = if ($alreadyAuthenticated) { 'PClient에 등록한 계정으로 이미 로그인되어 있습니다.' }
            else { 'PClient에서 등록한 계정의 로그인 상태를 확인했습니다.' }
        Wait-For {
            (Find-Control $settings 'VerificationState').Current.Name -eq '인증 확인됨' -and
                (Find-Control $settings 'PClientAuthenticationStatus').Current.Name -eq 'PClient 로그인됨' -and
                (Find-Control $settings 'AccountFeedback').Current.Name -eq $expected -and
                (Find-Control $settings 'AutoLoginAtLogon').Current.IsEnabled
        } 'Automatic login result' 17

        foreach ($manualAction in 'LoginPClient', 'FillPClientAccount') {
            $manualButton = Find-Control $settings $manualAction
            if ($null -ne $manualButton -and -not $manualButton.Current.IsOffscreen) {
                throw 'Manual account actions remained visible while automatic login was enabled.'
            }
        }

        $submissions = if (Test-Path -LiteralPath $submissionsPath) { @(Get-Content -LiteralPath $submissionsPath).Count } else { 0 }
        if ($submissions -ne [int](-not $alreadyAuthenticated)) {
            throw 'Automatic login submitted an unexpected number of times.'
        }
        if ($alreadyAuthenticated) {
            (Find-Control $settings 'CloseWindow').GetCurrentPattern($invokePattern).Invoke()
            Wait-For { -not $app.HasExited -and $null -eq (Find-AppWindow $app 'NetAuthAccountSettings') } 'Monitor remains in the tray'
            [AccountFillFixture]::SetDiagnosticStatus($client.MainWindowHandle, '로그아웃 상태입니다.')
            Wait-For {
                $notice = Find-AppWindow $app 'NetAuthAuthenticationNotification'
                $null -ne $notice -and $notice.Current.Name -eq 'NetAuth · PClient 로그아웃됨'
            } 'Logout notification before submission' 10
            $delayClock = [Diagnostics.Stopwatch]::StartNew()
            Wait-For { Test-Path -LiteralPath $submissionsPath } 'Tray monitor submitted after a later logout' 10
            if ($delayClock.ElapsedMilliseconds -lt 3300) {
                throw 'Automatic login must leave roughly four seconds after confirming logout.'
            }
            $settings = Show-TraySettings $app
            if ($monitorCase -eq 'login-real-cycle-rejected') {
                Wait-For { (Find-Control $settings 'VerificationState').Current.Name -eq '미확인' } 'Unconfirmed automatic relogin' 17
                Start-Sleep -Seconds 11
                if ((Find-Control $settings 'PClientAuthenticationStatus').Current.Name -ne 'PClient 로그아웃됨') {
                    throw 'The badge must report a confirmed logout even if the last attempt was inconclusive.'
                }
            } else {
                Wait-For {
                    (Find-Control $settings 'VerificationState').Current.Name -eq '인증 확인됨' -and
                        (Find-Control $settings 'AccountFeedback').Current.Name -eq 'PClient에서 등록한 계정의 로그인 상태를 확인했습니다.'
                } 'Automatic relogin restored authentication' 17
                Wait-For {
                    $notice = Find-AppWindow $app 'NetAuthAuthenticationNotification'
                    $null -ne $notice -and $notice.Current.Name -eq 'NetAuth · PClient 로그인됨'
                } 'Confirmed login replaces logout notification'
            }
            if (@(Get-Content -LiteralPath $submissionsPath).Count -ne 1) {
                throw 'The monitor submitted more than once for the same logout.'
            }
        }
        Get-Process -Name PClientUI -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -ne $client.Id -and $_.Path -eq $fixture } |
            ForEach-Object { Close-App $_ }
        Close-App $client
        $client = $null
        foreach ($file in $reopenedStatePath, $submissionsPath) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
        }
    }
    (Find-Control $settings 'AutoLoginAtLogon').GetCurrentPattern($togglePattern).Toggle()
    Wait-For {
        -not (Get-ItemProperty -LiteralPath $startupKey -Name NetAuth -ErrorAction SilentlyContinue)
    } 'Turning off automatic login removes the Windows startup entry'
    Write-Output 'Passed startup monitoring, later logout recovery while hidden, and no repeated submission after an unconfirmed result.'

    $verificationBeforeFill = (Find-Control $settings 'VerificationState').Current.Name
    foreach ($scenario in 'ambiguous-state', 'state-after-id', 'unregistered-image', 'empty', 'prefilled', 'hidden-status', 'authenticated', 'password', 'during-selection', 'during-write', 'partial', 'modified-image') {
        $targetExecutable = if ($scenario -eq 'unregistered-image') { $otherFixture } else { $fixture }
        if ($scenario -eq 'modified-image') {
            # 실행 가능한 더미의 끝에 표시 바이트를 추가해 등록 당시와 다른 해시 재현
            $stream = [IO.File]::Open($fixture, 'Append', 'Write', 'None')
            try { $stream.WriteByte(0x2A) } finally { $stream.Dispose() }
        }
        $client = Open-App $targetExecutable $scenario
        Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'Fixture ready' } "$scenario window"
        $handle = $client.MainWindowHandle
        $initialId = [AccountFillFixture]::ReadId($handle)
        $button = Find-Control $settings 'FillPClientAccount'
        $button.GetCurrentPattern($invokePattern).Invoke()
        $expected = switch ($scenario) {
            { $_ -in 'unregistered-image', 'modified-image' } { 'PClient 연결되지 않음' }
            { $_ -in 'authenticated', 'ambiguous-state', 'state-after-id' } { 'PClient에서 로그아웃 상태를 확인할 수 없습니다.' }
            'password' { 'PClient의 비밀번호란을 비운 뒤 다시 시도하세요.' }
            'during-selection' { 'PClient의 비밀번호란을 비운 뒤 다시 시도하세요.' }
            { $_ -in 'partial', 'during-write' } { '입력란 복구를 확인할 수 없습니다. PClient의 입력란을 확인하세요.' }
            default { 'PClient에 ID와 비밀번호를 채웠습니다.' }
        }
        $fillsAccount = $scenario -in 'empty', 'prefilled', 'hidden-status'
        $expectedId = if ($fillsAccount) { $storedId } else { $initialId }
        Wait-For {
            $button.Current.IsEnabled -and (Find-Control $settings 'AccountFeedback').Current.Name -eq $expected -and
                [AccountFillFixture]::ReadId($handle) -eq $expectedId
        } "$scenario result"

        $expectedTitle = switch ($scenario) {
            'partial' { 'Fixture password mismatch' }
            'during-selection' { 'Fixture manual entry unchanged' }
            'during-write' { 'Fixture manual entry preserved' }
            'state-after-id' { 'Fixture status changed' }
            { $fillsAccount } { 'Fixture password matched' }
            default { 'Fixture ready' }
        }
        $client.Refresh()
        if ($client.MainWindowTitle -ne $expectedTitle) {
            throw "$scenario case failed to match the expected password and no-submit behavior. Fixture: $($client.MainWindowTitle)"
        }
        if ((Find-Control $settings 'VerificationState').Current.Name -ne $verificationBeforeFill) {
            throw 'Filling the account changed the authentication result.'
        }
        $badge = (Find-Control $settings 'PClientAuthenticationStatus').Current.Name
        if (($fillsAccount -and $badge -ne 'PClient 로그아웃됨') -or $badge -eq 'PClient 로그인됨') {
            throw "$scenario showed an incorrect PClient login status."
        }
        Close-App $client
        $client = $null
    }

    $testAppFiles = @($netAuth)
    foreach ($extension in '.dll', '.deps.json', '.runtimeconfig.json') {
        $adjacentFile = [IO.Path]::ChangeExtension($netAuth, $extension)
        if (Test-Path -LiteralPath $adjacentFile) { $testAppFiles += $adjacentFile }
    }
    Copy-Item -LiteralPath $testAppFiles -Destination $otherDirectory
    $overlap = Open-App $otherNetAuth ''
    Wait-For { $null -ne (Find-AppWindow $overlap 'NetAuthAccountSettings') } 'Second account window'
    $otherSettings = Find-AppWindow $overlap 'NetAuthAccountSettings'
    (Find-Control $otherSettings 'EditAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Find-Control $otherSettings 'PClientAccountId').Current.IsOffscreen } 'Edit registered ID'
    (Find-Control $otherSettings 'PClientAccountId').GetCurrentPattern($valuePattern).SetValue('')
    (Find-Control $otherSettings 'CancelEdit').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Find-Control $otherSettings 'EditAccount').Current.IsOffscreen } 'Cancelled account edit'
    (Find-Control $otherSettings 'EditAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For {
        $idField = Find-Control $otherSettings 'PClientAccountId'
        $idField -and -not $idField.Current.IsOffscreen -and $idField.GetCurrentPattern($valuePattern).Current.Value -eq $storedId
    } 'Cancelled edit kept the registered ID'
    (Find-Control $otherSettings 'CancelEdit').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Find-Control $otherSettings 'FillPClientAccount').Current.IsOffscreen } 'Saved actions in second account window'

    (Find-Control $settings 'DeleteAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Find-Control $settings 'ConfirmDelete').Current.IsOffscreen } 'Delete from first account window'
    (Find-Control $settings 'ConfirmDelete').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Test-Path -LiteralPath $accountPath) } 'Account removed from the first window'
    (Find-Control $otherSettings 'FillPClientAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Find-Control $otherSettings 'RegisterAccount').Current.IsOffscreen } 'Second window detected deletion'
    (Find-Control $otherSettings 'RegisterAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For { -not (Find-Control $otherSettings 'PClientAccountId').Current.IsOffscreen } 'Registration in second account window'
    if ((Find-Control $otherSettings 'PClientAccountId').GetCurrentPattern($valuePattern).Current.Value -ne '') {
        throw 'A deleted account left a stale ID.'
    }
    Close-App $overlap
    $overlap = $null
    Write-Output 'Passed account edit cancellation and removal across two account windows.'

    Close-App $app
    $app = $null
    $app = Open-App $netAuth '--settings-pclient-preview'
    Wait-For {
        $app.Refresh()
        if ($app.HasExited) { throw "NetAuth login preview exited with code $($app.ExitCode)." }
        $app.MainWindowHandle -ne [IntPtr]::Zero
    } 'NetAuth login preview'
    $settings = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    (Find-Control $settings 'PClientAccountId').GetCurrentPattern($valuePattern).SetValue('demo-user')
    (Find-Control $settings 'PClientAccountPassword').GetCurrentPattern($valuePattern).SetValue('demo-pass')
    (Find-Control $settings 'SaveAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For {
        $button = Find-Control $settings 'TestDummyLogin'
        $null -ne $button -and $button.Current.IsEnabled -and -not $button.Current.IsOffscreen
    } 'Saved preview account action'

    $previewCases = [ordered]@{
        'login-success' = @{ State = '인증 확인됨'; Feedback = '인증 상태를 확인했습니다.'; Submissions = 1 }
        'login-rejected' = @{ State = '계정 거부됨'; Feedback = '계정이 거부되었습니다. ID와 비밀번호를 확인하세요.'; Submissions = 1 }
        'login-timeout' = @{ State = '미확인'; Feedback = '로그인 결과를 확인할 수 없습니다.'; Submissions = 1 }
        'login-missing' = @{ State = '미확인'; Feedback = '대상 창의 로그인 버튼을 확인할 수 없습니다.'; Submissions = 0 }
        'login-caption-mismatch' = @{ State = '미확인'; Feedback = '대상 창의 로그인 버튼을 확인할 수 없습니다.'; Submissions = 0 }
        'login-ambiguous' = @{ State = '미확인'; Feedback = '대상 창에서 로그아웃 상태를 확인할 수 없습니다.'; Submissions = 0 }
        'login-close' = @{ State = '미확인'; Feedback = '로그인 결과를 확인할 수 없습니다.'; WindowClosed = $true }
        'production-isolation' = @{ State = '미확인'; Feedback = '대상 로그인 창을 먼저 열어 주세요.'; Submissions = 0 }
    }
    foreach ($scenario in $previewCases.Keys) {
        $expected = $previewCases[$scenario]
        $client = if ($scenario -eq 'production-isolation') {
            Open-App $fixture 'login-success'
        } else {
            Open-App $previewFixture $scenario
        }
        Wait-For {
            $client.Refresh()
            $client.MainWindowTitle -eq 'NetAuth PClient 검증 | 제출 0회'
        } "$scenario login window"

        if ($scenario -eq 'login-timeout') {
            $overlap = Open-App $netAuth '--settings-pclient-preview'
            Wait-For { $overlap.Refresh(); $overlap.MainWindowHandle -ne [IntPtr]::Zero } 'Second preview UI'
            $overlapWindow = [System.Windows.Automation.AutomationElement]::FromHandle($overlap.MainWindowHandle)
        }
        $button = Find-Control $settings 'TestDummyLogin'
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $button.GetCurrentPattern($invokePattern).Invoke()

        if ($overlap) {
            Wait-For {
                $client.Refresh()
                $client.MainWindowTitle -eq 'NetAuth PClient 검증 | 제출 1회'
            } 'In-flight submission'
            (Find-Control $overlapWindow 'TestDummyLogin').GetCurrentPattern($invokePattern).Invoke()
            Wait-For {
                (Find-Control $overlapWindow 'AccountFeedback').Current.Name -eq '다른 NetAuth 창에서 로그인 결과를 확인하는 중입니다.'
            } 'Duplicate login rejected'
            Close-App $overlap
            $overlap = $null
        }
        try {
            Wait-For {
                $button.Current.IsEnabled -and
                (Find-Control $settings 'VerificationState').Current.Name -eq $expected.State -and
                (Find-Control $settings 'AccountFeedback').Current.Name -eq $expected.Feedback
            } "$scenario outcome" 12
        } catch {
            $client.Refresh()
            $state = (Find-Control $settings 'VerificationState').Current.Name
            $feedback = (Find-Control $settings 'AccountFeedback').Current.Name
            Write-Warning "${scenario}: state='$state', feedback='$feedback', fixture='$($client.MainWindowTitle)'"
            throw
        }

        if ($scenario -eq 'login-timeout' -and $clock.Elapsed.TotalSeconds -lt 7.5) {
            throw 'Result timing expired before the configured wait.'
        }
        if ($expected.WindowClosed) {
            if (-not $client.HasExited) { throw 'Preview client still running after the close scenario.' }
        } else {
            $client.Refresh()
            if ($client.MainWindowTitle -ne "NetAuth PClient 검증 | 제출 $($expected.Submissions)회") {
                throw "$scenario had an unexpected number of submissions. Fixture: $($client.MainWindowTitle)"
            }
        }
        Close-App $client
        $client = $null
    }

    if ($CheckLogonTask) {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $taskName = "NetAuth PClient Preview Logon - $sid"
        if (Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue) {
            throw 'An existing preview task must be preserved. Run scheduler tests using an unregistered Windows profile.'
        }
        $cleanUpLogonTask = $true
        $autoLogin = Find-Control $settings 'AutoLoginAtLogon'
        if ($null -eq $autoLogin -or -not $autoLogin.Current.IsEnabled) {
            throw 'Preview settings must expose an enabled automatic login switch for the saved account.'
        }
        $automaticLogin = $autoLogin.GetCurrentPattern($togglePattern)
        if ($automaticLogin.Current.ToggleState -ne 'Off') {
            throw 'Automatic login must initially be off.'
        }
        $automaticLogin.Toggle()
        Wait-For {
            $automaticLogin.Current.ToggleState -eq 'On' -and
                $null -ne (Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue)
        } 'Automatic login enabled in NetAuth settings'
        $logonTask = Get-ScheduledTask -TaskPath '\' -TaskName $taskName
        if ($logonTask.Actions.Execute -ne $netAuth -or
            $logonTask.Actions.Arguments -ne '--login-pclient-preview-at-logon' -or
            $logonTask.Triggers.CimClass.CimClassName -ne 'MSFT_TaskLogonTrigger' -or
            $logonTask.Principal.LogonType -ne 'Interactive' -or
            $logonTask.Principal.RunLevel -ne 'Limited' -or
            $logonTask.Settings.MultipleInstances -ne 'IgnoreNew') {
            throw 'Unexpected scheduled logon task configuration.'
        }

        Close-App $app
        $app = Open-App $netAuth '--settings-pclient-preview'
        Wait-For { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'Reopened preview settings'
        $settings = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
        $automaticLogin = (Find-Control $settings 'AutoLoginAtLogon').GetCurrentPattern($togglePattern)
        if ($automaticLogin.Current.ToggleState -ne 'On') {
            throw 'Reopening settings lost the registered automatic login state.'
        }

        Start-ScheduledTask -InputObject $logonTask
        Wait-For {
            (Get-ScheduledTask -TaskPath '\' -TaskName $taskName).State -eq 'Running'
        } 'Logon task waiting for the preview'
        Start-Sleep -Milliseconds 750
        if ((Get-ScheduledTask -TaskPath '\' -TaskName $taskName).State -ne 'Running') {
            throw 'Logon task exited before the preview opened.'
        }
        Start-ScheduledTask -InputObject $logonTask
        $client = Open-App $previewFixture 'login-success'
        Wait-For {
            $client.Refresh()
            $client.MainWindowTitle -eq 'NetAuth PClient 검증 | 제출 1회' -and
                (Get-ScheduledTask -TaskPath '\' -TaskName $taskName).State -eq 'Ready'
        } 'Logon task submitted once and finished' 15

        $run = $logonTask | Get-ScheduledTaskInfo
        if ($run.LastTaskResult -ne 0) { throw 'Logon task did not confirm authentication.' }
        Start-Sleep -Milliseconds 1100
        Start-ScheduledTask -InputObject $logonTask
        Wait-For {
            $next = $logonTask | Get-ScheduledTaskInfo
            $next.LastRunTime -gt $run.LastRunTime -and
                (Get-ScheduledTask -TaskPath '\' -TaskName $taskName).State -eq 'Ready'
        } 'Already-authenticated logon run'
        $client.Refresh()
        if (($logonTask | Get-ScheduledTaskInfo).LastTaskResult -ne 0 -or
            $client.MainWindowTitle -ne 'NetAuth PClient 검증 | 제출 1회') {
            throw 'Logon task resubmitted an already-authenticated session.'
        }
        Close-App $client
        $client = $null

        $client = Open-App $previewFixture 'login-rejected'
        Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'NetAuth PClient 검증 | 제출 0회' } 'Rejected preview'
        Start-ScheduledTask -InputObject $logonTask
        Wait-For {
            $client.Refresh()
            $client.MainWindowTitle -eq 'NetAuth PClient 검증 | 제출 1회' -and
                (Get-ScheduledTask -TaskPath '\' -TaskName $taskName).State -eq 'Ready'
        } 'Logon task stopped after rejection' 15
        if (($logonTask | Get-ScheduledTaskInfo).LastTaskResult -ne 5) {
            throw 'Logon task did not report unconfirmed authentication.'
        }

        Close-App $client
        $client = $null
        Start-ScheduledTask -InputObject $logonTask
        Wait-For {
            (Get-ScheduledTask -TaskPath '\' -TaskName $taskName).State -eq 'Running'
        } 'Logon task running before disable'
        $automaticLogin.Toggle()
        Wait-For {
            $automaticLogin.Current.ToggleState -eq 'Off' -and
                $null -eq (Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue) -and
                $null -eq (Get-Process -Name NetAuth -ErrorAction SilentlyContinue | Where-Object Id -ne $app.Id)
        } 'Automatic login disabled in NetAuth settings and waiting worker stopped'

        $updatingTask = [Threading.Mutex]::new($false, 'Local\NetAuth.PClientPreview.Startup')
        try {
            (Find-Control $settings 'DeleteAccount').GetCurrentPattern($invokePattern).Invoke()
            Wait-For {
                $confirmation = Find-Control $settings 'ConfirmDelete'
                $confirmation -and -not $confirmation.Current.IsOffscreen
            } 'Preview account deletion confirmation'
            (Find-Control $settings 'ConfirmDelete').GetCurrentPattern($invokePattern).Invoke()
            Wait-For {
                -not (Test-Path -LiteralPath $previewAccountPath) -and
                    (Find-Control $settings 'AccountFeedback').Current.Name -like '저장된 계정은 삭제했습니다.*'
            } 'Preview account deleted even though task cleanup failed'
        } finally {
            $updatingTask.Dispose()
        }
        Write-Output 'Passed automatic login settings on/off, saved state, delayed target, single run, already authenticated, rejection, and account deletion when startup cleanup fails.'
    }

    if ($PreviewDirectory) {
        New-Item -ItemType Directory -Path $PreviewDirectory -Force | Out-Null
        Copy-Item -LiteralPath $previewFixture -Destination $PreviewDirectory -Force
    }
} finally {
    try {
        if ($cleanUpLogonTask) {
            $null = Read-AppOutput $netAuth '--remove-pclient-preview-startup'
        }
    } finally {
        if ((Get-ItemProperty -LiteralPath $startupKey -Name NetAuth -ErrorAction SilentlyContinue).NetAuth -eq $startupCommand) {
            Remove-ItemProperty -LiteralPath $startupKey -Name NetAuth
        }
        Get-Process -Name PClientUI -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $fixture -and (!$client -or $_.Id -ne $client.Id) } |
            ForEach-Object { Close-App $_ }
        foreach ($file in $reopenedStatePath, $submissionsPath) {
            if ($file -and (Test-Path -LiteralPath $file)) { Remove-Item -LiteralPath $file }
        }
        Close-App $overlap
        Close-App $client
        Close-App $app
        $copiedAppFiles = @($testAppFiles | ForEach-Object { Join-Path $otherDirectory (Split-Path -Leaf $_) })
        foreach ($file in (@($accountPath, $previewAccountPath, $fixture, $previewFixture, $otherFixture) + $copiedAppFiles)) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
        }
        if (Test-Path -LiteralPath $otherDirectory) { Remove-Item -LiteralPath $otherDirectory }
        Remove-Item -LiteralPath $work
    }
}

Write-Output "Passed 12 fill-only cases, including status changes, unregistered or modified executables and intervening input, and $($previewCases.Count) native login preview cases."
