using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using NetAuth.Security;

namespace NetAuth.PClient;

internal enum PClientAccountFillResult
{
    Filled,
    WindowNotFound,
    AmbiguousWindow,
    LogoutNotConfirmed,
    FieldsNotConfirmed,
    PasswordNotEmpty,
    IdNotAccepted,
    PasswordNotAccepted,
    RestorationNotVerified,
    Busy,
    LoginButtonNotConfirmed,
    Authenticated,
    AlreadyAuthenticated,
    CredentialsRejected,
    UnknownState
}

internal static class PClientAccountFill
{
    public static PClientAccountFillResult Fill(LoginAccount account) => Run(account, submitPreview: false);

    public static PClientAccountFillResult LoginPreview(LoginAccount account) => Run(account, submitPreview: true);

    public static PClientAccountFillResult LoginPreviewAtLogon(LoginAccount account) =>
        Run(account, submitPreview: true, windowWait: TimeSpan.FromSeconds(30));

    private static PClientAccountFillResult Run(LoginAccount account, bool submitPreview, TimeSpan windowWait = default)
    {
        var mutexName = submitPreview ? @"Local\NetAuth.PClientPreview.Login" : @"Local\NetAuth.PClient.IdFill";
        using var request = new Mutex(false, mutexName, out var firstRequest);
        if (!firstRequest)
        {
            return PClientAccountFillResult.Busy;
        }

        using var current = Process.GetCurrentProcess();
        var clock = Stopwatch.StartNew();
        while (true)
        {
            var result = RunOnce(current.SessionId, account, submitPreview);
            if (result != PClientAccountFillResult.WindowNotFound || clock.Elapsed >= windowWait)
            {
                return result;
            }

            Thread.Sleep(250);
        }
    }

    private static PClientAccountFillResult RunOnce(int sessionId, LoginAccount account, bool submitPreview)
    {
        var processes = Process.GetProcessesByName(submitPreview ? "NetAuth.PClientPreview" : "PClientUI");
        try
        {
            var candidates = processes.Where(process => process.SessionId == sessionId).ToArray();
            return candidates.Length switch
            {
                0 => PClientAccountFillResult.WindowNotFound,
                1 => RunInLoggedOutWindow(candidates[0].Id, account, submitPreview),
                _ => PClientAccountFillResult.AmbiguousWindow
            };
        }
        catch (ElementNotAvailableException)
        {
            return PClientAccountFillResult.LogoutNotConfirmed;
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }
    }

    private static PClientAccountFillResult RunInLoggedOutWindow(int processId, LoginAccount account, bool submitPreview)
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
            return PClientAccountFillResult.WindowNotFound;
        }

        var loggedOut = windows.Cast<AutomationElement>()
            .Where(window => window.FindFirst(TreeScope.Descendants, logoutCondition) is not null)
            .ToArray();
        if (submitPreview && windows.Count == 1 && loggedOut.Length == 0)
        {
            return PClientPreviewLogin.ReadStatus(windows[0], processId) switch
            {
                "인증되었습니다." => PClientAccountFillResult.AlreadyAuthenticated,
                null => PClientAccountFillResult.WindowNotFound,
                _ => PClientAccountFillResult.LogoutNotConfirmed
            };
        }
        if (loggedOut.Length != 1)
        {
            return loggedOut.Length == 0
                ? PClientAccountFillResult.LogoutNotConfirmed
                : PClientAccountFillResult.AmbiguousWindow;
        }

        var target = loggedOut[0];
        var button = IntPtr.Zero;
        if (submitPreview)
        {
            button = PClientPreviewLogin.FindButton(target, processId);
            if (button == IntPtr.Zero)
            {
                return PClientAccountFillResult.LoginButtonNotConfirmed;
            }
        }

        var fill = FillFields(target, processId, logoutCondition, account);
        return submitPreview && fill == PClientAccountFillResult.Filled
            ? PClientPreviewLogin.Submit(target, processId, button, logoutCondition)
            : fill;
    }

    private static PClientAccountFillResult FillFields(AutomationElement target, int processId,
        Condition logoutCondition, LoginAccount account)
    {
        var handle = new IntPtr(target.Current.NativeWindowHandle);
        var idField = PClientNativeEdit.Find(handle, processId, 1024, masked: false);
        var passwordField = PClientNativeEdit.Find(handle, processId, 1022, masked: true);
        if (idField is null || passwordField?.ReadLength() is not int passwordLength)
        {
            return PClientAccountFillResult.FieldsNotConfirmed;
        }
        if (passwordLength != 0)
        {
            return PClientAccountFillResult.PasswordNotEmpty;
        }
        if (target.FindFirst(TreeScope.Descendants, logoutCondition) is null)
        {
            return PClientAccountFillResult.LogoutNotConfirmed;
        }

        var original = idField.ReadIdState();
        if (original is null || !idField.CanAccept(account.UserId, masked: false))
        {
            return PClientAccountFillResult.IdNotAccepted;
        }
        if (!passwordField.CanAccept(account.Password, masked: true))
        {
            return PClientAccountFillResult.PasswordNotAccepted;
        }

        var (originalId, selection) = original.Value;
        var idChanged = originalId != account.UserId;
        var result = PClientAccountFillResult.IdNotAccepted;
        if (!idChanged || idField.ReplaceAndVerifyId(originalId, account.UserId))
        {
            try
            {
                result = target.FindFirst(TreeScope.Descendants, logoutCondition) is null
                    ? PClientAccountFillResult.LogoutNotConfirmed
                    : passwordField.FillEmptyPassword(account.Password);
            }
            catch (Exception error) when (error is ElementNotAvailableException or InvalidOperationException or COMException)
            {
                result = PClientAccountFillResult.LogoutNotConfirmed;
            }
        }

        if (result != PClientAccountFillResult.Filled && idChanged && !idField.RestoreId(originalId, selection))
        {
            return PClientAccountFillResult.RestorationNotVerified;
        }
        return result;
    }
}
