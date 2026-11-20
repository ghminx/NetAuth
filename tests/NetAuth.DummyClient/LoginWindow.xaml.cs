using System.Windows;

namespace NetAuth.DummyClient;

public partial class LoginWindow : Window
{
    private readonly Scenario scenario;
    private int submissions;

    internal LoginWindow(Scenario scenario)
    {
        InitializeComponent();
        this.scenario = scenario;
        ScenarioText.Text = scenario switch
        {
            Scenario.Success => "성공",
            Scenario.AlreadyAuthenticated => "이미 인증됨",
            Scenario.Rejected => "자격 증명 거부",
            Scenario.Delayed => "응답 지연",
            Scenario.NoResponse => "응답 없음",
            Scenario.ConnectionError => "연결 오류",
            Scenario.AdditionalVerification => "추가 인증",
            Scenario.MissingControl => "필수 컨트롤 누락",
            _ => throw new ArgumentOutOfRangeException(nameof(scenario))
        };

        if (scenario == Scenario.MissingControl)
        {
            Credentials.Children.Remove(PasswordRow);
            SubmitButton.IsEnabled = false;
        }
        else if (scenario is Scenario.AlreadyAuthenticated or Scenario.AdditionalVerification)
        {
            StatusText.Text = scenario == Scenario.AlreadyAuthenticated
                ? "인증되었습니다."
                : "추가 인증이 필요합니다.";
            Credentials.IsEnabled = false;
        }
    }

    private async void SignIn_Click(object sender, RoutedEventArgs e)
    {
        var validCredentials = UserId.Text == "demo-user" && Password.Password == "demo-pass";
        Password.Clear();
        SubmissionCount.Text = $"제출 횟수 {++submissions}회";
        Credentials.IsEnabled = false;

        if (scenario is Scenario.Delayed or Scenario.NoResponse)
        {
            StatusText.Text = "인증 결과를 기다리는 중입니다.";
            if (scenario == Scenario.NoResponse)
            {
                return;
            }
            await Task.Delay(TimeSpan.FromSeconds(3));
        }

        if (!validCredentials || scenario == Scenario.Rejected)
        {
            StatusText.Text = "테스트 자격 증명이 거부되었습니다.";
            Credentials.IsEnabled = true;
        }
        else if (scenario == Scenario.ConnectionError)
        {
            StatusText.Text = "일시적인 연결 오류입니다.";
            Credentials.IsEnabled = true;
        }
        else
        {
            StatusText.Text = "인증되었습니다.";
        }
    }
}
