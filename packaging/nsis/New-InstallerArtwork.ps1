param(
    [Parameter(Mandatory)] [string]$LogoPath,
    [Parameter(Mandatory)] [string]$OutputDirectory
)

Add-Type -AssemblyName System.Drawing
$logo = [Drawing.Image]::FromFile($LogoPath)
$wizard = [Drawing.Bitmap]::new(328, 628, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
$header = [Drawing.Bitmap]::new(300, 114, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
$panel = [Drawing.Graphics]::FromImage($wizard)
$headerGraphics = [Drawing.Graphics]::FromImage($header)
$background = [Drawing.Drawing2D.LinearGradientBrush]::new(
    [Drawing.Rectangle]::new(0, 0, $wizard.Width, $wizard.Height),
    [Drawing.Color]::FromArgb(10, 32, 58), [Drawing.Color]::FromArgb(19, 68, 101),
    [Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
)
$trace = [Drawing.Pen]::new([Drawing.Color]::FromArgb(58, 99, 215, 232), 2)
$accent = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(95, 215, 232))
$wordmark = [Drawing.Font]::new('Segoe UI Semibold', 44, [Drawing.GraphicsUnit]::Pixel)
$center = [Drawing.StringFormat]::new()
$center.Alignment = [Drawing.StringAlignment]::Center

try {
    $panel.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $panel.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $panel.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $panel.FillRectangle($background, 0, 0, $wizard.Width, $wizard.Height)
    $panel.DrawEllipse($trace, 77, 140, 174, 174)
    $panel.DrawEllipse($trace, 58, 121, 212, 212)
    $panel.DrawImage($logo, 108, 171, 112, 112)
    $panel.FillEllipse($accent, 230, 146, 8, 8)
    $panel.DrawString('NetAuth', $wordmark, [Drawing.Brushes]::White, [Drawing.PointF]::new(164, 355), $center)

    $panel.DrawLines($trace, [Drawing.Point[]]@(
        [Drawing.Point]::new(0, 507), [Drawing.Point]::new(78, 507),
        [Drawing.Point]::new(120, 465), [Drawing.Point]::new(178, 465)
    ))
    $panel.DrawLines($trace, [Drawing.Point[]]@(
        [Drawing.Point]::new(328, 513), [Drawing.Point]::new(246, 513),
        [Drawing.Point]::new(186, 573), [Drawing.Point]::new(140, 573)
    ))
    $panel.FillEllipse($accent, 174, 461, 8, 8)
    $panel.FillEllipse($accent, 136, 569, 8, 8)
    $wizard.Save((Join-Path $OutputDirectory 'wizard.bmp'), [Drawing.Imaging.ImageFormat]::Bmp)

    $headerGraphics.Clear([Drawing.Color]::FromArgb(252, 253, 254))
    $headerGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $headerGraphics.DrawImage($logo, 220, 24, 66, 66)
    $header.Save((Join-Path $OutputDirectory 'header.bmp'), [Drawing.Imaging.ImageFormat]::Bmp)
} finally {
    $center.Dispose()
    $wordmark.Dispose()
    $accent.Dispose()
    $trace.Dispose()
    $background.Dispose()
    $headerGraphics.Dispose()
    $panel.Dispose()
    $header.Dispose()
    $wizard.Dispose()
    $logo.Dispose()
}
