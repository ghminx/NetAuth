using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Media;
using Microsoft.Win32;
using NetAuth.PClient;
using NetAuth.Security;

namespace NetAuth.UI;

internal enum AccountWindowMode
{
    PClient,
    Dummy,
    PClientPreview
}

public partial class AccountWindow : Window
{
    private readonly CredentialStore store;
    private readonly AccountWindowMode mode;
    private string? registeredId;
    private string? registeredExecutablePath;
    private bool refreshingAutomaticLogin;

    internal AccountWindow(AccountWindowMode mode)
    {
        InitializeComponent();
        this.mode = mode;
        var usesTestAccount = mode != AccountWindowMode.PClient;
        store = new CredentialStore(usesTestAccount);

        DummyLogin.Visibility = usesTestAccount ? Visibility.Visible : Visibility.Collapsed;
        FillPClientAccountButton.Visibility = usesTestAccount ? Visibility.Collapsed : Visibility.Visible;
        ExecutableRegistration.Visibility = usesTestAccount ? Visibility.Collapsed : Visibility.Visible;
        AutomaticLoginSetting.Visibility = mode == AccountWindowMode.Dummy ? Visibility.Collapsed : Visibility.Visible;
        if (mode == AccountWindowMode.PClientPreview)
        {
            Title = "NetAuth · PClient 로그인 검증";
            DummyLogin.Content = "로그인 검증";
        }

        try
        {
            var account = store.Load();
            registeredExecutablePath = account?.ExecutableIdentity?.Path;
            ShowOverview(account?.UserId);
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
        RefreshAutomaticLogin();
    }

    private void RefreshAutomaticLogin()
    {
        refreshingAutomaticLogin = true;
        AutoLoginAtLogon.IsEnabled = false;
        try
        {
            if (mode != AccountWindowMode.PClientPreview || registeredId is null)
            {
                AutoLoginAtLogon.IsChecked = false;
                AutoLoginDescription.Text = "실제 PClient의 로그인 결과를 확인한 뒤 사용할 수 있습니다.";
                return;
            }

            var startup = PClientPreviewStartup.ReadState();
            AutoLoginAtLogon.IsChecked = startup == PClientPreviewStartupState.EnabledHere;
            AutoLoginAtLogon.IsEnabled = true;
            AutoLoginDescription.Text = startup == PClientPreviewStartupState.EnabledElsewhere
                ? "다른 NetAuth 경로에 등록되어 있습니다. 여기서 켜면 실행 위치를 변경합니다."
                : "Windows 로그인 시 테스트용 PClient를 찾아 로그인을 한 번 시도합니다.";
        }
        catch (Exception error) when (PClientPreviewStartup.IsOperationError(error))
        {
            AutoLoginAtLogon.IsChecked = null;
            AutoLoginDescription.Text = "Windows 시작 작업 상태를 읽을 수 없습니다.";
        }
        finally
        {
            refreshingAutomaticLogin = false;
        }
    }

    private void AutoLoginAtLogon_Changed(object sender, RoutedEventArgs e)
    {
        if (refreshingAutomaticLogin || mode != AccountWindowMode.PClientPreview || registeredId is null)
        {
            return;
        }

        try
        {
            if (AutoLoginAtLogon.IsChecked == true)
            {
                PClientPreviewStartup.Enable();
                RefreshAutomaticLogin();
                ShowFeedback("Windows 로그인 시 자동으로 실행되도록 등록했습니다.");
            }
            else
            {
                var removed = PClientPreviewStartup.Disable();
                RefreshAutomaticLogin();
                ShowFeedback(removed ? "Windows 로그인 시 실행 등록을 해제했습니다."
                    : "다른 NetAuth 경로에 등록된 시작 작업은 유지했습니다.");
            }
        }
        catch (Exception error) when (PClientPreviewStartup.IsOperationError(error))
        {
            RefreshAutomaticLogin();
            ShowFeedback("Windows 시작 작업을 변경할 수 없습니다. 작업 스케줄러 상태를 확인하세요.", isError: true);
        }
    }

    private void ShowEditor()
    {
        Heading.Text = registeredId is null ? "계정 등록" : "계정 변경";
        Description.Text = mode switch
        {
            AccountWindowMode.PClient => "창원대 PClient에 사용하는 ID와 비밀번호를 입력하세요.",
            AccountWindowMode.PClientPreview => "검증 창에서 사용할 가상 ID와 비밀번호를 입력하세요.",
            _ => "사용할 ID와 비밀번호를 입력하세요."
        };
        Editor.Visibility = Visibility.Visible;
        RegisterButton.Visibility = Visibility.Collapsed;
        SavedActions.Visibility = Visibility.Collapsed;
        DeleteConfirmation.Visibility = Visibility.Collapsed;
        CancelEditor.Content = registeredId is null ? "나중에" : "취소";
        AccountId.Text = registeredId ?? string.Empty;
        PClientExecutablePath.Text = registeredExecutablePath ?? string.Empty;
        AccountPassword.Clear();
        ShowFeedback(string.Empty);
        (registeredId is null ? (UIElement)AccountId : AccountPassword).Focus();
    }

    private void Edit_Click(object sender, RoutedEventArgs e) => ShowEditor();

    private void BrowseExecutable_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "설치한 PClient 실행 파일 선택",
            Filter = "PClient 실행 파일 (PClientUI.exe)|PClientUI.exe"
        };
        if (dialog.ShowDialog(this) == true)
        {
            PClientExecutablePath.Text = dialog.FileName;
        }
    }

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

        PClientExecutableIdentity? executableIdentity = null;
        if (mode == AccountWindowMode.PClient && !string.IsNullOrWhiteSpace(PClientExecutablePath.Text))
        {
            try
            {
                executableIdentity = PClientExecutableIdentity.FromFile(PClientExecutablePath.Text.Trim());
            }
            catch (Exception error) when (IsStorageError(error) || error is ArgumentException or NotSupportedException)
            {
                ShowFeedback("설치한 PClientUI.exe의 전체 경로와 파일 읽기 권한을 확인하세요.", isError: true);
                PClientExecutablePath.Focus();
                return;
            }
        }

        try
        {
            store.Save(new LoginAccount(userId, password, executableIdentity));
            registeredExecutablePath = executableIdentity?.Path;
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
        var startupRemoved = true;
        if (mode == AccountWindowMode.PClientPreview)
        {
            try
            {
                startupRemoved = PClientPreviewStartup.Disable();
            }
            catch (Exception error) when (PClientPreviewStartup.IsOperationError(error))
            {
                startupRemoved = false;
            }
        }

        try
        {
            store.Delete();
            registeredExecutablePath = null;
            VerificationState.Text = "확인 전";
            ShowOverview(null);
            RegisterButton.Focus();
            ShowFeedback(startupRemoved ? "저장된 계정을 삭제했습니다."
                : "저장된 계정은 삭제했습니다. Windows 시작 작업의 중지·해제 여부는 작업 스케줄러에서 확인하세요.",
                isError: !startupRemoved);
        }
        catch (Exception error) when (IsStorageError(error))
        {
            RefreshAutomaticLogin();
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

            var state = await Task.Run(() => mode == AccountWindowMode.PClientPreview
                ? PClientAccountFill.LoginPreview(account).ToString()
                : DummyClientProbe.Login(account.UserId, account.Password));
            VerificationState.Text = state switch
            {
                "Authenticated" or "AlreadyAuthenticated" => "인증 확인됨",
                "CredentialsRejected" => "계정 거부됨",
                _ => "미확인"
            };
            ShowFeedback(state switch
            {
                "Authenticated" => "인증 상태를 확인했습니다.",
                "AlreadyAuthenticated" => "대상 창이 이미 인증된 상태입니다.",
                "CredentialsRejected" => "계정이 거부되었습니다. ID와 비밀번호를 확인하세요.",
                "WaitingForPClient" or "WaitingForWindow" or "WindowNotFound" => "대상 로그인 창을 먼저 열어 주세요.",
                "MultipleDummyClients" or "AmbiguousWindow" => "대상 창을 하나만 남기고 다시 시도하세요.",
                "LoginInProgress" or "Busy" => "다른 NetAuth 창에서 로그인 결과를 확인하는 중입니다.",
                "LogoutNotConfirmed" => "대상 창에서 로그아웃 상태를 확인할 수 없습니다.",
                "LoginButtonNotConfirmed" => "대상 창의 로그인 버튼을 확인할 수 없습니다.",
                "PasswordNotEmpty" => "대상 창의 비밀번호란을 비운 뒤 다시 시도하세요.",
                "ConnectionError" => "연결 오류가 발생했습니다.",
                "ManualActionRequired" => "추가 인증이 필요합니다.",
                _ => "로그인 결과를 확인할 수 없습니다."
            }, isError: state is not ("Authenticated" or "AlreadyAuthenticated"));
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

    private async void FillPClientAccount_Click(object sender, RoutedEventArgs e)
    {
        DeleteConfirmation.Visibility = Visibility.Collapsed;
        SavedActions.IsEnabled = false;
        ShowFeedback("PClient의 로그아웃 상태를 확인하는 중입니다.");
        try
        {
            var account = store.Load();
            if (account is null)
            {
                ShowOverview(null);
                ShowFeedback("저장된 계정이 없습니다.", isError: true);
                return;
            }

            var result = await Task.Run(() => PClientAccountFill.Fill(account));
            ShowFeedback(result switch
            {
                PClientAccountFillResult.Filled => "PClient에 ID와 비밀번호를 채웠습니다.",
                PClientAccountFillResult.WindowNotFound => "이 Windows 세션에서 PClient 로그인 창을 열어 주세요.",
                PClientAccountFillResult.AmbiguousWindow => "PClient 창을 하나만 남기고 다시 시도하세요.",
                PClientAccountFillResult.ExecutableNotRegistered => "계정 변경에서 설치한 PClientUI.exe를 지정해 주세요.",
                PClientAccountFillResult.ExecutableNotConfirmed => "실행 중인 PClient가 등록한 파일과 일치하지 않습니다. 설치 위치와 버전을 확인하세요.",
                PClientAccountFillResult.LogoutNotConfirmed => "PClient에서 로그아웃 상태를 확인할 수 없습니다.",
                PClientAccountFillResult.FieldsNotConfirmed => "PClient 로그인 입력란을 확인할 수 없습니다.",
                PClientAccountFillResult.PasswordNotEmpty => "PClient의 비밀번호란을 비운 뒤 다시 시도하세요.",
                PClientAccountFillResult.PasswordNotAccepted => "PClient에서 비밀번호 입력을 확인할 수 없습니다.",
                PClientAccountFillResult.RestorationNotVerified => "입력란 복구를 확인할 수 없습니다. PClient의 입력란을 확인하세요.",
                PClientAccountFillResult.Busy => "다른 NetAuth 창에서 계정을 채우는 중입니다.",
                _ => "PClient에서 저장된 ID가 입력됐는지 확인할 수 없습니다."
            }, isError: result != PClientAccountFillResult.Filled);
        }
        catch (Exception error) when (IsStorageError(error) || error is InvalidOperationException or COMException)
        {
            ShowFeedback("PClient에 계정을 채울 수 없습니다. 저장된 계정과 PClient 창을 확인하세요.", isError: true);
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
        error is IOException or UnauthorizedAccessException or CryptographicException or JsonException or InvalidDataException;

}
