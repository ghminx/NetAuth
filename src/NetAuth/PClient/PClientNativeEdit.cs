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
        if (root == IntPtr.Zero || GetWindowThreadProcessId(root, out var owner) == 0 || owner != processId)
        {
            return null;
        }

        var matches = new List<PClientNativeEdit>();
        EnumChildWindows(root, (child, _) =>
        {
            var edit = new PClientNativeEdit(root, processId, controlId, child);
            if (edit.IsExpectedEdit())
            {
                matches.Add(edit);
            }
            return true;
        }, IntPtr.Zero);

        return matches.Count == 1 && matches[0].IsMasked() == masked ? matches[0] : null;
    }

    public int? ReadLength() => IsExpectedEdit() ? ReadNumber(GetTextLength) : null;

    public PClientIdFillResult FillId(string userId)
    {
        if (string.IsNullOrWhiteSpace(userId) || userId.IndexOfAny(['\0', '\r', '\n']) >= 0 ||
            userId.Length >= ushort.MaxValue)
        {
            return PClientIdFillResult.IdNotAccepted;
        }

        var original = ReadIdText();
        var selection = ReadNumber(GetSelection);
        var limit = ReadNumber(GetTextLimit);
        if (original is null || selection is null or -1 || limit is null ||
            original.Length > limit || userId.Length > limit)
        {
            return PClientIdFillResult.IdNotAccepted;
        }
        if (original == userId || ReplaceAndVerify(original, userId))
        {
            return PClientIdFillResult.Filled;
        }

        var current = ReadIdText();
        var restored = current is not null && (current == original || ReplaceAndVerify(current, original)) &&
            SelectRange(selection.Value & 0xFFFF, (int)((uint)selection.Value >> 16));
        return restored ? PClientIdFillResult.IdNotAccepted : PClientIdFillResult.RestorationNotVerified;
    }

    private bool ReplaceAndVerify(string previous, string value) =>
        IsWritableId() &&
        SelectRange(0, previous.Length) &&
        IsWritableId() &&
        SendReplacement(handle, ReplaceSelection, IntPtr.Zero, value,
            AbortIfHung, TimeoutMilliseconds, out _) != IntPtr.Zero &&
        ReadIdText() == value;

    private bool SelectRange(int start, int end) =>
        IsExpectedEdit() &&
        SendNumber(handle, SetSelection, new IntPtr(start), new IntPtr(end),
            AbortIfHung, TimeoutMilliseconds, out _) != IntPtr.Zero &&
        ReadNumber(GetSelection) == (start | (end << 16));

    private string? ReadIdText()
    {
        if (!IsWritableId() || ReadNumber(GetTextLength) is not int length ||
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

    private bool IsWritableId() =>
        controlId == 1024 && IsExpectedEdit() && IsWindowEnabled(handle) &&
        (GetWindowLong(handle, WindowStyleIndex) & ReadOnlyStyle) == 0 && IsMasked() == false;

    private bool? IsMasked() =>
        (GetWindowLong(handle, WindowStyleIndex) & PasswordStyle) != 0
            ? true
            : ReadNumber(GetPasswordCharacter) is int character ? character != 0 : null;

    private bool IsExpectedEdit()
    {
        if (GetDlgCtrlID(handle) != controlId || !IsChild(root, handle) || !IsWindowVisible(handle) ||
            GetWindowThreadProcessId(handle, out var owner) == 0 || owner != processId)
        {
            return false;
        }

        var name = new StringBuilder(64);
        return GetClassName(handle, name, name.Capacity) > 0 &&
            name.ToString().Equals("Edit", StringComparison.OrdinalIgnoreCase);
    }

    private int? ReadNumber(uint message) =>
        SendNumber(handle, message, IntPtr.Zero, IntPtr.Zero, AbortIfHung,
            TimeoutMilliseconds, out var value) != IntPtr.Zero ? unchecked((int)value.ToInt64()) : null;

    private delegate bool WindowCallback(IntPtr window, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr parent, WindowCallback callback, IntPtr data);
    [DllImport("user32.dll")]
    private static extern bool IsChild(IntPtr parent, IntPtr child);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    private static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr window);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
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
