$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$accountPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'NetAuth/Account/account.dat'
$netAuth = (Resolve-Path (Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('NetAuth-IdFill-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $work 'PClientUI.exe'
$valuePattern = [System.Windows.Automation.ValuePattern]::Pattern
$invokePattern = [System.Windows.Automation.InvokePattern]::Pattern

if ((Test-Path -LiteralPath $accountPath) -or (Get-Process -Name NetAuth, PClientUI -ErrorAction SilentlyContinue)) {
    throw 'Run on a development PC with no PClient or NetAuth window and no saved operational account.'
}

function Wait-For($Condition, $Context) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 80
    } while ($clock.Elapsed.TotalSeconds -lt 8)
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
try {
    Add-Type -OutputAssembly $fixture -OutputType WindowsApplication -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public sealed class IdFillFixture : Form
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(int extra, string kind, string text, int style, int x, int y,
        int width, int height, IntPtr parent, IntPtr id, IntPtr instance, IntPtr args);
    [DllImport("user32.dll")]
    private static extern IntPtr GetDlgItem(IntPtr parent, int controlId);
    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode)]
    private static extern IntPtr ReadText(IntPtr window, uint message, IntPtr capacity, StringBuilder text);

    [STAThread]
    public static void Main(string[] args)
    {
        var scenario = args[0];
        using (var form = new IdFillFixture { Width = 420, Height = 245 })
        {
            form.Shown += delegate
            {
                var status = scenario == "authenticated" ? "인증되었습니다." : "로그아웃 상태입니다.";
                var id = scenario == "empty" ? "" : "88888888";
                form.AddControl("Static", status, 0x50000000, 18, 1013);
                form.AddControl("Edit", id, 0x50810080, 52, 1024);
                form.AddControl("Edit", scenario == "password" ? "123" : "", 0x508100A0, 86, 1022);
                form.AddControl("Button", "로그인", 0x50010000, 120, 1029);
                form.Text = "Fixture ready";
            };
            Application.Run(form);
        }
    }

    private void AddControl(string kind, string text, int style, int y, int id)
    {
        if (CreateWindowEx(0, kind, text, style, 18, y, 320, 28, Handle, (IntPtr)id,
            IntPtr.Zero, IntPtr.Zero) == IntPtr.Zero)
            throw new InvalidOperationException("Could not create native control.");
    }

    protected override void WndProc(ref Message message)
    {
        // 비밀번호 변경 알림과 로그인 버튼 호출의 발생 여부 검증
        if (message.Msg == 0x0111)
        {
            long notification = message.WParam.ToInt64();
            if (notification == 1029 || notification == (0x0300L << 16 | 1022))
                Text = "Unexpected password change or login activation";
        }
        base.WndProc(ref message);
    }

    public static string ReadId(IntPtr parent)
    {
        var buffer = new StringBuilder(64);
        ReadText(GetDlgItem(parent, 1024), 0x000D, (IntPtr)buffer.Capacity, buffer);
        return buffer.ToString();
    }
}
'@
    [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($fixture)) | Out-Null

    $app = Open-App $netAuth ''
    Wait-For { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'NetAuth account window'
    $settings = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    $storedId = '76543210'
    (Find-Control $settings 'PClientAccountId').GetCurrentPattern($valuePattern).SetValue($storedId)
    (Find-Control $settings 'PClientAccountPassword').GetCurrentPattern($valuePattern).SetValue('fixture-only-password')
    (Find-Control $settings 'SaveAccount').GetCurrentPattern($invokePattern).Invoke()
    Wait-For {
        $button = Find-Control $settings 'FillPClientId'
        $null -ne $button -and $button.Current.IsEnabled -and -not $button.Current.IsOffscreen
    } 'Saved account action'

    foreach ($scenario in 'empty', 'prefilled', 'authenticated', 'password') {
        $client = Open-App $fixture $scenario
        Wait-For { $client.Refresh(); $client.MainWindowTitle -eq 'Fixture ready' } "$scenario window"
        $handle = $client.MainWindowHandle
        $initialId = [IdFillFixture]::ReadId($handle)
        $button = Find-Control $settings 'FillPClientId'
        $button.GetCurrentPattern($invokePattern).Invoke()
        $expected = switch ($scenario) {
            'authenticated' { 'PClient에서 로그아웃 상태를 확인할 수 없습니다.' }
            'password' { 'PClient의 비밀번호란을 비운 뒤 다시 시도하세요.' }
            default { 'PClient ID를 채웠습니다.' }
        }
        $expectedId = if ($scenario -in 'empty', 'prefilled') { $storedId } else { $initialId }
        Wait-For {
            $button.Current.IsEnabled -and (Find-Control $settings 'AccountFeedback').Current.Name -eq $expected -and
                [IdFillFixture]::ReadId($handle) -eq $expectedId
        } "$scenario result"

        $client.Refresh()
        if ($client.MainWindowTitle -ne 'Fixture ready') { throw 'Password changed or login was activated.' }
        if ((Find-Control $settings 'VerificationState').Current.Name -ne '확인 전') {
            throw 'Filling the ID marked authentication as verified.'
        }
        Close-App $client
        $client = $null
    }
} finally {
    Close-App $client
    Close-App $app
    foreach ($file in $accountPath, $fixture) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
    Remove-Item -LiteralPath $work
}

Write-Output 'Passed 4 PClient ID-fill cases.'
