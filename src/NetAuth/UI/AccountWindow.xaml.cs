using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Media;
using NetAuth.PClient;
using NetAuth.Security;

namespace NetAuth.UI;

public partial class AccountWindow : Window
{
    private readonly CredentialStore store;
    private readonly bool useDummyAccount;
    private string? registeredId;

    internal AccountWindow(bool useDummyAccount)
    {
        InitializeComponent();
        this.useDummyAccount = useDummyAccount;
        store = new CredentialStore(useDummyAccount);

        DummyLogin.Visibility = useDummyAccount ? Visibility.Visible : Visibility.Collapsed;

        try
        {
            ShowOverview(store.Load()?.UserId);
            if (registeredId is null)
            {
                ShowEditor();
                Loaded += (_, _) => AccountId.Focus();
            }
        }
        catch (Exception error) when (IsStorageError(error))
        {
            ShowOverview(null);
            RegisterButton.IsEnabled = false;
            Heading.Text = "저장소 확인 필요";
            ShowFeedback("저장된 계정을 읽을 수 없습니다. Windows 사용자와 폴더 권한을 확인한 뒤 다시 실행하세요.", isError: true);
        }
    }

    private void ShowOverview(string? userId)
    {
        registeredId = userId;
        var hasAccount = userId is not null;
        Heading.Text = hasAccount ? "계정 관리" : "계정 설정";
        Description.Text = hasAccount
            ? "PClient 비밀번호가 바뀌면 저장된 계정을 업데이트하세요."
            : "등록한 계정이 없습니다.";
        Editor.Visibility = Visibility.Collapsed;
        RegisterButton.Visibility = hasAccount ? Visibility.Collapsed : Visibility.Visible;
        SavedActions.Visibility = hasAccount ? Visibility.Visible : Visibility.Collapsed;
        DeleteConfirmation.Visibility = Visibility.Collapsed;
        SavedAccountId.Text = userId ?? string.Empty;
        AccountId.Clear();
        AccountPassword.Clear();
    }

    private void ShowEditor()
    {
        Heading.Text = registeredId is null ? "계정 등록" : "계정 변경";
        Description.Text = useDummyAccount
            ? "사용할 ID와 비밀번호를 입력하세요."
            : "창원대 PClient에 사용하는 ID와 비밀번호를 입력하세요.";
        Editor.Visibility = Visibility.Visible;
        RegisterButton.Visibility = Visibility.Collapsed;
        SavedActions.Visibility = Visibility.Collapsed;
        DeleteConfirmation.Visibility = Visibility.Collapsed;
        CancelEditor.Content = registeredId is null ? "나중에" : "취소";
        AccountId.Text = registeredId ?? string.Empty;
        AccountPassword.Clear();
        ShowFeedback(string.Empty);
        (registeredId is null ? (UIElement)AccountId : AccountPassword).Focus();
    }

    private void Edit_Click(object sender, RoutedEventArgs e) => ShowEditor();

    private void Minimize_Click(object sender, RoutedEventArgs e) => SystemCommands.MinimizeWindow(this);

    private void ToggleMaximize_Click(object sender, RoutedEventArgs e)
    {
        if (WindowState == WindowState.Maximized)
        {
            SystemCommands.RestoreWindow(this);
        }
        else
        {
            SystemCommands.MaximizeWindow(this);
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => SystemCommands.CloseWindow(this);

    private void CancelEdit_Click(object sender, RoutedEventArgs e)
    {
        ShowOverview(registeredId);
        ShowFeedback("입력을 취소했습니다.");
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var userId = AccountId.Text.Trim();
        if (userId.Length == 0)
        {
            ShowFeedback("PClient ID를 입력하세요.", isError: true);
            AccountId.Focus();
            return;
        }

        var password = AccountPassword.Password;
        if (password.Length == 0)
        {
            ShowFeedback("비밀번호를 입력하세요.", isError: true);
            AccountPassword.Focus();
            return;
        }

        try
        {
            store.Save(new LoginAccount(userId, password));
            VerificationState.Text = "확인 전";
            ShowOverview(userId);
            ShowFeedback("계정을 이 PC에 저장했습니다.");
        }
        catch (Exception error) when (IsStorageError(error))
        {
            AccountPassword.Clear();
            AccountPassword.Focus();
            ShowFeedback("계정을 저장할 수 없습니다. 권한을 확인하고 비밀번호를 다시 입력하세요.", isError: true);
        }
    }

    private void ShowDelete_Click(object sender, RoutedEventArgs e)
    {
        DeleteConfirmation.Visibility = Visibility.Visible;
        ShowFeedback(string.Empty);
        ConfirmDelete.Focus();
    }

    private void CancelDelete_Click(object sender, RoutedEventArgs e)
    {
        DeleteConfirmation.Visibility = Visibility.Collapsed;
        DeleteAccount.Focus();
    }

    private void ConfirmDelete_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            store.Delete();
            VerificationState.Text = "확인 전";
            ShowOverview(null);
            RegisterButton.Focus();
            ShowFeedback("저장된 계정을 삭제했습니다.");
        }
        catch (Exception error) when (IsStorageError(error))
        {
            ShowFeedback("계정을 삭제할 수 없습니다. 폴더 권한을 확인하고 다시 시도하세요.", isError: true);
        }
    }

    private async void DummyLogin_Click(object sender, RoutedEventArgs e)
    {
        DeleteConfirmation.Visibility = Visibility.Collapsed;
        SavedActions.IsEnabled = false;
        VerificationState.Text = "확인 중";
        ShowFeedback("로그인 결과를 기다리는 중입니다.");
        try
        {
            var account = store.Load();
            if (account is null)
            {
                VerificationState.Text = "확인 전";
                ShowOverview(null);
                ShowFeedback("저장된 계정이 없습니다.", isError: true);
                return;
            }

            var state = await Task.Run(() => DummyClientProbe.Login(account.UserId, account.Password));
            VerificationState.Text = state switch
            {
                "Authenticated" => "인증 확인됨",
                "CredentialsRejected" => "계정 거부됨",
                _ => "미확인"
            };
            ShowFeedback(state switch
            {
                "Authenticated" => "인증 상태를 확인했습니다.",
                "CredentialsRejected" => "계정이 거부되었습니다. ID와 비밀번호를 확인하세요.",
                "WaitingForPClient" or "WaitingForWindow" => "대상 로그인 창을 먼저 열어 주세요.",
                "MultipleDummyClients" => "대상 창을 하나만 남기고 다시 시도하세요.",
                "ConnectionError" => "연결 오류가 발생했습니다.",
                "ManualActionRequired" => "추가 인증이 필요합니다.",
                _ => "로그인 결과를 확인할 수 없습니다."
            }, isError: state != "Authenticated");
        }
        catch (Exception error) when (IsStorageError(error) || error is InvalidOperationException or COMException)
        {
            VerificationState.Text = "미확인";
            ShowFeedback("로그인 확인 중 오류가 발생했습니다. 계정 설정과 대상 창을 확인하세요.", isError: true);
        }
        finally
        {
            SavedActions.IsEnabled = true;
        }
    }

    private void ShowFeedback(string message, bool isError = false)
    {
        Feedback.Text = message;
        Feedback.Foreground = (Brush)FindResource(isError ? "Danger" : "Muted");
        FeedbackPanel.Background = (Brush)FindResource(isError ? "DangerSurface" : "Rail");
        FeedbackPanel.Visibility = message.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        FrameworkElementAutomationPeer.CreatePeerForElement(Feedback)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }

    private static bool IsStorageError(Exception error) =>
        error is IOException or UnauthorizedAccessException or CryptographicException or JsonException;
}
