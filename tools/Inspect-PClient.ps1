[CmdletBinding()]
param(
    [ValidateRange(1, 2147483647)]
    [int]$ProcessId,
    [switch]$AsJson,
    [switch]$CheckInput,
    [switch]$CheckAutoInput,
    [switch]$PreviewInput,
    [switch]$CheckIdReplacement
)

$ErrorActionPreference = 'Stop'
$isAutomaticCheck = $CheckAutoInput -or $PreviewInput -or $CheckIdReplacement
if (@($CheckInput, $CheckAutoInput, $PreviewInput, $CheckIdReplacement | Where-Object { $_ }).Count -gt 1) {
    throw '-CheckInput, -CheckAutoInput, -PreviewInput, -CheckIdReplacement 중 하나만 선택하세요.'
}

function New-NameCondition($Names) {
    $conditions = foreach ($name in $Names) {
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            $name,
            [System.Windows.Automation.PropertyConditionFlags]::IgnoreCase)
    }
    [System.Windows.Automation.OrCondition]::new(
        [System.Windows.Automation.Condition[]]$conditions)
}

function Get-ControlCandidates($Window, $WindowIndex, $TargetId, $LoginLabelCondition) {
    $descendants = [System.Windows.Automation.TreeScope]::Descendants
    $loginLabels = @{}
    foreach ($label in $Window.FindAll($descendants, $LoginLabelCondition)) {
        $loginLabels[($label.GetRuntimeId() -join ':')] = $true
    }
    $windowBounds = $Window.Current.BoundingRectangle

    foreach ($element in $Window.FindAll($descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        $info = $element.Current
        if ($info.ProcessId -ne $TargetId -or $info.IsOffscreen) {
            continue
        }

        $type = $info.ControlType.ProgrammaticName
        $id = $info.AutomationId
        $supportsValue = [bool]$element.GetCurrentPropertyValue(
            [System.Windows.Automation.AutomationElement]::IsValuePatternAvailableProperty)
        $supportsInvoke = [bool]$element.GetCurrentPropertyValue(
            [System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty)
        $hasLoginLabel = $loginLabels.ContainsKey(($element.GetRuntimeId() -join ':'))

        $role = if ($info.IsPassword) {
            'PasswordCandidate'
        } elseif ($hasLoginLabel -and
            ($supportsInvoke -or $type -in 'ControlType.Button', 'ControlType.Custom', 'ControlType.Pane')) {
            'LoginButtonCandidate'
        } elseif ($type -eq 'ControlType.Edit' -or $supportsValue) {
            'InputCandidate'
        } elseif ($type -eq 'ControlType.Button' -or $supportsInvoke) {
            'ButtonCandidate'
        } elseif ($hasLoginLabel) {
            'LoginLabelCandidate'
        } elseif (($type -in 'ControlType.Custom', 'ControlType.Pane') -and
            ($id -or $info.IsKeyboardFocusable)) {
            'CustomCandidate'
        } else {
            continue
        }

        $isReadOnly = $null
        if ($supportsValue) {
            $property = $element.GetCurrentPropertyValue(
                [System.Windows.Automation.ValuePattern]::IsReadOnlyProperty, $true)
            if ($property -is [bool]) {
                $isReadOnly = $property
            }
        }

        $bounds = $info.BoundingRectangle
        $position = if (-not $bounds.IsEmpty -and -not $windowBounds.IsEmpty) {
            [ordered]@{
                X = [int]($bounds.X - $windowBounds.X)
                Y = [int]($bounds.Y - $windowBounds.Y)
                Width = [int]$bounds.Width
                Height = [int]$bounds.Height
            }
        }

        # 입력값과 일반 접근성 이름을 제외한 컨트롤 메타데이터만 수집
        [pscustomobject][ordered]@{
            WindowIndex = $WindowIndex
            Role = $role
            AutomationId = $id
            ControlType = $type
            ClassName = $info.ClassName
            IsPassword = $info.IsPassword
            IsEnabled = $info.IsEnabled
            IsKeyboardFocusable = $info.IsKeyboardFocusable
            SupportsValuePattern = $supportsValue
            ValueIsReadOnly = $isReadOnly
            SupportsInvokePattern = $supportsInvoke
            BoundsInWindow = $position
        }
    }
}

function Wait-EditLength($Handle, $Baseline, [switch]$Restore) {
    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        if ([NetAuthEditDiagnostic]::HasFocus($Handle)) {
            $length = [NetAuthEditDiagnostic]::GetLength($Handle)
            if ($length -ge 0 -and (($Restore -and $length -eq $Baseline) -or
                (-not $Restore -and [Math]::Abs($length - $Baseline) -eq 1))) {
                return $length
            }
        }
        Start-Sleep -Milliseconds 120
    } while ($elapsed.Elapsed.TotalSeconds -lt 35)
}

function Read-EditCheck($Root, $TargetId, $AutomationId, [bool]$ExpectPassword) {
    $check = [ordered]@{
        AutomationId = "$AutomationId"
        ExpectedRole = if ($ExpectPassword) { 'Password' } else { 'UserId' }
        IsNativeEdit = $false
        IsMasked = $null
        IsReadOnly = $null
        InputObserved = $false
        OriginalLengthRestored = $null
        Reason = 'NativeEditNotFound'
    }
    $handles = @([NetAuthEditDiagnostic]::FindEdits($Root, $TargetId, $AutomationId))
    if ($handles.Count -ne 1) {
        if ($handles.Count -gt 1) { $check.Reason = 'MultipleNativeEdits' }
        return [pscustomobject]$check
    }

    $handle = $handles[0]
    $style = [NetAuthEditDiagnostic]::GetStyle($handle)
    $maskCharacter = [NetAuthEditDiagnostic]::GetMaskCharacter($handle)
    $passwordStyle = 0x20
    $readOnlyStyle = 0x800
    $check.IsNativeEdit = $true
    $check.IsMasked = if (($style -band $passwordStyle) -ne 0) { $true } elseif ($maskCharacter -ge 0) { $maskCharacter -ne 0 }
    $check.IsReadOnly = ($style -band $readOnlyStyle) -ne 0
    if ($null -eq $check.IsMasked -or $check.IsMasked -ne $ExpectPassword) {
        $check.Reason = 'MaskingDoesNotConfirmRole'
        return [pscustomobject]$check
    }
    if ($check.IsReadOnly -or -not [NetAuthEditDiagnostic]::IsEnabled($handle)) {
        $check.Reason = 'InputUnavailable'
        return [pscustomobject]$check
    }

    $baseline = [NetAuthEditDiagnostic]::GetLength($handle)
    if ($baseline -lt 0) {
        $check.Reason = 'LengthUnavailable'
        return [pscustomobject]$check
    }
    if (($ExpectPassword -or $PreviewInput) -and $baseline -ne 0) {
        $check.Reason = if ($ExpectPassword) { 'PasswordFieldNotEmpty' } else { 'UserIdFieldNotEmpty' }
        return [pscustomobject]$check
    }

    if ($isAutomaticCheck) {
        $testText = '0'
        $previewMilliseconds = 0
        if ($PreviewInput) {
            $testText = if ($ExpectPassword) { '04260819' } else { '00000000' }
            $previewMilliseconds = 5000
        }
        $edit = [NetAuthEditDiagnostic]::CheckRoundTrip(
            $Root, $TargetId, $AutomationId, $handle, $baseline, $testText, $previewMilliseconds)
        $check.InputObserved = $edit.InputObserved
        $check.OriginalLengthRestored = $edit.OriginalLengthRestored
        $check.OriginalSelectionRestored = $edit.OriginalSelectionRestored
        $check.Reason = $edit.Reason
        return [pscustomobject]$check
    }

    if ($ExpectPassword) {
        Write-Host '[PW] 35초 안에 아래쪽 비밀번호 입력란을 클릭하고 숫자 0을 한 글자만 입력하세요.'
    } else {
        Write-Host '[ID] 35초 안에 위쪽 입력란을 클릭하고 오른쪽 방향키(→)로 커서를 맨 끝까지 옮긴 뒤 숫자 0을 한 글자만 입력하세요.'
        Write-Host '입력란이 가득 찬 경우, 원래 글자를 알고 있을 때만 마지막 한 글자를 지우세요.'
    }

    $changedLength = Wait-EditLength $handle $baseline
    if ($null -eq $changedLength) {
        $check.Reason = 'NoInputChangeObserved'
        return [pscustomobject]$check
    }

    $check.InputObserved = $true
    if ($changedLength -gt $baseline) {
        Write-Host '→ 입력 변화를 확인했습니다. 같은 입력란에서 Backspace를 한 번 눌러 추가한 글자를 지우세요.'
    } else {
        Write-Host '→ 입력 변화를 확인했습니다. 같은 입력란에서 지운 글자를 다시 입력하세요.'
    }
    $check.OriginalLengthRestored = $null -ne (Wait-EditLength $handle $baseline -Restore)
    $check.Reason = if ($check.OriginalLengthRestored) { 'InputObservedAndLengthRestored' } else { 'RestorationNotObserved' }
    [pscustomobject]$check
}

function Test-IdReplacement($Window, $Root, $TargetId, $PasswordHandle, $StatusCondition) {
    $registeredId = Read-Host 'NetAuth에 등록한 ID를 입력하세요. 입력은 숨겨집니다' -AsSecureString
    try {
        if ($registeredId.Length -eq 0) {
            return [pscustomobject]@{ Reason = 'RegisteredIdMissing' }
        }

        $status = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $StatusCondition)
        if ($null -eq $status -or $status.Current.ProcessId -ne $TargetId -or
            $status.Current.AutomationId -ne '1013' -or $status.Current.IsOffscreen) {
            return [pscustomobject]@{ Reason = 'LogoutStateNotConfirmed' }
        }
        if ([NetAuthEditDiagnostic]::GetLength($PasswordHandle) -ne 0) {
            return [pscustomobject]@{ Reason = 'EmptyPasswordNotConfirmed' }
        }

        $idEdits = @([NetAuthEditDiagnostic]::FindEdits($Root, $TargetId, 1024))
        if ($idEdits.Count -ne 1) {
            return [pscustomobject]@{ Reason = 'UserIdFieldNotConfirmed' }
        }

        $buffer = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($registeredId)
        try {
            $id = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($buffer, $registeredId.Length)
            [NetAuthEditDiagnostic]::CheckIdReplacement($Root, $TargetId, $idEdits[0], $id)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($buffer)
        }
    } finally {
        $registeredId.Dispose()
    }
}

