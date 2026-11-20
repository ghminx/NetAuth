using System.Windows;
using System.Windows.Automation;
using NetAuth.PClient;
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
            case ["--settings-dummy"]:
                return new Application().Run(new AccountWindow(useDummyAccount: args.Length == 1));
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
                Console.Error.WriteLine("사용법: NetAuth [--settings-dummy | --probe-dummy | --login-dummy | --check-ui-automation]");
                return 2;
        }
    }
}
