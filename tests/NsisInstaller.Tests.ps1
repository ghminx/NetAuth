param(
    [Parameter(Mandatory)] [string]$PreviousInstallerPath,
    [Parameter(Mandatory)] [string]$InstallerPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UiTestHelpers.ps1')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class SetupTestButton
{
    public static int Send(int handle, uint message)
    {
        IntPtr value;
        if (handle == 0 || SendMessageTimeout(new IntPtr(handle), message, IntPtr.Zero, IntPtr.Zero, 2, 2000,
            out value) == IntPtr.Zero)
            throw new InvalidOperationException("Setup button did not respond.");
        return value.ToInt32();
    }

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, IntPtr lParam,
        uint flags, uint timeout, out IntPtr result);
}
'@
$previousInstaller = (Resolve-Path -LiteralPath $PreviousInstallerPath).Path
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NetAuth'
$programs = [Environment]::GetFolderPath('Programs')
$shortcut = Join-Path $programs 'NetAuth.lnk'
$pendingShortcut = Join-Path $programs 'NetAuth.pending.lnk'
$removingShortcut = Join-Path $programs 'NetAuth.removing.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'NetAuth.lnk'
$removingDesktopShortcut = Join-Path (Split-Path -Parent $desktopShortcut) 'NetAuth.removing.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskName = "NetAuth PClient Preview Logon - $sid"

function Get-TestTask {
    Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue
}

if ((Get-TestTask) -or
    (Get-ItemProperty -LiteralPath $runKey -Name NetAuth -ErrorAction SilentlyContinue) -or
    (@($key, $shortcut, $pendingShortcut, $removingShortcut, $desktopShortcut, $removingDesktopShortcut, "$shortcut.netauth-backup" |
        Where-Object { Test-Path -LiteralPath $_ }).Count -ne 0)) {
    throw 'Use a Windows profile with no NetAuth installation, shortcuts or preview task.'
}

$artifacts = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../artifacts')).Path
$tag = [Guid]::NewGuid().ToString('N')
$installDirectory = Join-Path $artifacts "nsis-test-$tag"
$uninstallerCopy = Join-Path $artifacts "nsis-test-remove-$tag.exe"
$app = Join-Path $installDirectory 'NetAuth.exe'
$uninstaller = Join-Path $installDirectory 'Uninstall.exe'
$uninstallerBackup = "$uninstaller.netauth-backup"
$backups = @("$app.netauth-backup", "$uninstaller.netauth-backup", "$shortcut.netauth-backup")
$originalUninstallerAcl = $null

function Invoke-Setup($Path, $Arguments, $ExpectedExit, $Context) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
    try {
        Write-Output "$Context exit=$($process.ExitCode)"
        if ($process.ExitCode -ne $ExpectedExit) {
            throw "$Context expected exit $ExpectedExit."
        }
    } finally {
        $process.Dispose()
    }
}

function Get-Installation {
    $entry = Get-ItemProperty -LiteralPath $key
    $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($app).ProductVersion.Split('+')[0]
    if ($entry.InstallLocation -ne $installDirectory -or $entry.DisplayVersion -ne $version) {
        throw 'Install location or registered version does not match the installed app.'
    }
    (@($version) + @($app, $uninstaller, $shortcut | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash })) -join '|'
}

function Invoke-Removal($ExpectedExit, $Context) {
    Copy-Item -LiteralPath $uninstaller -Destination $uninstallerCopy -Force
    # NSIS 임시 제거 프로세스의 종료 코드 직접 확인
    Invoke-Setup $uninstallerCopy ('/S _?=' + $installDirectory) $ExpectedExit $Context
}

function Find-WizardControl($Window, $Pattern) {
    $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition) |
        Where-Object { $_.Current.ClassName -eq 'Button' -and $_.Current.IsEnabled -and -not $_.Current.IsOffscreen -and
            ($_.Current.Name -replace '&', '') -match $Pattern } | Select-Object -First 1
}

