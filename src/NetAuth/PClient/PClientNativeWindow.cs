using System.Runtime.InteropServices;
using System.Text;

namespace NetAuth.PClient;

internal static class PClientNativeWindow
{
    public static IntPtr FindUniqueChild(IntPtr root, int processId, int controlId, string className)
    {
        if (root == IntPtr.Zero || !IsOwnedBy(root, processId))
        {
            return IntPtr.Zero;
        }

        var match = IntPtr.Zero;
        EnumChildWindows(root, (child, _) =>
        {
            if (!IsExpectedChild(root, child, processId, controlId, className))
            {
                return true;
            }

            if (match != IntPtr.Zero)
            {
                match = IntPtr.Zero;
                return false;
            }

            match = child;
            return true;
        }, IntPtr.Zero);
        return match;
    }

    public static bool IsExpectedChild(IntPtr root, IntPtr child, int processId, int controlId, string className)
    {
        if (GetDlgCtrlID(child) != controlId || !IsChild(root, child) || !IsWindowVisible(child) ||
            !IsOwnedBy(child, processId))
        {
            return false;
        }

        var name = new StringBuilder(64);
        return GetClassName(child, name, name.Capacity) > 0 &&
            name.ToString().Equals(className, StringComparison.OrdinalIgnoreCase);
    }

    public static bool IsOwnedBy(IntPtr window, int processId) =>
        GetWindowThreadProcessId(window, out var owner) != 0 && owner == processId;

    private delegate bool WindowCallback(IntPtr window, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr parent, WindowCallback callback, IntPtr data);
    [DllImport("user32.dll")]
    private static extern bool IsChild(IntPtr parent, IntPtr child);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")]
    private static extern int GetDlgCtrlID(IntPtr window);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
}
