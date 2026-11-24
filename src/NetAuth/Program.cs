using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using NetAuth.PClient;
using NetAuth.Security;
using NetAuth.UI;

namespace NetAuth;

internal static class Program
{
    private const int StandardOutputHandle = -11;
    private const uint ParentProcess = uint.MaxValue;

    [STAThread]
    private static int Main(string[] args)
    {
        if (args is [] or ["--start-in-tray"] or ["--start-in-tray", "--auto-login"])
        {
            return AccountTray.Run(startHidden: args.Length != 0);
        }

        var mode = args switch
        {
            ["--settings-dummy"] => AccountWindowMode.Dummy,
            ["--settings-pclient-preview"] => AccountWindowMode.PClientPreview,
            _ => (AccountWindowMode?)null
        };
        if (mode is { } settingsMode)
        {
            return OpenSettings(settingsMode);
        }

        var output = GetStdHandle(StandardOutputHandle);
        if (output == IntPtr.Zero || output == new IntPtr(-1))
        {
            AttachConsole(ParentProcess);
        }

        switch (args)
        {
            case ["--login-pclient-preview-at-logon"]:
                return RunLogonPreview();
            case ["--remove-pclient-preview-startup"]:
                return RemovePreviewStartup();
            case ["--probe-dummy"]:
                Console.WriteLine(DummyClientProbe.Read());
                return 0;
            case ["--login-dummy"]:
                Console.WriteLine(DummyClientProbe.Login("demo-user", "demo-pass"));
                return 0;
            case ["--check-ui-automation"]:
                Console.WriteLine($"NetAuth | UI Automation: {typeof(AutomationElement).Assembly.GetName().Name}");
                return 0;
            default:
                Console.Error.WriteLine(
                    "사용법: NetAuth [--start-in-tray [--auto-login] | --settings-dummy | --settings-pclient-preview | --login-pclient-preview-at-logon | " +
                    "--remove-pclient-preview-startup | --probe-dummy | --login-dummy | --check-ui-automation]");
                return 2;
        }
    }

    private static int OpenSettings(AccountWindowMode mode) => new Application().Run(new AccountWindow(mode));

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetStdHandle(int standardHandle);

    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(uint processId);

    private static int RemovePreviewStartup()
    {
        try
        {
            PClientPreviewStartup.Disable();
            return 0;
        }
        catch (Exception error) when (PClientPreviewStartup.IsOperationError(error))
        {
            Console.Error.WriteLine("PreviewStartupRemovalFailed");
            return 7;
        }
    }

    private static int RunLogonPreview()
    {
        LoginAccount? account;
        try
        {
            account = new CredentialStore(useDummyAccount: true).Load();
        }
        catch (Exception error) when (CredentialStore.IsStorageError(error))
        {
            Console.Error.WriteLine("AccountStoreUnavailable");
            return 6;
        }

        if (account is null)
        {
            Console.WriteLine("AccountNotRegistered");
            return 3;
        }

        var result = PClientAccountFill.LoginPreviewAtLogon(account);
        Console.WriteLine(result);
        return result switch
        {
            PClientAccountFillResult.Authenticated or PClientAccountFillResult.AlreadyAuthenticated => 0,
            PClientAccountFillResult.WindowNotFound => 4,
            _ => 5
        };
    }
}
