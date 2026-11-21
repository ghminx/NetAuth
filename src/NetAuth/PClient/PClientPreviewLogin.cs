using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace NetAuth.PClient;

internal static class PClientPreviewLogin
{
    private const uint ButtonClick = 0x00F5;
    private const uint AbortIfHung = 0x0002;

    public static IntPtr FindButton(AutomationElement window, int processId)
    {
        var candidates = window.FindAll(TreeScope.Descendants, new AndCondition(
            new PropertyCondition(AutomationElement.ProcessIdProperty, processId),
            new PropertyCondition(AutomationElement.AutomationIdProperty, "1029"),
            new PropertyCondition(AutomationElement.ClassNameProperty, "Button"),
            new PropertyCondition(AutomationElement.NameProperty, "로그인"),
            new PropertyCondition(AutomationElement.IsEnabledProperty, true),
            new PropertyCondition(AutomationElement.IsOffscreenProperty, false)));

        return candidates.Count == 1 ? new IntPtr(candidates[0].Current.NativeWindowHandle) : IntPtr.Zero;
    }

    public static string? ReadStatus(AutomationElement window, int processId)
    {
        var statuses = window.FindAll(TreeScope.Descendants, new AndCondition(
            new PropertyCondition(AutomationElement.ProcessIdProperty, processId),
            new PropertyCondition(AutomationElement.AutomationIdProperty, "1013"),
            new PropertyCondition(AutomationElement.IsOffscreenProperty, false)));

        return statuses.Count == 1 ? statuses[0].Current.Name : null;
    }

    public static PClientAccountFillResult Submit(AutomationElement window, int processId,
        IntPtr button, Condition logoutCondition)
    {
        try
        {
            if (window.FindFirst(TreeScope.Descendants, logoutCondition) is null ||
                FindButton(window, processId) != button)
            {
                return PClientAccountFillResult.LoginButtonNotConfirmed;
            }

            // 시간 초과 후에도 버튼에서 메시지를 처리했을 수 있어 재호출 금지
            SendMessageTimeout(button, ButtonClick, IntPtr.Zero, IntPtr.Zero, AbortIfHung, 250, out _);

            var clock = Stopwatch.StartNew();
            while (clock.Elapsed < TimeSpan.FromSeconds(8))
            {
                switch (ReadStatus(window, processId))
                {
                    case "인증되었습니다.":
                        return PClientAccountFillResult.Authenticated;
                    case "테스트 자격 증명이 거부되었습니다.":
                        return PClientAccountFillResult.CredentialsRejected;
                }
                Thread.Sleep(100);
            }
        }
        catch (Exception error) when (error is ElementNotAvailableException or COMException or InvalidOperationException)
        {
            return PClientAccountFillResult.UnknownState;
        }

        return PClientAccountFillResult.UnknownState;
    }

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, IntPtr lParam,
        uint flags, uint timeoutMilliseconds, out IntPtr result);
}
