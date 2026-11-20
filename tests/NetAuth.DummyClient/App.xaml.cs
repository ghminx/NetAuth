using System.Windows;

namespace NetAuth.DummyClient;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var scenario = Scenario.Success;

        if (e.Args.Length > 0 &&
            (e.Args.Length != 1 ||
             !Enum.TryParse(e.Args[0], ignoreCase: true, out scenario) ||
             !Enum.IsDefined(scenario)))
        {
            MessageBox.Show(string.Join(", ", Enum.GetNames<Scenario>()), "사용 가능한 테스트 시나리오");
            Shutdown(2);
            return;
        }

        MainWindow = new LoginWindow(scenario);
        MainWindow.Show();
    }
}

internal enum Scenario
{
    Success,
    AlreadyAuthenticated,
    Rejected,
    Delayed,
    ConnectionError,
    AdditionalVerification,
    MissingControl
}
