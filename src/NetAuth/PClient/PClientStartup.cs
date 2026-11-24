using System.IO;
using System.Security;
using Microsoft.Win32;

namespace NetAuth.PClient;

internal enum PClientStartupState { Disabled, EnabledHere, RegisteredElsewhere }

internal static class PClientStartup
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "NetAuth";
    private static string TrayCommand => $"\"{Environment.ProcessPath}\" --start-in-tray";
    private static string LoginCommand => TrayCommand + " --auto-login";

    public static PClientStartupState ReadState()
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
        return ReadState(key);
    }

    public static bool Enable()
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
        if (ReadState(key) == PClientStartupState.RegisteredElsewhere)
        {
            return false;
        }

        key.SetValue(ValueName, LoginCommand, RegistryValueKind.String);
        return true;
    }

    public static bool Disable()
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath, writable: true);
        var state = ReadState(key);
        if (state == PClientStartupState.EnabledHere)
        {
            key!.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        return state != PClientStartupState.RegisteredElsewhere;
    }

    public static bool IsOperationError(Exception error) => error is SecurityException or UnauthorizedAccessException or IOException;

    private static PClientStartupState ReadState(RegistryKey? key)
    {
        var value = key?.GetValue(ValueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
        if (value is null || EqualsCommand(value, TrayCommand))
        {
            return PClientStartupState.Disabled;
        }

        return EqualsCommand(value, LoginCommand) ? PClientStartupState.EnabledHere : PClientStartupState.RegisteredElsewhere;
    }

    private static bool EqualsCommand(object value, string expected) =>
        value is string command && string.Equals(command, expected, StringComparison.OrdinalIgnoreCase);
}
