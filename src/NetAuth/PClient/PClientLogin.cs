using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;
using NetAuth.Security;

namespace NetAuth.PClient;

internal static class PClientLogin
{
    private const uint ButtonClick = 0x00F5;
    private const uint GetText = 0x000D;
    private const uint AbortIfHung = 0x0002;
    private const int LoginButtonId = 1029;

    public static bool HasVerifiedButtonId(Process process)
    {
        try
        {
            // 실제 5.16.0.93의 버튼 1029는 표시 문구와 네이티브 문구가 다를 수 있음
            return process.MainModule?.FileVersionInfo.FileVersion == "5.16.0.93";
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException or IOException)
        {
            return false;
        }
    }

    public static IntPtr FindButton(AutomationElement window, int processId, bool verifiedButtonId, bool requireEnabled = false)
    {
        var root = new IntPtr(window.Current.NativeWindowHandle);
        var button = PClientNativeWindow.FindUniqueChild(root, processId, LoginButtonId, "Button");
        if (button == IntPtr.Zero || (!verifiedButtonId && !HasLoginCaption(button)) ||
            !PClientNativeWindow.IsExpectedChild(root, button, processId, LoginButtonId, "Button") ||
            (requireEnabled && !PClientNativeWindow.IsWindowEnabled(button)))
        {
            return IntPtr.Zero;
        }

        return button;
    }

    private static bool HasLoginCaption(IntPtr button)
    {
        var caption = new StringBuilder(32);
        var received = ReadButtonText(button, GetText, new IntPtr(caption.Capacity), caption, AbortIfHung, 250, out _);
        return received != IntPtr.Zero && caption.ToString().Trim() is ("로그인" or "&로그인");
    }

    public static PClientAccountFillResult Submit(AutomationElement window, Process process, IntPtr button,
        string? expectedUserId, PClientExecutableIdentity? identity, bool verifiedButtonId, Func<bool>? isCurrent)
    {
        Process? reopened = null;
        try
        {
            var ready = Stopwatch.StartNew();
            while (!PClientNativeWindow.IsWindowEnabled(button) && ready.ElapsedMilliseconds < 600)
            {
                Thread.Sleep(50);
            }

            if (PClientWindowStatus.Read(window, process.Id) != PClientWindowState.LoggedOut ||
                FindButton(window, process.Id, verifiedButtonId, requireEnabled: true) != button)
            {
                return PClientAccountFillResult.LoginButtonNotConfirmed;
            }
            if (isCurrent?.Invoke() == false)
            {
                return PClientAccountFillResult.StartupNotCurrent;
            }

            // 시간 초과 후에도 버튼에서 메시지를 처리했을 수 있어 재호출 금지
            SendMessageTimeout(button, ButtonClick, IntPtr.Zero, IntPtr.Zero, AbortIfHung, 250, out _);

            var clock = Stopwatch.StartNew();
            var timeout = TimeSpan.FromSeconds(identity is null ? 8 : 12);
            var reopenAttempted = false;
            while (clock.Elapsed < timeout)
            {
                var state = ReadProcessState(process, expectedUserId);
                if (reopened is not null)
                {
                    var reopenedState = ReadProcessState(reopened, expectedUserId);
                    state = state == PClientWindowState.Missing ? reopenedState
                        : reopenedState == PClientWindowState.Missing ? state : PClientWindowState.Ambiguous;
                }

                switch (state)
                {
                    case PClientWindowState.Authenticated:
                        return PClientAccountFillResult.Authenticated;
                    case PClientWindowState.OtherAccountAuthenticated:
                        return PClientAccountFillResult.OtherAccountAuthenticated;
                    case PClientWindowState.CredentialsRejected:
                        return PClientAccountFillResult.CredentialsRejected;
                    case PClientWindowState.Missing when identity is not null && !reopenAttempted && clock.ElapsedMilliseconds >= 750:
                        // 창이 닫힌 뒤 명시적 성공 문구를 보기 위한 한 번의 재열기
                        reopenAttempted = true;
                        reopened = identity.Reopen();
                        break;
                }
                Thread.Sleep(100);
            }
        }
        catch (Exception error) when (error is ElementNotAvailableException or COMException or InvalidOperationException or
            Win32Exception or IOException or UnauthorizedAccessException)
        {
            return PClientAccountFillResult.UnknownState;
        }
        finally
        {
            reopened?.Dispose();
        }

        return PClientAccountFillResult.UnknownState;
    }

    private static PClientWindowState ReadProcessState(Process process, string? expectedUserId)
    {
        if (process.HasExited)
        {
            return PClientWindowState.Missing;
        }

        try
        {
            var condition = new PropertyCondition(AutomationElement.ProcessIdProperty, process.Id);
            var windows = AutomationElement.RootElement.FindAll(TreeScope.Children, condition)
                .Cast<AutomationElement>().Where(window => !window.Current.IsOffscreen).ToArray();

            if (windows.Length != 1)
            {
                return windows.Length == 0 ? PClientWindowState.Missing : PClientWindowState.Ambiguous;
            }

            var state = PClientWindowStatus.Read(windows[0], process.Id, expectedUserId);
            return state == PClientWindowState.Missing ? PClientWindowState.Other : state;
        }
        catch (ElementNotAvailableException)
        {
            return PClientWindowState.Other;
        }
    }

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    private static extern IntPtr ReadButtonText(IntPtr window, uint message, IntPtr capacity, StringBuilder caption,
        uint flags, uint timeoutMilliseconds, out IntPtr result);

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, IntPtr lParam,
        uint flags, uint timeoutMilliseconds, out IntPtr result);
}