function Invoke-OptionsSetup([bool]$InitiallyChecked, [bool]$SelectOptions) {
    $setup = Open-App $installer "/D=$installDirectory"
    try {
        Wait-For { $setup.Refresh(); $setup.MainWindowHandle -ne [IntPtr]::Zero } 'Setup options wizard'
        $wizard = [System.Windows.Automation.AutomationElement]::FromHandle($setup.MainWindowHandle)
        $forward = '^(Next|다음|Install|설치)(\s|[<>]|$)'
        $buttonClick = 0x00F5
        $buttonGetCheck = 0x00F0
        Wait-For { $null -ne (Find-WizardControl $wizard $forward) } 'Setup welcome button'
        $null = [SetupTestButton]::Send((Find-WizardControl $wizard $forward).Current.NativeWindowHandle, $buttonClick)
        foreach ($label in '^(Start NetAuth when I sign in to Windows|Windows 로그인 시 NetAuth 실행)$',
            '^(Create a desktop shortcut|바탕 화면에 바로가기 만들기)$') {
            Wait-For { $null -ne (Find-WizardControl $wizard $label) } 'Installation option checkbox'
            $checkbox = (Find-WizardControl $wizard $label).Current.NativeWindowHandle
            if (([SetupTestButton]::Send($checkbox, $buttonGetCheck) -eq 1) -ne $InitiallyChecked) {
                throw "Unexpected default for $label."
            }
            if ($InitiallyChecked -ne $SelectOptions) { $null = [SetupTestButton]::Send($checkbox, $buttonClick) }
        }
        $null = [SetupTestButton]::Send((Find-WizardControl $wizard $forward).Current.NativeWindowHandle, $buttonClick)
        $finish = '^(Finish|마침|완료)(\s|$)'
        Wait-For { $null -ne (Find-WizardControl $wizard $finish) } 'Setup finish button' 25
        $null = [SetupTestButton]::Send((Find-WizardControl $wizard $finish).Current.NativeWindowHandle, $buttonClick)
        if (-not $setup.WaitForExit(5000) -or $setup.ExitCode -ne 0) { throw 'Options setup did not complete.' }
    } finally {
        Close-App $setup
    }
}

function Assert-Options([bool]$Selected, [bool]$AutomaticLogin = $false) {
    $startup = (Get-ItemProperty -LiteralPath $runKey -Name NetAuth -ErrorAction SilentlyContinue).NetAuth
    if (-not $Selected) {
        if ($startup -or (Test-Path -LiteralPath $desktopShortcut)) { throw 'Unexpected startup or desktop registration.' }
        return
    }
    $expected = '"' + $app + '" --start-in-tray'
    if ($AutomaticLogin) { $expected += ' --auto-login' }
    if ($startup -ne $expected -or -not (Test-Path -LiteralPath $desktopShortcut)) {
        throw 'Setup did not create the requested startup and desktop options.'
    }
    $shell = New-Object -ComObject WScript.Shell
    if ($shell.CreateShortcut($desktopShortcut).TargetPath -ne $app) {
        throw 'Desktop shortcut does not target the installed NetAuth.'
    }
}

