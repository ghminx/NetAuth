using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace NetAuth.PClient;

internal static class DummyClientProbe
{
    private const int UnexpectedAutomationError = unchecked((int)0x8000FFFF);
    public static string Read() => WithDummyWindow(ReadWindow);

    public static string Login(string accountId, string accountPassword)
    {
        // 요청이 끝날 때까지 유지하는 세션별 이름 있는 뮤텍스
        using var request = new Mutex(false, @"Local\NetAuth.DummyClient.Login", out var firstRequest);
        return firstRequest
            ? WithDummyWindow(window => LoginWindow(window, accountId, accountPassword))
            : "LoginInProgress";
    }

    private static string WithDummyWindow(Func<AutomationElement, string> operate)
    {
        var processes = Process.GetProcessesByName("NetAuth.DummyClient");
        try
        {
            if (processes.Length == 0)
            {
                return "WaitingForPClient";
            }

            if (processes.Length > 1)
            {
                return "MultipleDummyClients";
            }

            var process = processes[0];
            var handle = IntPtr.Zero;
            try
            {
                handle = process.MainWindowHandle;
                if (handle == IntPtr.Zero)
                {
                    return "WaitingForWindow";
                }

                var window = AutomationElement.FromHandle(handle);
                if (window.Current.ProcessId != processes[0].Id ||
                    window.Current.AutomationId != "NetAuthDummyLogin")
                {
                    return "UnrecognizedWindow";
                }

                return operate(window);
            }
            catch (ElementNotAvailableException)
            {
                return "UnknownState";
            }
            catch (COMException error) when (error.HResult == UnexpectedAutomationError &&
                (process.HasExited || handle != IntPtr.Zero && !IsWindow(handle)))
            {
                return "UnknownState";
            }
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }
    }

    private static string ReadWindow(AutomationElement window) =>
        Find(window, "AuthenticationStatus")?.Current.Name switch
        {
            "로그아웃 상태입니다." => ReadLoggedOut(window),
            "인증되었습니다." => "Authenticated",
            "인증 결과를 기다리는 중입니다." => "CheckingState",
            "테스트 자격 증명이 거부되었습니다." => "CredentialsRejected",
            "일시적인 연결 오류입니다." => "ConnectionError",
            "추가 인증이 필요합니다." => "ManualActionRequired",
            _ => "UnknownState"
        };

    private static string LoginWindow(AutomationElement window, string accountId, string accountPassword)
    {
        var state = ReadWindow(window);
        if (state != "LoginRequired")
        {
            return state;
        }

        var userId = Find(window, "UserId");
        var password = Find(window, "Password");
        var submit = Find(window, "SignIn");
        if (userId?.Current.IsEnabled != true || password?.Current.IsEnabled != true ||
            submit?.Current.IsEnabled != true ||
            !userId.TryGetCurrentPattern(ValuePattern.Pattern, out var idPattern) ||
            !password.TryGetCurrentPattern(ValuePattern.Pattern, out var passwordPattern) ||
            !submit.TryGetCurrentPattern(InvokePattern.Pattern, out var submitPattern))
        {
            return "UiMismatch";
        }

        ((ValuePattern)idPattern).SetValue(accountId);
        ((ValuePattern)passwordPattern).SetValue(accountPassword);
        ((InvokePattern)submitPattern).Invoke();

        var elapsed = Stopwatch.StartNew();
        while (elapsed.Elapsed < TimeSpan.FromSeconds(8))
        {
            state = ReadWindow(window);
            if (state is not ("LoginRequired" or "CheckingState"))
            {
                return state == "UiMismatch" ? "UnknownState" : state;
            }
            Thread.Sleep(100);
        }

        return "UnknownState";
    }

    private static string ReadLoggedOut(AutomationElement window)
    {
        var userId = Find(window, "UserId");
        var password = Find(window, "Password");
        var submit = Find(window, "SignIn");

        return userId?.Current.ControlType == ControlType.Edit &&
               password?.Current.IsPassword == true &&
               submit?.Current.ControlType == ControlType.Button
            ? "LoginRequired"
            : "UiMismatch";
    }

    private static AutomationElement? Find(AutomationElement window, string id) =>
        window.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.AutomationIdProperty, id));

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr window);
}
