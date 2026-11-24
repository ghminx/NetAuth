using System.Windows.Automation;

namespace NetAuth.PClient;

internal enum PClientWindowState
{
    Missing,
    Ambiguous,
    LoggedOut,
    Authenticated,
    OtherAccountAuthenticated,
    CredentialsRejected,
    Other
}

internal static class PClientWindowStatus
{
    private const string SignedInSuffix = " 님으로 로그인 상태입니다";

    public static PClientWindowState Read(AutomationElement window, int processId, string? expectedUserId = null)
    {
        var statuses = window.FindAll(TreeScope.Descendants, new AndCondition(
            new PropertyCondition(AutomationElement.ProcessIdProperty, processId),
            new PropertyCondition(AutomationElement.AutomationIdProperty, "1013"),
            new PropertyCondition(AutomationElement.IsOffscreenProperty, false)));

        return statuses.Count switch
        {
            0 => PClientWindowState.Missing,
            1 => ReadName(statuses[0].Current, expectedUserId),
            _ => PClientWindowState.Ambiguous
        };
    }

    private static PClientWindowState ReadName(AutomationElement.AutomationElementInformation status, string? expectedUserId)
    {
        if (status.IsPassword || status.ControlType == ControlType.Edit ||
            status.ClassName?.Contains("Edit", StringComparison.OrdinalIgnoreCase) == true)
        {
            return PClientWindowState.Other;
        }

        var name = status.Name?.Trim() ?? string.Empty;
        if (expectedUserId is not null)
        {
            var text = name.EndsWith('.') ? name[..^1] : name;
            if (text.EndsWith(SignedInSuffix, StringComparison.Ordinal))
            {
                var visibleId = text[..^SignedInSuffix.Length].TrimEnd();
                if (visibleId.Length != 0)
                {
                    return expectedUserId.Length == 0 || visibleId == expectedUserId
                        ? PClientWindowState.Authenticated : PClientWindowState.OtherAccountAuthenticated;
                }
            }
        }

        return name switch
        {
            "로그아웃 상태입니다." or "로그아웃 상태입니다" => PClientWindowState.LoggedOut,
            "인증되었습니다." when expectedUserId is null => PClientWindowState.Authenticated,
            "테스트 자격 증명이 거부되었습니다." when expectedUserId is null => PClientWindowState.CredentialsRejected,
            _ => PClientWindowState.Other
        };
    }
}
