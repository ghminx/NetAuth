using System.Windows;
using System.Windows.Media;

namespace NetAuth.UI;

internal partial class AuthenticationNotification : Window
{
    private readonly Action openSettings;

    internal AuthenticationNotification(bool signedIn, Action openSettings)
    {
        InitializeComponent();
        this.openSettings = openSettings;

        if (!signedIn)
        {
            Card.BorderBrush = new SolidColorBrush(Color.FromRgb(91, 70, 85));
            CardTint.Color = Color.FromRgb(47, 39, 54);
            StatusTile.Background = new SolidColorBrush(Color.FromRgb(57, 45, 55));
            StatusGlyph.Stroke = new SolidColorBrush(Color.FromRgb(255, 206, 156));
            StatusGlyph.Data = Geometry.Parse("M 16,3 L 5,3 Q 2,3 2,6 L 2,24 Q 2,27 5,27 L 16,27 M 9,15 L 28,15 M 22,9 L 28,15 L 22,21");
            StatusTitle.Text = "PClient 로그아웃됨";
            StatusDescription.Text = "창원대 PClient의 로그아웃 상태를 확인했습니다.";
        }

        Title = $"NetAuth · {StatusTitle.Text}";
        var workArea = SystemParameters.WorkArea;
        Card.Measure(new Size(Width, double.PositiveInfinity));
        Left = workArea.Right - Width - 16;
        Top = workArea.Bottom - Card.DesiredSize.Height - 16;
    }

    private void Dismiss_Click(object sender, RoutedEventArgs e) => Close();

    private void OpenSettings_Click(object sender, RoutedEventArgs e)
    {
        Close();
        openSettings();
    }
}
