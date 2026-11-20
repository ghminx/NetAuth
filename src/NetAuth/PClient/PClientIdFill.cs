using System.Diagnostics;
using System.Windows.Automation;

namespace NetAuth.PClient;

internal enum PClientIdFillResult
{
    Filled,
    WindowNotFound,
    AmbiguousWindow,
    LogoutNotConfirmed,
    FieldsNotConfirmed,
    PasswordNotEmpty,
    IdNotAccepted,
    RestorationNotVerified,
    Busy
}

internal static class PClientIdFill
{
    public static PClientIdFillResult Fill(string userId)
    {
        using var request = new Mutex(false, @"Local\NetAuth.PClient.IdFill", out var firstRequest);
        if (!firstRequest)
        {
            return PClientIdFillResult.Busy;
        }

        using var current = Process.GetCurrentProcess();
        var processes = Process.GetProcessesByName("PClientUI");
        try
        {
            var candidates = processes.Where(process => process.SessionId == current.SessionId).ToArray();
            return candidates.Length switch
            {
                0 => PClientIdFillResult.WindowNotFound,
                1 => FillLoggedOutWindow(candidates[0].Id, userId),
                _ => PClientIdFillResult.AmbiguousWindow
            };
        }
        catch (ElementNotAvailableException)
        {
            return PClientIdFillResult.LogoutNotConfirmed;
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }
    }

    private static PClientIdFillResult FillLoggedOutWindow(int processId, string userId)
    {
        var processCondition = new PropertyCondition(AutomationElement.ProcessIdProperty, processId);
        var logoutCondition = new AndCondition(
            processCondition,
            new PropertyCondition(AutomationElement.AutomationIdProperty, "1013"),
            new PropertyCondition(AutomationElement.IsOffscreenProperty, false),
            new OrCondition(
                new PropertyCondition(AutomationElement.NameProperty, "로그아웃 상태입니다."),
                new PropertyCondition(AutomationElement.NameProperty, "로그아웃 상태입니다")));

        var windows = AutomationElement.RootElement.FindAll(TreeScope.Children, processCondition);
        if (windows.Count == 0)
        {
            return PClientIdFillResult.WindowNotFound;
        }

        var loggedOut = windows.Cast<AutomationElement>()
            .Where(window => window.FindFirst(TreeScope.Descendants, logoutCondition) is not null)
            .ToArray();
        if (loggedOut.Length != 1)
        {
            return loggedOut.Length == 0
                ? PClientIdFillResult.LogoutNotConfirmed
                : PClientIdFillResult.AmbiguousWindow;
        }

        var target = loggedOut[0];
        var handle = new IntPtr(target.Current.NativeWindowHandle);
        var idField = PClientNativeEdit.Find(handle, processId, 1024, masked: false);
        var passwordField = PClientNativeEdit.Find(handle, processId, 1022, masked: true);
        var passwordLength = passwordField?.ReadLength();
        if (idField is null || passwordLength is null)
        {
            return PClientIdFillResult.FieldsNotConfirmed;
        }
        if (passwordLength != 0)
        {
            return PClientIdFillResult.PasswordNotEmpty;
        }
        if (target.FindFirst(TreeScope.Descendants, logoutCondition) is null)
        {
            return PClientIdFillResult.LogoutNotConfirmed;
        }

        return idField.FillId(userId);
    }
}
