$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UiTestHelpers.ps1')

$exe = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../src/NetAuth/bin/Debug/net10.0-windows/NetAuth.exe')).Path
if (Get-Process -Name NetAuth -ErrorAction SilentlyContinue) {
    throw 'Close NetAuth before the tray test.'
}

$app = Open-App $exe '--start-in-tray'
try {
    if (-not $app.WaitForInputIdle(5000) -or $app.HasExited -or $app.MainWindowHandle -ne [IntPtr]::Zero) {
        throw 'Starting in the tray must leave NetAuth running with its settings hidden.'
    }

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $launcher = Open-App $exe ''
        try {
            if (-not $launcher.WaitForExit(5000) -or $launcher.ExitCode -ne 0) {
                throw 'Launching NetAuth again must use the running instance.'
            }
        } finally {
            Close-App $launcher
        }

        Wait-For { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'Settings opened in original instance'
        $window = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
        Wait-For { $null -ne (Find-Control $window 'CloseWindow') } 'Settings close button is available'
        $close = Find-Control $window 'CloseWindow'
        $close.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Wait-For { $app.Refresh(); -not $app.HasExited -and $app.MainWindowHandle -eq [IntPtr]::Zero } 'Close hides settings and keeps NetAuth running'
    }
    Write-Output 'Passed tray-only startup, hide on close, and reopening the same instance.'
} finally {
    Close-App $app
}
