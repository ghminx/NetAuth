[CmdletBinding(DefaultParameterSetName = 'Register')]
param(
    [Parameter(ParameterSetName = 'Register')]
    [string]$NetAuthPath = (Join-Path $PSScriptRoot 'NetAuth.exe'),

    [Parameter(Mandatory, ParameterSetName = 'Remove')]
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$sid = $identity.User.Value
$user = $identity.Name
$taskName = "NetAuth PClient Preview Logon - $sid"
$taskPath = '\'

if ($Remove) {
    if (Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false
    }
    return
}

$exe = Get-Item -LiteralPath $NetAuthPath
if ($exe.PSIsContainer -or $exe.Name -ne 'NetAuth.exe') {
    throw 'Specify the path of the NetAuth.exe preview build.'
}

$action = New-ScheduledTaskAction -Execute $exe.FullName -WorkingDirectory $exe.DirectoryName `
    -Argument '--login-pclient-preview-at-logon'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Description 'NetAuth logon test using the local PClient preview only.' -Force
