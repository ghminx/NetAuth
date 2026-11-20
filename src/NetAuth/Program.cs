using System.Windows.Automation;
using NetAuth.PClient;

if (args is ["--probe-dummy"])
{
    Console.WriteLine(DummyClientProbe.Read());
    return 0;
}

if (args.Length != 0)
{
    Console.Error.WriteLine("사용법: NetAuth [--probe-dummy]");
    return 2;
}

Console.WriteLine($"NetAuth | UI Automation: {typeof(AutomationElement).Assembly.GetName().Name}");
return 0;
