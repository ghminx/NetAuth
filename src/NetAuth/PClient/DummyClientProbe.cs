using System.Diagnostics;
using System.Windows.Automation;

namespace NetAuth.PClient;

internal static class DummyClientProbe
{
    public static string Read()
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

            try
            {
                var handle = processes[0].MainWindowHandle;
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

                return Find(window, "AuthenticationStatus")?.Current.Name switch
                {
                    "로그아웃 상태입니다." => ReadLoggedOut(window),
                    "인증되었습니다." => "Authenticated",
                    "인증 결과를 기다리는 중입니다." => "CheckingState",
                    "테스트 자격 증명이 거부되었습니다." => "CredentialsRejected",
                    "일시적인 연결 오류입니다." => "ConnectionError",
                    "추가 인증이 필요합니다." => "ManualActionRequired",
                    _ => "UnknownState"
                };
            }
            catch (ElementNotAvailableException)
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
}
