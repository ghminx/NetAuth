using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Media;
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
    private enum AuthenticationStatus { Unknown, Checking, SignedOut, SignedIn, OtherAccount }

    private readonly CredentialStore store;
    private readonly AccountWindowMode mode;
    private string? registeredId;
    private PClientExecutableIdentity? knownExecutable;
    private bool refreshingAutomaticLogin;
    private bool checkingAuthentication;
    private bool attemptedCurrentLogout;
    private bool? lastConfirmedSignIn;
    private long resumeAutomaticLoginAt;

    internal event Action<bool>? AuthenticationChanged;

    internal AccountWindow(AccountWindowMode mode)
    {
        InitializeComponent();
        this.mode = mode;
        var usesTestAccount = mode != AccountWindowMode.PClient;
        store = new CredentialStore(usesTestAccount);

        DummyLogin.Visibility = usesTestAccount ? Visibility.Visible : Visibility.Collapsed;
        PClientStatusBadge.Visibility = usesTestAccount ? Visibility.Collapsed : Visibility.Visible;
        AutomaticLoginSetting.Visibility = mode == AccountWindowMode.Dummy ? Visibility.Collapsed : Visibility.Visible;
        if (mode == AccountWindowMode.PClientPreview)
        {
            Title = "NetAuth · PClient 로그인 검증";
            DummyLogin.Content = "로그인 검증";
        }

        try
        {
            var account = store.Load();
            knownExecutable = account?.ExecutableIdentity;
            ShowOverview(account?.UserId);
            if (account is null)
            {
                ShowEditor();
                Loaded += (_, _) => AccountId.Focus();
            }
        }
        catch (Exception error) when (CredentialStore.IsStorageError(error))
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
            if (registeredId is null || mode == AccountWindowMode.Dummy)
            {
                AutoLoginAtLogon.IsChecked = false;
                return;
            }

            if (mode == AccountWindowMode.PClient)
            {
                var realStartup = PClientStartup.ReadState();
                AutoLoginAtLogon.IsChecked = realStartup == PClientStartupState.EnabledHere;
                AutoLoginAtLogon.IsEnabled = realStartup != PClientStartupState.RegisteredElsewhere;
                AutoLoginDescription.Text = realStartup == PClientStartupState.RegisteredElsewhere
                    ? "다른 경로의 NetAuth가 Windows 시작프로그램에 등록되어 있습니다."
                    : "Windows 로그인 후 PClient 상태를 확인하고, 로그아웃되면 다시 로그인합니다.";
                return;
            }

            var startup = PClientPreviewStartup.ReadState();
            AutoLoginAtLogon.IsChecked = startup == PClientPreviewStartupState.EnabledHere;
            AutoLoginAtLogon.IsEnabled = true;
            AutoLoginDescription.Text = startup == PClientPreviewStartupState.EnabledElsewhere
                ? "다른 NetAuth 경로에 등록되어 있습니다. 여기서 켜면 실행 위치를 변경합니다."
                : "Windows 로그인 시 테스트용 PClient를 찾아 로그인을 한 번 시도합니다.";
        }
        catch (Exception error) when (PClientPreviewStartup.IsOperationError(error) || PClientStartup.IsOperationError(error))
        {
            AutoLoginAtLogon.IsChecked = null;
            AutoLoginDescription.Text = "Windows 시작 작업 상태를 읽을 수 없습니다.";
        }
        finally
        {
#if DEBUG
            if (mode == AccountWindowMode.PClient)
            {
                var manualActions = AutoLoginAtLogon.IsChecked == true ? Visibility.Collapsed : Visibility.Visible;
                LoginPClientButton.Visibility = manualActions;
                FillPClientAccountButton.Visibility = manualActions;
            }
#endif
            refreshingAutomaticLogin = false;
        }
    }

    private void AutoLoginAtLogon_Changed(object sender, RoutedEventArgs e)
    {
        if (refreshingAutomaticLogin || mode == AccountWindowMode.Dummy || registeredId is null)
        {
            return;
        }

        string feedback;
        var isError = false;
        try
        {
            if (mode == AccountWindowMode.PClient)
            {
                var enabled = AutoLoginAtLogon.IsChecked == true;
                var changed = enabled ? PClientStartup.Enable() : PClientStartup.Disable();
                if (changed && enabled)
                {
                    attemptedCurrentLogout = false;
                    resumeAutomaticLoginAt = 0;
                }
                feedback = !changed ? "다른 NetAuth 경로에 등록된 시작 항목은 유지했습니다."
                    : enabled ? "Windows 로그인 시 PClient에 자동 로그인하도록 설정했습니다."
                    : "PClient 자동 로그인과 시작 등록을 해제했습니다.";
                isError = !changed;
            }
            else if (AutoLoginAtLogon.IsChecked == true)
            {
                PClientPreviewStartup.Enable();
                feedback = "Windows 로그인 시 자동으로 실행되도록 등록했습니다.";
            }
            else
            {
                feedback = PClientPreviewStartup.Disable() ? "Windows 로그인 시 실행 등록을 해제했습니다."
                    : "다른 NetAuth 경로에 등록된 시작 작업은 유지했습니다.";
            }
        }
        catch (Exception error) when (PClientPreviewStartup.IsOperationError(error) || PClientStartup.IsOperationError(error))
        {
            feedback = "Windows 시작 항목을 변경할 수 없습니다.";
            isError = true;
        }

        RefreshAutomaticLogin();
        ShowFeedback(feedback, isError);
    }

    private void ShowEditor()
    {
        var firstRegistration = registeredId is null;
        Heading.Text = firstRegistration ? "계정 등록" : "계정 변경";
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
        CancelEditor.Content = firstRegistration ? "나중에" : "취소";
        AccountId.Text = registeredId ?? string.Empty;
        AccountPassword.Clear();
        ShowFeedback(string.Empty);
        (firstRegistration ? (UIElement)AccountId : AccountPassword).Focus();
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
            var savedIdentity = mode == AccountWindowMode.PClient ? store.Load()?.ExecutableIdentity : null;
            store.Save(new LoginAccount(userId, password, savedIdentity));
            attemptedCurrentLogout = false;
            resumeAutomaticLoginAt = 0;
            VerificationState.Text = "확인 전";
            ShowOverview(userId);
            ShowFeedback("계정을 이 PC에 저장했습니다.");
        }
        catch (Exception error) when (CredentialStore.IsStorageError(error))
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
        if (mode != AccountWindowMode.Dummy)
        {
            try
            {
                startupRemoved = mode == AccountWindowMode.PClient ? PClientStartup.Disable() : PClientPreviewStartup.Disable();
            }
            catch (Exception error) when (PClientPreviewStartup.IsOperationError(error) || PClientStartup.IsOperationError(error))
            {
                startupRemoved = false;
            }
        }

        try
        {
            store.Delete();
            VerificationState.Text = "확인 전";
            ShowOverview(null);
            RegisterButton.Focus();
            ShowFeedback(startupRemoved ? "저장된 계정을 삭제했습니다."
                : "저장된 계정은 삭제했습니다. Windows 시작 항목을 확인하세요.",
                isError: !startupRemoved);
        }
        catch (Exception error) when (CredentialStore.IsStorageError(error))
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
        catch (Exception error) when (CredentialStore.IsStorageError(error) || error is InvalidOperationException or COMException)
        {
            VerificationState.Text = "미확인";
            ShowFeedback("로그인 확인 중 오류가 발생했습니다. 계정 설정과 대상 창을 확인하세요.", isError: true);
        }
        finally
        {
            SavedActions.IsEnabled = true;
        }
    }

    private bool CanMonitorAuthentication => mode == AccountWindowMode.PClient && AutoLoginAtLogon.IsChecked == true &&
        SavedActions.IsEnabled && SavedActions.Visibility == Visibility.Visible && DeleteConfirmation.Visibility != Visibility.Visible;

    internal async void CheckAuthentication()
    {
        if (mode != AccountWindowMode.PClient || checkingAuthentication || !SavedActions.IsEnabled)
        {
            return;
        }

        checkingAuthentication = true;
        try
        {
            var userId = registeredId;
            var expected = knownExecutable;
            var (state, identity) = await Task.Run(() => PClientAccountFill.Observe(userId, expected));
            if (!SavedActions.IsEnabled || registeredId != userId)
            {
                return;
            }
            knownExecutable = identity ?? knownExecutable;
            ShowAuthenticationStatus(StatusFromResult(state));

            if (!CanMonitorAuthentication || userId is null || PClientStartup.ReadState() != PClientStartupState.EnabledHere)
            {
                return;
            }

            if (state == PClientAccountFillResult.LoginRequired && !attemptedCurrentLogout && identity is not null)
            {
                var delay = Math.Max(4000, resumeAutomaticLoginAt - Environment.TickCount64);
                VerificationState.Text = "대기 중";
                ShowFeedback("로그아웃을 확인했습니다. 잠시 후 다시 로그인합니다.");
                await Task.Delay(TimeSpan.FromMilliseconds(delay));
                if (Dispatcher.HasShutdownStarted || !CanMonitorAuthentication || registeredId != userId)
                {
                    return;
                }

                var delayedIdentity = identity;
                (state, identity) = await Task.Run(() => PClientAccountFill.Observe(userId, delayedIdentity));
                if (Dispatcher.HasShutdownStarted || !CanMonitorAuthentication || registeredId != userId ||
                    PClientStartup.ReadState() != PClientStartupState.EnabledHere)
                {
                    return;
                }
                ShowAuthenticationStatus(StatusFromResult(state));
                if (state is not (PClientAccountFillResult.LoginRequired or PClientAccountFillResult.AlreadyAuthenticated
                    or PClientAccountFillResult.OtherAccountAuthenticated))
                {
                    VerificationState.Text = "미확인";
                    ShowFeedback("PClient 상태가 바뀌었습니다. 상태를 다시 확인하는 중입니다.");
                    return;
                }
            }

            switch (state)
            {
                case PClientAccountFillResult.AlreadyAuthenticated:
                    attemptedCurrentLogout = false;
                    if (VerificationState.Text != "인증 확인됨")
                    {
                        VerificationState.Text = "인증 확인됨";
                        ShowFeedback("PClient에 등록한 계정으로 이미 로그인되어 있습니다.");
                    }
                    break;
                case PClientAccountFillResult.OtherAccountAuthenticated:
                    if (VerificationState.Text != "다른 계정")
                    {
                        VerificationState.Text = "다른 계정";
                        ShowFeedback("PClient에 다른 계정으로 로그인되어 있습니다.", isError: true);
                    }
                    break;
                case PClientAccountFillResult.LoginRequired when !attemptedCurrentLogout && identity is not null:
                    attemptedCurrentLogout = true;
                    await UsePClientAccountAsync(signIn: true, automaticIdentity: identity);
                    break;
                case PClientAccountFillResult.WindowNotFound when VerificationState.Text == "확인 전":
                    VerificationState.Text = "대기 중";
                    ShowFeedback("PClient 상태 창이 나타나기를 기다리는 중입니다.");
                    break;
            }
        }
        catch (Exception error) when (PClientStartup.IsOperationError(error) ||
            error is InvalidOperationException or COMException or System.ComponentModel.Win32Exception)
        {
            if (SavedActions.IsEnabled)
            {
                ShowAuthenticationStatus(AuthenticationStatus.Unknown);
            }
            if (CanMonitorAuthentication && VerificationState.Text is ("확인 전" or "대기 중"))
            {
                VerificationState.Text = "미확인";
                ShowFeedback("PClient 자동 로그인 상태를 확인할 수 없습니다.", isError: true);
            }
        }
        finally
        {
            checkingAuthentication = false;
        }
    }

    private async void UsePClientAccount_Click(object sender, RoutedEventArgs e) =>
        await UsePClientAccountAsync(signIn: ReferenceEquals(sender, LoginPClientButton));

    private async Task UsePClientAccountAsync(bool signIn, PClientExecutableIdentity? automaticIdentity = null)
    {
        DeleteConfirmation.Visibility = Visibility.Collapsed;
        SavedActions.IsEnabled = false;
        ShowFeedback("PClient의 로그아웃 상태를 확인하는 중입니다.");
        ShowAuthenticationStatus(AuthenticationStatus.Checking);
        if (signIn)
        {
            VerificationState.Text = "확인 중";
        }

        try
        {
            var account = store.Load();
            if (account is null)
            {
                ShowOverview(null);
                ShowFeedback("저장된 계정이 없습니다.", isError: true);
                return;
            }

            PClientAccountFillResult result;
            if (automaticIdentity is not null)
            {
                var connectedAccount = new LoginAccount(account.UserId, account.Password, automaticIdentity);
                result = await Task.Run(() => PClientAccountFill.LoginAutomatically(connectedAccount, () =>
                    PClientStartup.ReadState() == PClientStartupState.EnabledHere && IsCurrentAccount(account)));
            }
            else
            {
                var expected = account.ExecutableIdentity ?? knownExecutable;
                var identity = await Task.Run(() => PClientAccountFill.FindConnectedIdentity(expected));
                if (identity is null)
                {
                    ShowFeedback("PClient 연결되지 않음", isError: true);
                    return;
                }
                knownExecutable = identity;

                if (!IsCurrentAccount(account))
                {
                    ShowFeedback("저장된 계정이 변경되었습니다. 다시 시도해 주세요.", isError: true);
                    return;
                }

                var connectedAccount = new LoginAccount(account.UserId, account.Password, identity);
                if (signIn)
                {
                    ShowFeedback("PClient 로그인 및 결과를 확인하는 중입니다.");
                }
                result = await Task.Run(() => signIn ? PClientAccountFill.Login(connectedAccount) : PClientAccountFill.Fill(connectedAccount));
            }

            var authenticated = result is PClientAccountFillResult.Authenticated or PClientAccountFillResult.AlreadyAuthenticated;
            ShowAuthenticationStatus(StatusFromResult(result));
            if (signIn)
            {
                VerificationState.Text = authenticated ? "인증 확인됨" : "미확인";
            }
            if (authenticated)
            {
                attemptedCurrentLogout = false;
                resumeAutomaticLoginAt = Environment.TickCount64 + (long)TimeSpan.FromSeconds(15).TotalMilliseconds;
            }
            ShowFeedback(result switch
            {
                PClientAccountFillResult.Filled => "PClient에 ID와 비밀번호를 채웠습니다.",
                PClientAccountFillResult.Authenticated => "PClient에서 등록한 계정의 로그인 상태를 확인했습니다.",
                PClientAccountFillResult.AlreadyAuthenticated => "PClient에 등록한 계정으로 이미 로그인되어 있습니다.",
                PClientAccountFillResult.OtherAccountAuthenticated => "PClient에 다른 계정으로 로그인되어 있습니다.",
                PClientAccountFillResult.LoginButtonNotConfirmed => "PClient의 로그인 버튼을 확인할 수 없습니다.",
                PClientAccountFillResult.UnknownState => "PClient에서 로그인 결과를 확인할 수 없습니다. PClient 상태 창을 확인하세요.",
                PClientAccountFillResult.WindowNotFound => "이 Windows 세션에서 PClient 로그인 창을 열어 주세요.",
                PClientAccountFillResult.AmbiguousWindow => "PClient 창을 하나만 남기고 다시 시도하세요.",
                PClientAccountFillResult.ExecutableNotConfirmed => "PClient 연결되지 않음",
                PClientAccountFillResult.LogoutNotConfirmed => "PClient에서 로그아웃 상태를 확인할 수 없습니다.",
                PClientAccountFillResult.FieldsNotConfirmed => "PClient 로그인 입력란을 확인할 수 없습니다.",
                PClientAccountFillResult.PasswordNotEmpty => "PClient의 비밀번호란을 비운 뒤 다시 시도하세요.",
                PClientAccountFillResult.PasswordNotAccepted => "PClient에서 비밀번호 입력을 확인할 수 없습니다.",
                PClientAccountFillResult.RestorationNotVerified => "입력란 복구를 확인할 수 없습니다. PClient의 입력란을 확인하세요.",
                PClientAccountFillResult.StartupNotCurrent => "시작 설정 또는 저장된 계정이 변경되어 자동 로그인을 중단했습니다.",
                PClientAccountFillResult.Busy => "다른 NetAuth 창에서 PClient를 처리하는 중입니다.",
                _ => "PClient에서 저장된 ID가 입력됐는지 확인할 수 없습니다."
            }, isError: !authenticated && result != PClientAccountFillResult.Filled);
        }
        catch (Exception error) when (CredentialStore.IsStorageError(error) || PClientStartup.IsOperationError(error) ||
            error is InvalidOperationException or COMException or System.ComponentModel.Win32Exception)
        {
            ShowFeedback("PClient에서 계정을 사용할 수 없습니다. 저장된 계정과 PClient 창을 확인하세요.", isError: true);
        }
        finally
        {
            if (signIn && VerificationState.Text == "확인 중")
            {
                VerificationState.Text = "미확인";
            }
            if (PClientAuthenticationStatus.Text == "PClient 확인 중")
            {
                ShowAuthenticationStatus(AuthenticationStatus.Unknown);
            }
            SavedActions.IsEnabled = true;
        }
    }

    private bool IsCurrentAccount(LoginAccount account)
    {
        var latest = store.Load();
        return latest is not null && latest.UserId == account.UserId && latest.Password == account.Password &&
            latest.ExecutableIdentity == account.ExecutableIdentity;
    }

    private void RefreshPClientStatus(object? sender, EventArgs e) => CheckAuthentication();

    private static AuthenticationStatus StatusFromResult(PClientAccountFillResult result) => result switch
    {
        PClientAccountFillResult.Authenticated or PClientAccountFillResult.AlreadyAuthenticated => AuthenticationStatus.SignedIn,
        PClientAccountFillResult.LoginRequired or PClientAccountFillResult.Filled => AuthenticationStatus.SignedOut,
        PClientAccountFillResult.OtherAccountAuthenticated => AuthenticationStatus.OtherAccount,
        _ => AuthenticationStatus.Unknown
    };

    private void ShowAuthenticationStatus(AuthenticationStatus status)
    {
        var (text, foreground, background, dot) = status switch
        {
            AuthenticationStatus.SignedIn => ("PClient 로그인됨", "AuthSuccessText", "AuthSuccessSurface", "AuthSuccessDot"),
            AuthenticationStatus.SignedOut => ("PClient 로그아웃됨", "AuthWarningText", "AuthWarningSurface", "AuthWarningDot"),
            AuthenticationStatus.OtherAccount => ("다른 계정 로그인됨", "AuthWarningText", "AuthWarningSurface", "AuthWarningDot"),
            AuthenticationStatus.Checking => ("PClient 확인 중", "Brand", "Tint", "Brand"),
            _ => ("PClient 상태 미확인", "Muted", "AuthUnknownSurface", "Muted")
        };
        if (PClientAuthenticationStatus.Text != text)
        {
            PClientAuthenticationStatus.Text = text;
            PClientAuthenticationStatus.Foreground = (Brush)FindResource(foreground);
            PClientStatusDot.Fill = (Brush)FindResource(dot);
            PClientStatusBadge.Background = (Brush)FindResource(background);
            FrameworkElementAutomationPeer.CreatePeerForElement(PClientAuthenticationStatus)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        }

        if (status is AuthenticationStatus.SignedIn or AuthenticationStatus.SignedOut or AuthenticationStatus.OtherAccount)
        {
            var signedIn = status != AuthenticationStatus.SignedOut;
            var previous = lastConfirmedSignIn;
            lastConfirmedSignIn = signedIn;
            if (previous != signedIn && (previous is not null || !signedIn))
            {
                AuthenticationChanged?.Invoke(signedIn);
            }
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
}