function Test-LoginEdits($Window, $TargetId, $StatusCondition) {
    $root = [IntPtr]$Window.Current.NativeWindowHandle
    if ($root -eq [IntPtr]::Zero) {
        return [pscustomobject]@{ Reason = 'NativeWindowNotFound'; Fields = @() }
    }

    if (-not ('NetAuthEditDiagnostic' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class NetAuthEditDiagnostic
{
    private const int StyleIndex = -16;
    private const uint GetTextMessage = 0x000D;
    private const uint GetTextLengthMessage = 0x000E;
    private const uint GetPasswordCharacterMessage = 0x00D2;
    private const uint GetTextLimitMessage = 0x00D5;
    private const uint GetSelectionMessage = 0x00B0;
    private const uint SetSelectionMessage = 0x00B1;
    private const uint ReplaceSelectionMessage = 0x00C2;
    private const uint AbortIfHung = 0x0002;

    public sealed class RoundTripResult
    {
        public bool InputObserved { get; set; }
        public bool? OriginalLengthRestored { get; set; }
        public bool? OriginalSelectionRestored { get; set; }
        public string Reason { get; set; }
    }

    public sealed class IdReplacementResult
    {
        public bool EmptyIdMatched { get; set; }
        public bool PrefilledIdMatched { get; set; }
        public bool? OriginalIdRestored { get; set; }
        public bool? OriginalSelectionRestored { get; set; }
        public string Reason { get; set; }
    }

    private delegate bool WindowCallback(IntPtr window, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public int Size, Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr parent, WindowCallback callback, IntPtr data);
    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "IsWindowEnabled")]
    public static extern bool IsEnabled(IntPtr window);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    private static extern bool IsChild(IntPtr parent, IntPtr child);
    [DllImport("user32.dll")]
    private static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wparam,
        IntPtr lparam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendTextMessageTimeout(IntPtr window, uint message, IntPtr wparam,
        string text, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    private static extern IntPtr ReadTextMessageTimeout(IntPtr window, uint message, IntPtr wparam,
        StringBuilder text, uint flags, uint timeout, out IntPtr result);

    public static IntPtr[] FindEdits(IntPtr parent, uint process, int id)
    {
        uint owner;
        if (GetWindowThreadProcessId(parent, out owner) == 0 || owner != process)
            return new IntPtr[0];

        var edits = new List<IntPtr>();
        EnumChildWindows(parent, delegate(IntPtr window, IntPtr data)
        {
            if (IsExpectedEdit(parent, process, id, window))
                edits.Add(window);
            return true;
        }, IntPtr.Zero);
        return edits.ToArray();
    }

    public static int GetStyle(IntPtr window) { return GetWindowLong(window, StyleIndex); }
    public static int GetLength(IntPtr window) { return ReadNumber(window, GetTextLengthMessage); }
    public static int GetMaskCharacter(IntPtr window) { return ReadNumber(window, GetPasswordCharacterMessage); }

    private static bool IsExpectedEdit(IntPtr root, uint process, int id, IntPtr window)
    {
        uint owner;
        if (GetDlgCtrlID(window) != id || !IsWindowVisible(window) || !IsChild(root, window) ||
            GetWindowThreadProcessId(window, out owner) == 0 || owner != process)
            return false;

        var name = new StringBuilder(64);
        GetClassName(window, name, name.Capacity);
        return name.ToString().Equals("Edit", StringComparison.OrdinalIgnoreCase);
    }

    public static IdReplacementResult CheckIdReplacement(IntPtr root, uint process, IntPtr window, string target)
    {
        var result = new IdReplacementResult();
        if (string.IsNullOrWhiteSpace(target) || target.IndexOfAny(new[] { '\0', '\r', '\n' }) >= 0)
        {
            result.Reason = "InvalidRegisteredId";
            return result;
        }
        if (!IsWritableId(root, process, window))
        {
            result.Reason = "UserIdFieldNotConfirmed";
            return result;
        }

        string original = ReadEditText(window);
        int originalSelection = ReadNumber(window, GetSelectionMessage);
        if (original == null || originalSelection == -1)
        {
            result.Reason = "OriginalIdOrSelectionUnavailable";
            return result;
        }
        int limit = ReadNumber(window, GetTextLimitMessage);
        if (limit < 1 || original.Length > limit || target.Length > limit || target.Length >= ushort.MaxValue - 1)
        {
            result.Reason = "InputLimitNotConfirmed";
            return result;
        }

        string differentId = new string('0', target.Length);
        if (differentId == target)
            differentId = new string('1', target.Length);

        string expected = original;
        try
        {
            result.EmptyIdMatched = WriteAndVerifyId(root, process, window, ref expected, string.Empty) &&
                WriteAndVerifyId(root, process, window, ref expected, target);
            result.PrefilledIdMatched = result.EmptyIdMatched &&
                WriteAndVerifyId(root, process, window, ref expected, differentId) &&
                WriteAndVerifyId(root, process, window, ref expected, target);
        }
        finally
        {
            result.OriginalIdRestored = WriteAndVerifyId(root, process, window, ref expected, original);
            if (result.OriginalIdRestored == true)
                result.OriginalSelectionRestored = SetSelection(window,
                    originalSelection & 0xFFFF, (int)((uint)originalSelection >> 16)) &&
                    ReadEditText(window) == original;
        }

        if (result.OriginalIdRestored != true || result.OriginalSelectionRestored != true)
            result.Reason = "RestorationNotVerified";
        else
            result.Reason = result.EmptyIdMatched && result.PrefilledIdMatched
                ? "BothCasesMatchedAndRestored" : "ReplacementNotVerified";
        return result;
    }

    private static bool IsWritableId(IntPtr root, uint process, IntPtr window)
    {
        const int PasswordOrReadOnly = 0x20 | 0x800;
        return IsExpectedEdit(root, process, 1024, window) && IsEnabled(window) &&
            (GetStyle(window) & PasswordOrReadOnly) == 0 && GetMaskCharacter(window) == 0;
    }

    private static bool WriteAndVerifyId(IntPtr root, uint process, IntPtr window, ref string expected, string text)
    {
        if (!MatchesWritableId(root, process, window, expected))
            return false;
        if (expected == text)
            return true;

        // 선택 범위를 지정하는 동안 변경된 입력도 보존
        if (!SetSelection(window, 0, expected.Length) || !MatchesWritableId(root, process, window, expected) ||
            !ReplaceSelection(window, text) || !MatchesWritableId(root, process, window, text))
            return false;

        expected = text;
        return true;
    }

    private static bool MatchesWritableId(IntPtr root, uint process, IntPtr window, string expected)
    {
        return IsWritableId(root, process, window) && ReadEditText(window) == expected;
    }

    private static string ReadEditText(IntPtr window)
    {
        int length = GetLength(window);
        if (length < 0 || length >= ushort.MaxValue - 1)
            return null;

        var buffer = new StringBuilder(length + 2);
        IntPtr count;
        if (ReadTextMessageTimeout(window, GetTextMessage, (IntPtr)buffer.Capacity, buffer,
            AbortIfHung, 250, out count) == IntPtr.Zero ||
            count.ToInt64() != buffer.Length || GetLength(window) != length)
            return null;

        return buffer.ToString();
    }

    public static RoundTripResult CheckRoundTrip(IntPtr root, uint process, int id, IntPtr window,
        int baseline, string testText, int previewMilliseconds)
    {
        var result = new RoundTripResult();
        int expectedLength = baseline + testText.Length;
        int limit = ReadNumber(window, GetTextLimitMessage);
        if (limit < 1 || expectedLength > limit)
        {
            result.Reason = limit < 1 ? "InputLimitUnknown" : "InputLimitReached";
            return result;
        }
        if (expectedLength >= ushort.MaxValue)
        {
            result.Reason = "SelectionOutOfRange";
            return result;
        }

        int originalSelection = ReadNumber(window, GetSelectionMessage);
        if (originalSelection == -1 || !IsExpectedEdit(root, process, id, window) ||
            GetLength(window) != baseline)
        {
            result.Reason = "FieldChangedBeforeInput";
            return result;
        }

        int restoredStart = originalSelection & 0xFFFF;
        int restoredEnd = (int)((uint)originalSelection >> 16);
        bool attemptedInsert = false;
        try
        {
            if (SetSelection(window, baseline, baseline) && GetLength(window) == baseline)
            {
                attemptedInsert = true;
                bool delivered = ReplaceSelection(window, testText);
                result.InputObserved = delivered && GetLength(window) == expectedLength;
                if (result.InputObserved && previewMilliseconds > 0)
                    System.Threading.Thread.Sleep(previewMilliseconds);
            }
        }
        finally
        {
            if (IsExpectedEdit(root, process, id, window))
            {
                int currentLength = GetLength(window);
                // 삽입한 범위 안에서 길이와 커서 위치가 일치할 때만 해당 범위 제거
                if (attemptedInsert && currentLength > baseline && currentLength <= expectedLength &&
                    ReadNumber(window, GetSelectionMessage) == PackSelection(currentLength, currentLength) &&
                    SetSelection(window, baseline, currentLength))
                {
                    ReplaceSelection(window, string.Empty);
                }

                result.OriginalLengthRestored = GetLength(window) == baseline;
                if (result.OriginalLengthRestored == true)
                    result.OriginalSelectionRestored = SetSelection(window, restoredStart, restoredEnd);
            }
        }

        if (result.OriginalLengthRestored != true || result.OriginalSelectionRestored != true)
            result.Reason = "RestorationNotVerified";
        else if (!attemptedInsert)
            result.Reason = "SelectionNotSet";
        else
            result.Reason = result.InputObserved ? "InputObservedAndRestored" : "NoInputChangeObserved";
        return result;
    }

    private static int PackSelection(int start, int end) { return start | (end << 16); }

    private static bool SetSelection(IntPtr window, int start, int end)
    {
        IntPtr ignored;
        return SendMessageTimeout(window, SetSelectionMessage, (IntPtr)start, (IntPtr)end,
            AbortIfHung, 250, out ignored) != IntPtr.Zero &&
            ReadNumber(window, GetSelectionMessage) == PackSelection(start, end);
    }

    private static bool ReplaceSelection(IntPtr window, string text)
    {
        IntPtr ignored;
        return SendTextMessageTimeout(window, ReplaceSelectionMessage, IntPtr.Zero, text,
            AbortIfHung, 250, out ignored) != IntPtr.Zero;
    }

    public static bool HasFocus(IntPtr window)
    {
        uint process;
        var thread = GetWindowThreadProcessId(window, out process);
        var info = new GuiThreadInfo { Size = Marshal.SizeOf(typeof(GuiThreadInfo)) };
        return thread != 0 && GetGUIThreadInfo(thread, ref info) && info.Focus == window;
    }

    private static int ReadNumber(IntPtr window, uint message)
    {
        IntPtr value;
        return SendMessageTimeout(window, message, IntPtr.Zero, IntPtr.Zero, AbortIfHung, 250, out value) == IntPtr.Zero
            ? -1 : unchecked((int)value.ToInt64());
    }
}
'@
    }

    if ($isAutomaticCheck) {
        $passwordEdits = @([NetAuthEditDiagnostic]::FindEdits($root, $TargetId, 1022))
        if ($passwordEdits.Count -ne 1) {
            return [pscustomobject]@{ Reason = 'PasswordFieldNotConfirmed'; Fields = @() }
        }
        $passwordLength = [NetAuthEditDiagnostic]::GetLength($passwordEdits[0])
        if ($passwordLength -ne 0) {
            $reason = if ($passwordLength -gt 0) { 'PasswordFieldNotEmpty' } else { 'PasswordLengthUnavailable' }
            return [pscustomobject]@{ Reason = $reason; Fields = @() }
        }
        if ($CheckIdReplacement) {
            return Test-IdReplacement $Window $root $TargetId $passwordEdits[0] $StatusCondition
        }
        if ($PreviewInput) {
            $idEdits = @([NetAuthEditDiagnostic]::FindEdits($root, $TargetId, 1024))
            if ($idEdits.Count -ne 1) {
                return [pscustomobject]@{ Reason = 'UserIdFieldNotConfirmed'; Fields = @() }
            }
            $idLength = [NetAuthEditDiagnostic]::GetLength($idEdits[0])
            if ($idLength -ne 0) {
                $reason = if ($idLength -gt 0) { 'UserIdFieldNotEmpty' } else { 'UserIdLengthUnavailable' }
                return [pscustomobject]@{ Reason = $reason; Fields = @() }
            }
        }
    } else {
        Write-Host 'PowerShell과 로그인 창을 나란히 두세요. Enter나 로그인 버튼을 사용하지 않습니다.'
    }
    $idCheck = Read-EditCheck $root $TargetId 1024 $false
    $fields = @($idCheck)
    if ($idCheck.Reason -eq 'RestorationNotVerified' -or
        (-not $isAutomaticCheck -and $idCheck.Reason -in 'NoInputChangeObserved', 'RestorationNotObserved') -or
        ($PreviewInput -and $idCheck.Reason -eq 'UserIdFieldNotEmpty')) {
        return [pscustomobject]@{ Reason = 'StoppedAfterId'; Fields = $fields }
    }
    $fields += Read-EditCheck $root $TargetId 1022 $true
    [pscustomobject]@{ Reason = 'Checked'; Fields = $fields }
}

