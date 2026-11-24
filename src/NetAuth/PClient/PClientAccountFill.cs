using System.ComponentModel;
using System.Diagnostics;
using System.IO;
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
    StartupNotCurrent,
    Busy,
    LoginButtonNotConfirmed,
    LoginRequired,
    Authenticated,
    AlreadyAuthenticated,
    OtherAccountAuthenticated,
    CredentialsRejected,
    UnknownState
}

internal static class PClientAccountFill
{
    private const string PClientProcessName = "PClientUI";

    private enum Operation { Fill, Login, Observe, PreviewLogin }

    public static PClientExecutableIdentity? FindConnectedIdentity(PClientExecutableIdentity? knownIdentity)
    {
        using var current = Process.GetCurrentProcess();
        var processes = Process.GetProcessesByName(PClientProcessName);
        try
        {
            var candidates = processes.Where(process => process.SessionId == current.SessionId).ToArray();
            if (candidates.Length != 1)
            {
                return null;
            }

            return ConfirmIdentity(candidates[0], knownIdentity);
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }
    }

    private static PClientExecutableIdentity? ConfirmIdentity(Process candidate, PClientExecutableIdentity? knownIdentity)
    {
        if (knownIdentity?.Matches(candidate) == true)
        {
            return knownIdentity;
        }

        var path = candidate.MainModule?.FileName;
        if (path is null || !Path.IsPathFullyQualified(path) ||
            !string.Equals(Path.GetFileName(path), PClientExecutableIdentity.FileName, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var identity = PClientExecutableIdentity.FromSignedFile(path);
        return identity?.Matches(candidate) == true ? identity : null;
    }

    public static PClientAccountFillResult Fill(LoginAccount account) => Run(account, Operation.Fill);

    public static PClientAccountFillResult Login(LoginAccount account) => Run(account, Operation.Login);

    public static PClientAccountFillResult LoginAutomatically(LoginAccount account, Func<bool> isCurrent) =>
        Run(account, Operation.Login, isCurrent: isCurrent);

    public static (PClientAccountFillResult State, PClientExecutableIdentity? Identity) Observe(
        string? userId, PClientExecutableIdentity? knownIdentity)
    {
        using var current = Process.GetCurrentProcess();
        var identity = knownIdentity;
        var account = new LoginAccount(userId ?? string.Empty, string.Empty, knownIdentity);
        var state = RunOnce(current.SessionId, account, Operation.Observe, ref identity, isCurrent: null);
        return (state, identity);
    }

    public static PClientAccountFillResult LoginPreview(LoginAccount account) => Run(account, Operation.PreviewLogin);

    public static PClientAccountFillResult LoginPreviewAtLogon(LoginAccount account) =>
        Run(account, Operation.PreviewLogin, windowWait: TimeSpan.FromSeconds(30));

    private static PClientAccountFillResult Run(LoginAccount account, Operation operation, TimeSpan windowWait = default,
        Func<bool>? isCurrent = null)
    {
        if (operation is Operation.Fill or Operation.Login && account.ExecutableIdentity is null)
        {
            return PClientAccountFillResult.ExecutableNotRegistered;
        }

        var mutexName = operation == Operation.PreviewLogin ? @"Local\NetAuth.PClientPreview.Login" : @"Local\NetAuth.PClient.IdFill";
        using var request = new Mutex(false, mutexName, out var firstRequest);
        if (!firstRequest)
        {
            return PClientAccountFillResult.Busy;
        }

        using var current = Process.GetCurrentProcess();
        var clock = Stopwatch.StartNew();
        var identity = account.ExecutableIdentity;
        while (true)
        {
            var result = RunOnce(current.SessionId, account, operation, ref identity, isCurrent);
            if (result != PClientAccountFillResult.WindowNotFound || clock.Elapsed >= windowWait)
            {
                return result;
            }

            Thread.Sleep(250);
        }
    }

    private static PClientAccountFillResult RunOnce(int sessionId, LoginAccount account, Operation operation,
        ref PClientExecutableIdentity? identity, Func<bool>? isCurrent)
    {
        var processes = Process.GetProcessesByName(operation == Operation.PreviewLogin ? "NetAuth.PClientPreview" : PClientProcessName);
        try
        {
            var candidates = processes.Where(process => process.SessionId == sessionId).ToArray();
            if (candidates.Length != 1)
            {
                return candidates.Length == 0 ? PClientAccountFillResult.WindowNotFound : PClientAccountFillResult.AmbiguousWindow;
            }

            var process = candidates[0];
            return (operation is Operation.Fill or Operation.Login) && identity?.Matches(process) != true
                ? PClientAccountFillResult.ExecutableNotConfirmed
                : RunInPClientWindow(process, account, operation, ref identity, isCurrent);
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

    private static PClientAccountFillResult RunInPClientWindow(Process process, LoginAccount account, Operation operation,
        ref PClientExecutableIdentity? identity, Func<bool>? isCurrent)
    {
        var processId = process.Id;
        var tracksAuthentication = operation is Operation.Login or Operation.Observe;
        var expectedUserId = tracksAuthentication ? account.UserId : null;
        var submit = operation is Operation.Login or Operation.PreviewLogin;
        var processCondition = new PropertyCondition(AutomationElement.ProcessIdProperty, processId);
        var windows = AutomationElement.RootElement.FindAll(TreeScope.Children, processCondition);
        if (windows.Count == 0)
        {
            return PClientAccountFillResult.WindowNotFound;
        }

        var visibleWindows = windows.Cast<AutomationElement>().Where(window => !window.Current.IsOffscreen).ToArray();
        if (visibleWindows.Length == 0)
        {
            return PClientAccountFillResult.WindowNotFound;
        }
        if (operation == Operation.Observe)
        {
            if (visibleWindows.Length != 1)
            {
                return PClientAccountFillResult.AmbiguousWindow;
            }

            identity = ConfirmIdentity(process, identity);
            if (identity is null)
            {
                return PClientAccountFillResult.ExecutableNotConfirmed;
            }
        }
        var candidates = visibleWindows
            .Select(window => (Window: window, State: PClientWindowStatus.Read(window, processId, expectedUserId)))
            .ToArray();
        if (candidates.Any(candidate => candidate.State == PClientWindowState.Ambiguous))
        {
            return PClientAccountFillResult.LogoutNotConfirmed;
        }

        var loggedOut = candidates
            .Where(candidate => candidate.State == PClientWindowState.LoggedOut)
            .ToArray();
        if ((submit || operation == Operation.Observe) && candidates.Length == 1 && loggedOut.Length == 0)
        {
            return candidates[0].State switch
            {
                PClientWindowState.Authenticated => PClientAccountFillResult.AlreadyAuthenticated,
                PClientWindowState.OtherAccountAuthenticated => PClientAccountFillResult.OtherAccountAuthenticated,
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
        if (tracksAuthentication && candidates.Length != 1)
        {
            return PClientAccountFillResult.AmbiguousWindow;
        }
        if (operation == Operation.Observe)
        {
            return PClientAccountFillResult.LoginRequired;
        }

        var target = loggedOut[0].Window;
        var button = IntPtr.Zero;
        var verifiedButtonId = operation == Operation.Login && PClientLogin.HasVerifiedButtonId(process);
        if (submit)
        {
            button = PClientLogin.FindButton(target, processId, verifiedButtonId);
            if (button == IntPtr.Zero)
            {
                return PClientAccountFillResult.LoginButtonNotConfirmed;
            }
        }

        if (isCurrent?.Invoke() == false)
        {
            return PClientAccountFillResult.StartupNotCurrent;
        }

        var fill = FillFields(target, processId, account);
        if (!submit || fill != PClientAccountFillResult.Filled)
        {
            return fill;
        }

        return PClientLogin.Submit(target, process, button, expectedUserId,
            operation == Operation.Login ? identity : null, verifiedButtonId, isCurrent);
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
