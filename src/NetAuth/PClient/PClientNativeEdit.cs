using System.Runtime.InteropServices;
using System.Text;

namespace NetAuth.PClient;

internal sealed class PClientNativeEdit(IntPtr root, int processId, int controlId, IntPtr handle)
{
    private const uint GetText = 0x000D;
    private const uint GetTextLength = 0x000E;
    private const uint GetSelection = 0x00B0;
    private const uint SetSelection = 0x00B1;
    private const uint ReplaceSelection = 0x00C2;
    private const uint GetPasswordCharacter = 0x00D2;
    private const uint GetTextLimit = 0x00D5;
    private const uint AbortIfHung = 0x0002;
    private const uint TimeoutMilliseconds = 250;
    private const int WindowStyleIndex = -16;
    private const int PasswordStyle = 0x0020;
    private const int ReadOnlyStyle = 0x0800;

    public static PClientNativeEdit? Find(IntPtr root, int processId, int controlId, bool masked)
    {
        var handle = PClientNativeWindow.FindUniqueChild(root, processId, controlId, "Edit");
        if (handle == IntPtr.Zero)
        {
            return null;
        }

        var edit = new PClientNativeEdit(root, processId, controlId, handle);
        return edit.IsMasked() == masked ? edit : null;
    }

    public int? ReadLength() => IsExpectedEdit() ? ReadNumber(GetTextLength) : null;

    public bool CanAccept(string value, bool masked) =>
        value.Length > 0 && value.Length < ushort.MaxValue &&
        value.IndexOfAny(['\0', '\r', '\n']) < 0 &&
        IsWritable(masked) && ReadNumber(GetTextLimit) is int limit && value.Length <= limit;

    public (string Text, int Selection)? ReadIdState()
    {
        var original = ReadIdText();
        var selection = ReadNumber(GetSelection);
        return original is not null && selection is not (null or -1) &&
            ReadNumber(GetTextLimit) is int limit && original.Length <= limit
            ? (original, selection.Value)
            : null;
    }

    public bool RestoreId(string original, int selection, string assigned)
    {
        var current = ReadIdText();
        return (current == original || current == assigned && ReplaceAndVerifyId(assigned, original)) &&
            SelectRange(selection & 0xFFFF, (int)((uint)selection >> 16));
    }

    public bool ReplaceAndVerifyId(string previous, string value)
    {
        if (ReadIdText() != previous || !IsWritable(masked: false) ||
            !SelectRange(0, previous.Length) || !IsWritable(masked: false))
        {
            return false;
        }

        return SendReplacement(handle, ReplaceSelection, IntPtr.Zero, value,
            AbortIfHung, TimeoutMilliseconds, out _) != IntPtr.Zero && ReadIdText() == value;
    }

    public PClientAccountFillResult FillEmptyPassword(string password)
    {
        if (!IsWritable(masked: true) || ReadLength() is not int length)
        {
            return PClientAccountFillResult.PasswordNotAccepted;
        }
        if (length != 0)
        {
            return PClientAccountFillResult.PasswordNotEmpty;
        }

        if (!SelectRange(0, 0) || !IsWritable(masked: true) || ReadLength() is not int lengthBeforeWrite)
        {
            return PClientAccountFillResult.PasswordNotAccepted;
        }
        if (lengthBeforeWrite != 0)
        {
            return PClientAccountFillResult.PasswordNotEmpty;
        }

        var delivered = SendReplacement(handle, ReplaceSelection, IntPtr.Zero, password,
            AbortIfHung, TimeoutMilliseconds, out _) != IntPtr.Zero;
        var writtenLength = ReadLength();
        // 운영 비밀번호의 원문을 읽지 않고 마스킹과 입력 길이로 확인
        if (delivered && IsWritable(masked: true) && writtenLength == password.Length)
        {
            return PClientAccountFillResult.Filled;
        }

        // 원문을 읽지 않으므로 실패 후 남은 문자의 소유권을 확인할 수 없어 입력란 보존
        return writtenLength == 0 ? PClientAccountFillResult.PasswordNotAccepted : PClientAccountFillResult.RestorationNotVerified;
    }

    private bool SelectRange(int start, int end) =>
        IsExpectedEdit() &&
        SendNumber(handle, SetSelection, new IntPtr(start), new IntPtr(end),
            AbortIfHung, TimeoutMilliseconds, out _) != IntPtr.Zero &&
        ReadNumber(GetSelection) == (start | (end << 16));

    private string? ReadIdText()
    {
        if (!IsWritable(masked: false) || ReadNumber(GetTextLength) is not int length ||
            length < 0 || length >= ushort.MaxValue - 1)
        {
            return null;
        }

        var buffer = new StringBuilder(length + 2);
        var delivered = ReadText(handle, GetText, new IntPtr(buffer.Capacity), buffer,
            AbortIfHung, TimeoutMilliseconds, out var copied);
        return delivered != IntPtr.Zero && copied.ToInt64() == buffer.Length &&
            ReadNumber(GetTextLength) == length ? buffer.ToString() : null;
    }

    private bool IsWritable(bool masked) =>
        IsExpectedEdit() && PClientNativeWindow.IsWindowEnabled(handle) &&
        (GetWindowLong(handle, WindowStyleIndex) & ReadOnlyStyle) == 0 && IsMasked() == masked;

    private bool? IsMasked() =>
        (GetWindowLong(handle, WindowStyleIndex) & PasswordStyle) != 0
            ? true
            : ReadNumber(GetPasswordCharacter) is int character ? character != 0 : null;

    private bool IsExpectedEdit() => PClientNativeWindow.IsExpectedChild(root, handle, processId, controlId, "Edit");

    private int? ReadNumber(uint message) =>
        SendNumber(handle, message, IntPtr.Zero, IntPtr.Zero, AbortIfHung,
            TimeoutMilliseconds, out var value) != IntPtr.Zero ? unchecked((int)value.ToInt64()) : null;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    private static extern IntPtr SendNumber(IntPtr window, uint message, IntPtr wParam, IntPtr lParam,
        uint flags, uint milliseconds, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendReplacement(IntPtr window, uint message, IntPtr wParam, string text,
        uint flags, uint milliseconds, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    private static extern IntPtr ReadText(IntPtr window, uint message, IntPtr wParam, StringBuilder text,
        uint flags, uint milliseconds, out IntPtr result);
}
