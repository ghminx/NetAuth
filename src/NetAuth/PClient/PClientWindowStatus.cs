using System.Windows.Automation;

namespace NetAuth.PClient;

internal enum PClientWindowState
{
    Missing,
    Ambiguous,
    LoggedOut,
    Authenticated,
    CredentialsRejected,
    Other
}

internal static class PClientWindowStatus
{
    public static PClientWindowState Read(AutomationElement window, int processId)
    {
        var statuses = window.FindAll(TreeScope.Descendants, new AndCondition(
            new PropertyCondition(AutomationElement.ProcessIdProperty, processId),
            new PropertyCondition(AutomationElement.AutomationIdProperty, "1013"),
            new PropertyCondition(AutomationElement.IsOffscreenProperty, false)));

        return statuses.Count switch
        {
            0 => PClientWindowState.Missing,
            1 => statuses[0].Current.Name switch
            {
                "로그아웃 상태입니다." or "로그아웃 상태입니다" => PClientWindowState.LoggedOut,
                "인증되었습니다." => PClientWindowState.Authenticated,
                "테스트 자격 증명이 거부되었습니다." => PClientWindowState.CredentialsRejected,
                _ => PClientWindowState.Other
            },
            _ => PClientWindowState.Ambiguous
        };
    }
}