function Get-Inspection($TargetId, $HasExplicitProcess) {
    $result = [ordered]@{
        ProcessId = $null
        ProcessName = $null
        State = 'UnknownState'
        Reason = 'ProcessNotFound'
        WindowCount = 0
        StatusName = $null
        AutomationId = $null
        ControlType = $null
        StatusWindowIndex = $null
        ScanInterrupted = $false
        ControlCandidates = @()
    }
    if ($CheckInput -or $isAutomaticCheck) {
        $result.InputCheck = [pscustomobject]@{ Reason = 'LogoutStateNotConfirmed'; Fields = @() }
    }

    $sessionId = (Get-Process -Id $PID).SessionId
    if ($HasExplicitProcess) {
        $result.ProcessId = $TargetId
        $target = Get-Process -Id $TargetId -ErrorAction SilentlyContinue
        if ($null -eq $target) {
            return [pscustomobject]$result
        }
        $result.ProcessName = $target.ProcessName
        if ($target.SessionId -ne $sessionId) {
            $result.Reason = 'DifferentSession'
            return [pscustomobject]$result
        }
    } else {
        $result.ProcessName = 'PClientUI'
        $targets = @(Get-Process -Name 'PClientUI' -ErrorAction SilentlyContinue |
            Where-Object SessionId -eq $sessionId)
        if ($targets.Count -eq 0) {
            $result.Reason = 'PClientUiNotInSession'
            return [pscustomobject]$result
        }
        if ($targets.Count -gt 1) {
            $result.Reason = 'MultiplePClientUiProcesses'
            return [pscustomobject]$result
        }
        $TargetId = $targets[0].Id
        $result.ProcessId = $TargetId
    }

    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

    $processCondition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $TargetId)
    $statusCondition = New-NameCondition @('로그아웃 상태입니다.', '로그아웃 상태입니다')
    $loginLabelCondition = New-NameCondition @('로그인', 'Login', 'Log in', 'Sign in')

    $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children, $processCondition)
    $result.WindowCount = $windows.Count
    if ($windows.Count -eq 0) {
        $result.Reason = 'WindowNotFound'
        return [pscustomobject]$result
    }

    $result.Reason = 'LogoutTextNotExposed'
    $result.ControlCandidates = @(
        $windowIndex = 0
        foreach ($window in $windows) {
            $windowIndex++
            try {
                if ($null -eq $result.StatusWindowIndex) {
                    $descendants = [System.Windows.Automation.TreeScope]::Descendants
                    foreach ($match in $window.FindAll($descendants, $statusCondition)) {
                        $status = $match.Current
                        if ($status.ProcessId -ne $TargetId -or $status.IsOffscreen -or $status.IsPassword) {
                            continue
                        }
                        $result.State = 'LoginRequired'
                        $result.Reason = 'VisibleLogoutText'
                        $result.StatusName = $status.Name
                        $result.AutomationId = $status.AutomationId
                        $result.ControlType = $status.ControlType.ProgrammaticName
                        $result.StatusWindowIndex = $windowIndex
                        break
                    }
                }

                Get-ControlCandidates $window $windowIndex $TargetId $loginLabelCondition
            } catch [System.Windows.Automation.ElementNotAvailableException] {
                $result.ScanInterrupted = $true
                if ($result.State -eq 'UnknownState') {
                    $result.Reason = 'WindowChanged'
                }
            }
        }
    )
    if ($isAutomaticCheck -and $result.State -eq 'LoginRequired' -and $result.AutomationId -ne '1013') {
        $result.InputCheck = [pscustomobject]@{ Reason = 'LogoutControlIdNotConfirmed'; Fields = @() }
    } elseif (($CheckInput -or $isAutomaticCheck) -and $result.State -eq 'LoginRequired') {
        $result.InputCheck = Test-LoginEdits ($windows[$result.StatusWindowIndex - 1]) $TargetId $statusCondition
    }
    [pscustomobject]$result
}

$inspection = Get-Inspection $ProcessId ($PSBoundParameters.ContainsKey('ProcessId'))
if ($AsJson) {
    $inspection | ConvertTo-Json -Depth 6
} else {
    $inspection
}
