param(
    [string]$NetAuthPath = (Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe'),
    [string]$PreviewDirectory,
    [switch]$CheckLogonTask
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$accountPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'NetAuth/Account/account.dat'
$previewAccountPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'NetAuth/Dummy/account.dat'
$netAuth = (Resolve-Path -LiteralPath $NetAuthPath).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('NetAuth-AccountFill-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $work 'PClientUI.exe'
$previewFixture = Join-Path $work 'NetAuth.PClientPreview.exe'
$valuePattern = [System.Windows.Automation.ValuePattern]::Pattern
$invokePattern = [System.Windows.Automation.InvokePattern]::Pattern
$togglePattern = [System.Windows.Automation.TogglePattern]::Pattern

if ((Test-Path -LiteralPath $accountPath) -or (Test-Path -LiteralPath $previewAccountPath) -or
    (Get-Process -Name NetAuth, PClientUI, NetAuth.PClientPreview -ErrorAction SilentlyContinue)) {
    throw 'Run on a development PC with no PClient or NetAuth window and no saved test or operational account.'
}

function Wait-For($Condition, $Context, $TimeoutSeconds = 8) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 80
    } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "Timed out: $Context"
}

function Open-App($Path, $Arguments) {
    $launch = [Diagnostics.ProcessStartInfo]::new($Path, $Arguments)
    $launch.UseShellExecute = $false
    $launch.CreateNoWindow = $true
    [Diagnostics.Process]::Start($launch)
}

function Close-App($Process) {
    if ($null -eq $Process) { return }
    if (-not $Process.HasExited -and (-not $Process.CloseMainWindow() -or -not $Process.WaitForExit(3000))) {
        $Process.Kill()
        $Process.WaitForExit()
    }
    $Process.Dispose()
}

function Find-Control($Window, $Id) {
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

New-Item -ItemType Directory -Path $work | Out-Null
$app = $null
$client = $null
$overlap = $null
$logonTask = $null
$ownsLogonTask = $false
$startupScript = Join-Path $PSScriptRoot '../tools/Register-PClientPreviewStartup.ps1'
try {
    Add-Type -OutputAssembly $fixture -OutputType WindowsApplication -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public sealed class AccountFillFixture : Form
{
    private readonly string scenario;
    private bool loginActivated;
    private int submissions;

    private AccountFillFixture(string scenario) { this.scenario = scenario; }

    private bool TestsLogin { get { return scenario.StartsWith("login-", StringComparison.Ordinal); } }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(int extra, string kind, string text, int style, int x, int y,
        int width, int height, IntPtr parent, IntPtr id, IntPtr instance, IntPtr args);
    [DllImport("user32.dll")]
    private static extern IntPtr GetDlgItem(IntPtr parent, int controlId);
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
        using (var form = new AccountFillFixture(scenario) { Width = 420, Height = 245 })
        {
            form.Shown += delegate
            {
                var status = scenario == "authenticated" ? "인증되었습니다." : "로그아웃 상태입니다.";
                var id = scenario == "empty" ? "" : "88888888";
                form.AddControl("Static", status, 0x50000000, 18, 1013);
                form.AddControl("Edit", id, 0x50810080, 52, 1024);
                var password = form.AddControl("Edit", scenario == "password" ? "123" : "", 0x508100A0, 86, 1022);
                if (scenario != "login-missing")
                    form.AddControl("Button", "로그인", 0x50010000, 120, 1029);
                if (scenario == "partial")
                    new TruncatingEdit().AssignHandle(password);
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
            else if (!TestsLogin && !loginActivated && notification == (0x0300L << 16 | 1022))
            {
                var password = ReadEditText(Handle, 1022);
                Text = password.Length == 0 ? "Fixture password cleared"
                    : password == "fixture-only-password!가" ? "Fixture password matched" : "Fixture password mismatch";
            }
        }
        base.WndProc(ref message);
    }

    private void Submit()
    {
        Text = "NetAuth PClient 검증 | 제출 " + ++submissions + "회";
        var status = GetDlgItem(Handle, 1013);
        SetWindowText(status, "인증 결과를 기다리는 중입니다.");
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

    $worker = Open-App $netAuth '--login-pclient-preview-at-logon'
    try {
        if (-not $worker.WaitForExit(5000) -or $worker.ExitCode -ne 3) {
            throw 'Logon worker should stop when no preview account is registered.'
        }
    } finally {
        Close-App $worker
    }

    $app = Open-App $netAuth ''
    Wait-For { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'NetAuth account window'
    $settings = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    $storedId = '76543210'
    (Find-Control $settings 'PClientAccountId').GetCurrentPattern($valuePattern).SetValue($storedId)
    (Find-Control $settings 'PClientAccountPassword').GetCurrentPattern($valuePattern).SetValue('fixture-only-password!가')
    (Find-Control $settings 'SaveAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For {
        $button = Find-Control $settings 'FillPClientAccount'
        $null -ne $button -and $button.Current.IsEnabled -and -not $button.Current.IsOffscreen
    } 'Saved account action'
    $realAutomaticLogin = Find-Control $settings 'AutoLoginAtLogon'
    if ($null -eq $realAutomaticLogin -or $realAutomaticLogin.Current.IsEnabled) {
        throw 'Real PClient automatic login must remain unavailable until its result is verified.'
    }

    foreach ($scenario in 'empty', 'prefilled', 'authenticated', 'password', 'partial') {
        $client = Open-App $fixture $scenario
        Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'Fixture ready' } "$scenario window"
        $handle = $client.MainWindowHandle
        $initialId = [AccountFillFixture]::ReadId($handle)
        $button = Find-Control $settings 'FillPClientAccount'
        $button.GetCurrentPattern($invokePattern).Invoke()
        $expected = switch ($scenario) {
            'authenticated' { 'PClient에서 로그아웃 상태를 확인할 수 없습니다.' }
            'password' { 'PClient의 비밀번호란을 비운 뒤 다시 시도하세요.' }
            'partial' { 'PClient에서 비밀번호 입력을 확인할 수 없습니다.' }
            default { 'PClient에 ID와 비밀번호를 채웠습니다.' }
        }
        $expectedId = if ($scenario -in 'empty', 'prefilled') { $storedId } else { $initialId }
        Wait-For {
            $button.Current.IsEnabled -and (Find-Control $settings 'AccountFeedback').Current.Name -eq $expected -and
                [AccountFillFixture]::ReadId($handle) -eq $expectedId
        } "$scenario result"

        $expectedTitle = switch ($scenario) {
            'partial' { 'Fixture password cleared' }
            { $_ -in 'empty', 'prefilled' } { 'Fixture password matched' }
            default { 'Fixture ready' }
        }
        $client.Refresh()
        if ($client.MainWindowTitle -ne $expectedTitle) {
            throw "$scenario case failed to match the expected password and no-submit behavior. Fixture: $($client.MainWindowTitle)"
        }
        if ((Find-Control $settings 'VerificationState').Current.Name -ne '확인 전') {
            throw 'Filling the account marked authentication as verified.'
        }
        Close-App $client
        $client = $null
    }

    Close-App $app
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
        Wait-For {
            $button.Current.IsEnabled -and
            (Find-Control $settings 'VerificationState').Current.Name -eq $expected.State -and
            (Find-Control $settings 'AccountFeedback').Current.Name -eq $expected.Feedback
        } "$scenario outcome" 12

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
        $ownsLogonTask = $true
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
        Write-Output 'Passed automatic login settings on/off, saved state, delayed target, single run, already authenticated, and rejection.'
    }

    if ($PreviewDirectory) {
        New-Item -ItemType Directory -Path $PreviewDirectory -Force | Out-Null
        Copy-Item -LiteralPath $previewFixture -Destination $PreviewDirectory -Force
    }
} finally {
    if ($ownsLogonTask) {
        Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue |
            Stop-ScheduledTask -ErrorAction SilentlyContinue
        & $startupScript -Remove
    }
    Close-App $overlap
    Close-App $client
    Close-App $app
    foreach ($file in $accountPath, $previewAccountPath, $fixture, $previewFixture) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
    Remove-Item -LiteralPath $work
}

Write-Output 'Passed 5 fill-only cases and 6 native login preview cases (including concurrent requests).'