try {
    Invoke-Setup $previousInstaller "/S /D=$installDirectory" 0 'Previous install'
    $previous = Get-Installation
    foreach ($file in $app, $uninstaller) {
        $lock = [IO.File]::Open($file, 'Open', 'Read', 'Read')
        try {
            Invoke-Setup $installer "/S /D=$installDirectory" 1 "Update with locked $([IO.Path]::GetFileName($file))"
        } finally {
            $lock.Dispose()
        }
        if ((Get-Installation) -ne $previous) { throw 'A failed update changed the previous installation.' }
    }

    Copy-Item -LiteralPath $uninstaller -Destination $uninstallerBackup
    Invoke-Setup $installer "/S /D=$installDirectory" 1 'Update with unconfirmed rollback backup'
    if ((Get-Installation) -ne $previous -or -not (Test-Path -LiteralPath $uninstallerBackup)) {
        throw 'Setup changed the previous installation or removed an unconfirmed backup.'
    }
    Remove-Item -LiteralPath $uninstallerBackup

    # 이름 변경은 허용하고 NSIS가 삭제 전에 읽기 전용 속성을 해제하는 동작만 차단
    $originalUninstallerAcl = Get-Acl -LiteralPath $uninstaller
    (Get-Item -LiteralPath $uninstaller).IsReadOnly = $true
    $restrictedAcl = Get-Acl -LiteralPath $uninstaller
    $denyAttributes = [Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new($sid), 'WriteAttributes', 'Deny')
    $restrictedAcl.AddAccessRule($denyAttributes)
    Set-Acl -LiteralPath $uninstaller -AclObject $restrictedAcl
    Invoke-Setup $installer "/S /D=$installDirectory" 1 'Update with blocked backup deletion after replacement'
    $updated = Get-Installation
    if ($updated -eq $previous -or -not (Test-Path -LiteralPath $uninstallerBackup)) {
        throw 'The replacement must be installed and its deferred backup preserved.'
    }
    Invoke-Setup $app '--check-ui-automation' 0 'Updated app before backup cleanup'
    Invoke-Setup $installer "/S /D=$installDirectory" 1 'Retry while backup deletion is blocked'
    Invoke-Removal 1 'Removal while backup deletion is blocked'
    if ((Get-Installation) -ne $updated) { throw 'Blocked cleanup changed the updated installation.' }
    Set-Acl -LiteralPath $uninstallerBackup -AclObject $originalUninstallerAcl
    (Get-Item -LiteralPath $uninstallerBackup).IsReadOnly = $false
    $originalUninstallerAcl = $null

    Invoke-Setup $installer "/S /D=$installDirectory" 0 'Update retry after releasing the backup'
    Assert-Options $false
    Invoke-OptionsSetup $false $true
    Assert-Options $true
    Set-ItemProperty -LiteralPath $runKey -Name NetAuth -Value ('"' + $app + '" --start-in-tray --auto-login')
    Invoke-OptionsSetup $true $true
    Assert-Options $true $true
    Invoke-OptionsSetup $true $false
    Assert-Options $false
    Invoke-OptionsSetup $false $true
    Set-ItemProperty -LiteralPath $runKey -Name NetAuth -Value ('"' + $app + '" --start-in-tray --auto-login')
    Assert-Options $true $true
    $ready = Get-Installation
    foreach ($file in $backups) {
        if (Test-Path -LiteralPath $file) { throw "A backup remains after a successful retry: $file" }
    }

    & (Join-Path $PSScriptRoot '../tools/Register-PClientPreviewStartup.ps1') -NetAuthPath $app | Out-Null
    $lock = [IO.File]::Open($shortcut, 'Open', 'Read', 'Read')
    try {
        Invoke-Removal 1 'Removal with a locked shortcut'
    } finally {
        $lock.Dispose()
    }
    if ((Get-Installation) -ne $ready -or -not (Get-TestTask)) {
        throw 'Blocked removal changed the installation or preview task.'
    }
    Assert-Options $true $true
    Invoke-Removal 0 'Removal retry after releasing the shortcut'
    Assert-Options $false
    if ((Get-TestTask) -or
        (@($key, $app, $uninstaller, $shortcut, $pendingShortcut, $removingShortcut |
            Where-Object { Test-Path -LiteralPath $_ }).Count -ne 0)) {
        throw 'The installer left app files, shortcuts, registration or a preview task after removal.'
    }
    Write-Output 'Passed interactive install options, prior selection, shortcut target, update recovery and removal retry.'
} catch {
    Write-Warning "Installer test failed: $($_.Exception.Message)"
    throw
} finally {
    $entry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if ($entry.InstallLocation -eq $installDirectory) {
        if ($null -ne $originalUninstallerAcl) {
            if (Test-Path -LiteralPath $uninstallerBackup) {
                Write-Output 'Found the deferred backup after the update.'
                Set-Acl -LiteralPath $uninstallerBackup -AclObject $originalUninstallerAcl
            } elseif (Test-Path -LiteralPath $uninstaller) {
                Set-Acl -LiteralPath $uninstaller -AclObject $originalUninstallerAcl
            }
        }
        # 검증용 경로에 이 테스트가 만든 백업만 정리
        foreach ($file in $backups) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
        if (Test-Path -LiteralPath $uninstaller) {
            (Get-Item -LiteralPath $uninstaller).IsReadOnly = $false
            Invoke-Removal 0 'Test installation cleanup'
        }
    }
    if (Test-Path -LiteralPath $uninstallerCopy) { Remove-Item -LiteralPath $uninstallerCopy }
}
