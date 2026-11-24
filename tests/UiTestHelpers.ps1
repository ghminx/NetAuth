Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

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

function Read-AppOutput($Path, $Arguments) {
    $launch = [Diagnostics.ProcessStartInfo]::new($Path, $Arguments)
    $launch.UseShellExecute = $false
    $launch.RedirectStandardOutput = $true
    $process = [Diagnostics.Process]::Start($launch)
    try {
        $output = $process.StandardOutput.ReadToEnd().Trim()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "$Arguments failed (exit $($process.ExitCode))." }
        $output
    } finally {
        $process.Dispose()
    }
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

function Find-AppWindow($Process, $Id) {
    $element = [System.Windows.Automation.AutomationElement]
    $match = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new($element::ProcessIdProperty, $Process.Id),
        [System.Windows.Automation.PropertyCondition]::new($element::AutomationIdProperty, $Id))
    $element::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $match)
}
