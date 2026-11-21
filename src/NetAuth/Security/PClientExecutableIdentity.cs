using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;

namespace NetAuth.Security;

internal sealed record PClientExecutableIdentity(string Path, string Sha256)
{
    public const string FileName = "PClientUI.exe";

    public static PClientExecutableIdentity FromFile(string path)
    {
        if (!System.IO.Path.IsPathFullyQualified(path) ||
            !string.Equals(System.IO.Path.GetFileName(path), FileName, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("PClientUI.exe의 전체 경로가 필요합니다.");
        }

        var fullPath = System.IO.Path.GetFullPath(path);
        return new PClientExecutableIdentity(fullPath, ReadSha256(fullPath));
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

    private static string ReadSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }
}
