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
    ExecutableNotRegistered,
    ExecutableNotConfirmed,
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
    public static PClientAccountFillResult Fill(LoginAccount account) => account.ExecutableIdentity is null
        ? PClientAccountFillResult.ExecutableNotRegistered
        : Run(account, submitPreview: false);

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
                1 when !submitPreview && account.ExecutableIdentity?.Matches(candidates[0]) != true =>
                    PClientAccountFillResult.ExecutableNotConfirmed,
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
        var windows = AutomationElement.RootElement.FindAll(TreeScope.Children, processCondition);
        if (windows.Count == 0)
        {
            return PClientAccountFillResult.WindowNotFound;
        }

        var candidates = windows.Cast<AutomationElement>()
            .Select(window => (Window: window, State: PClientWindowStatus.Read(window, processId)))
            .ToArray();
        if (candidates.Any(candidate => candidate.State == PClientWindowState.Ambiguous))
        {
            return PClientAccountFillResult.LogoutNotConfirmed;
        }

        var loggedOut = candidates
            .Where(candidate => candidate.State == PClientWindowState.LoggedOut)
            .ToArray();
        if (submitPreview && windows.Count == 1 && loggedOut.Length == 0)
        {
            return candidates[0].State switch
            {
                PClientWindowState.Authenticated => PClientAccountFillResult.AlreadyAuthenticated,
                PClientWindowState.Missing => PClientAccountFillResult.WindowNotFound,
                _ => PClientAccountFillResult.LogoutNotConfirmed
            };
        }
        if (loggedOut.Length != 1)
        {
            return loggedOut.Length == 0
                ? PClientAccountFillResult.LogoutNotConfirmed
                : PClientAccountFillResult.AmbiguousWindow;
        }

        var target = loggedOut[0].Window;
        var button = IntPtr.Zero;
        if (submitPreview)
        {
            button = PClientPreviewLogin.FindButton(target, processId);
            if (button == IntPtr.Zero)
            {
                return PClientAccountFillResult.LoginButtonNotConfirmed;
            }
        }

        var fill = FillFields(target, processId, account);
        return submitPreview && fill == PClientAccountFillResult.Filled
            ? PClientPreviewLogin.Submit(target, processId, button)
            : fill;
    }

    private static PClientAccountFillResult FillFields(AutomationElement target, int processId, LoginAccount account)
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
        var original = idField.ReadIdState();
        if (original is null || !idField.CanAccept(account.UserId, masked: false))
        {
            return PClientAccountFillResult.IdNotAccepted;
        }
        if (!passwordField.CanAccept(account.Password, masked: true))
        {
            return PClientAccountFillResult.PasswordNotAccepted;
        }
        if (PClientWindowStatus.Read(target, processId) != PClientWindowState.LoggedOut)
        {
            return PClientAccountFillResult.LogoutNotConfirmed;
        }

        var (originalId, selection) = original.Value;
        var idChanged = originalId != account.UserId;
        var result = PClientAccountFillResult.IdNotAccepted;
        if (!idChanged || idField.ReplaceAndVerifyId(originalId, account.UserId))
        {
            try
            {
                result = PClientWindowStatus.Read(target, processId) != PClientWindowState.LoggedOut
                    ? PClientAccountFillResult.LogoutNotConfirmed
                    : passwordField.FillEmptyPassword(account.Password);
            }
            catch (Exception error) when (error is ElementNotAvailableException or InvalidOperationException or COMException)
            {
                result = PClientAccountFillResult.LogoutNotConfirmed;
            }
        }

        if (result != PClientAccountFillResult.Filled && idChanged && !idField.RestoreId(originalId, selection, account.UserId))
        {
            return PClientAccountFillResult.RestorationNotVerified;
        }
        return result;
    }
}
