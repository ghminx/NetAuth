using System.Windows;
using System.Windows.Automation;
using NetAuth.PClient;
using NetAuth.Security;
using NetAuth.UI;

namespace NetAuth;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        switch (args)
        {
            case []:
                return OpenSettings(AccountWindowMode.PClient);
            case ["--settings-dummy"]:
                return OpenSettings(AccountWindowMode.Dummy);
            case ["--settings-pclient-preview"]:
                return OpenSettings(AccountWindowMode.PClientPreview);
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
                    "사용법: NetAuth [--settings-dummy | --settings-pclient-preview | --login-pclient-preview-at-logon | " +
                    "--remove-pclient-preview-startup | --probe-dummy | --login-dummy | --check-ui-automation]");
                return 2;
        }
    }

    private static int OpenSettings(AccountWindowMode mode) => new Application().Run(new AccountWindow(mode));

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
