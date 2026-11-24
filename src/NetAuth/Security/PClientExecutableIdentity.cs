using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;

namespace NetAuth.Security;

internal sealed record PClientExecutableIdentity(string Path, string Sha256)
{
    public const string FileName = "PClientUI.exe";

    public static PClientExecutableIdentity? FromSignedFile(string path)
    {
        // 서명 확인과 해시 계산 사이의 파일 교체 방지
        using var image = File.OpenRead(path);
        var powerShellDirectory = System.IO.Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0");
        var start = new ProcessStartInfo(System.IO.Path.Combine(powerShellDirectory, "powershell.exe"))
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = powerShellDirectory
        };
        start.Environment["PSModulePath"] = System.IO.Path.Combine(powerShellDirectory, "Modules");
        start.Environment["NETAUTH_PCLIENT_IMAGE"] = path;
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-Command");
        start.ArgumentList.Add("""
            $signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $env:NETAUTH_PCLIENT_IMAGE
            if ($signature.Status -eq 'Valid' -and
                $signature.SignerCertificate.GetNameInfo('SimpleName', $false) -ceq 'NetMan Co., Ltd.') { exit 0 }
            exit 1
            """);

        using var verification = Process.Start(start);
        if (verification is null)
        {
            return null;
        }

        if (!verification.WaitForExit(5000))
        {
            verification.Kill();
            return null;
        }

        return verification.ExitCode == 0
            ? new PClientExecutableIdentity(path, Convert.ToHexString(SHA256.HashData(image)))
            : null;
    }

    public bool Matches(Process process)
    {
        try
        {
            var image = process.MainModule?.FileName;
            return image is not null && string.Equals(image, Path, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(ReadSha256(image), Sha256, StringComparison.Ordinal) && !process.HasExited;
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    public Process? Reopen()
    {
        // 확인된 실행 파일을 시작하는 동안 경로 교체 방지
        using var image = File.OpenRead(Path);
        if (!string.Equals(Convert.ToHexString(SHA256.HashData(image)), Sha256, StringComparison.Ordinal))
        {
            return null;
        }

        return Process.Start(new ProcessStartInfo(Path)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = System.IO.Path.GetDirectoryName(Path)!
        });
    }

    private static string ReadSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }
}
