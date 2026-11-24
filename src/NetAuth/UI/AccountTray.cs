using System.Drawing;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Threading;
using Application = System.Windows.Application;

namespace NetAuth.UI;

internal static class AccountTray
{
    public static int Run(bool startHidden)
    {
        using var user = WindowsIdentity.GetCurrent();
        var pathHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
            Environment.ProcessPath!.ToUpperInvariant())));
        var instanceKey = $"{user.User!.Value}.{pathHash}";
        using var openRequest = new EventWaitHandle(false, EventResetMode.AutoReset,
            $@"Local\NetAuth.Open.{instanceKey}", out var firstInstance);
        if (!firstInstance)
        {
            if (!startHidden)
            {
                openRequest.Set();
            }
            return 0;
        }

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var window = new AccountWindow(AccountWindowMode.PClient);
        var exitRequested = false;
        window.Closing += (_, args) =>
        {
            if (!exitRequested && !app.Dispatcher.HasShutdownStarted)
            {
                args.Cancel = true;
                app.Dispatcher.BeginInvoke((Action)window.Hide);
            }
        };

        var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/netauth.ico"));
        using var iconStream = resource!.Stream;
        using var icon = new Icon(iconStream);
        using var menu = new ContextMenuStrip();
        using var tray = new NotifyIcon { Text = "NetAuth", Icon = icon, ContextMenuStrip = menu };
        var notificationTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(10) };
        AuthenticationNotification? notification = null;
        notificationTimer.Tick += (_, _) => notification?.Close();
        window.AuthenticationChanged += QueueNotification;
        menu.Items.Add("NetAuth 열기", null, (_, _) => ShowWindow());
        menu.Items.Add("종료", null, (_, _) =>
        {
            exitRequested = true;
            app.Shutdown();
        });
        tray.DoubleClick += (_, _) => ShowWindow();
        tray.Visible = true;

        var wait = ThreadPool.RegisterWaitForSingleObject(openRequest,
            (_, _) => app.Dispatcher.BeginInvoke((Action)ShowWindow), null, Timeout.Infinite, executeOnlyOnce: false);
        var monitor = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        monitor.Tick += (_, _) => window.CheckAuthentication();
        try
        {
            app.Dispatcher.BeginInvoke((Action)window.CheckAuthentication);
            monitor.Start();
            if (!startHidden)
            {
                ShowWindow();
            }
            return app.Run();
        }
        finally
        {
            wait.Unregister(null);
            monitor.Stop();
            notificationTimer.Stop();
        }

        void QueueNotification(bool signedIn)
        {
            if (exitRequested || app.Dispatcher.HasShutdownStarted)
            {
                return;
            }

            notification?.Close();
            notification = new AuthenticationNotification(signedIn, ShowWindow);
            notification.Closed += (_, _) =>
            {
                notificationTimer.Stop();
                notification = null;
            };
            notification.Show();
            notificationTimer.Start();
        }

        void ShowWindow()
        {
            if (exitRequested || app.Dispatcher.HasShutdownStarted)
            {
                return;
            }

            window.Show();
            if (window.WindowState == WindowState.Minimized)
            {
                window.WindowState = WindowState.Normal;
            }
            window.Activate();
        }
    }
}
