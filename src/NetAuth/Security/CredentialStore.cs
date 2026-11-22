using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace NetAuth.Security;

internal sealed class LoginAccount(string userId, string password, PClientExecutableIdentity? executableIdentity = null)
{
    public string UserId { get; } = userId;
    public string Password { get; } = password;
    public PClientExecutableIdentity? ExecutableIdentity { get; } = executableIdentity;
}

internal sealed class CredentialStore(bool useDummyAccount)
{
    private readonly string directory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "NetAuth", useDummyAccount ? "Dummy" : "Account");
    private readonly byte[] scope = Encoding.UTF8.GetBytes(
        useDummyAccount ? "NetAuth.Dummy.v1" : "NetAuth.Account.v1");

    private string AccountPath => Path.Combine(directory, "account.dat");

    public static bool IsStorageError(Exception error) =>
        error is IOException or UnauthorizedAccessException or CryptographicException or JsonException or InvalidDataException;

    public LoginAccount? Load()
    {
        byte[] encrypted;
        try
        {
            encrypted = File.ReadAllBytes(AccountPath);
        }
        catch (IOException error) when (error is FileNotFoundException or DirectoryNotFoundException)
        {
            return null;
        }

        var plaintext = ProtectedData.Unprotect(encrypted, scope, DataProtectionScope.CurrentUser);
        try
        {
            var account = JsonSerializer.Deserialize<LoginAccount>(plaintext);
            if (account is null || string.IsNullOrWhiteSpace(account.UserId) ||
                string.IsNullOrEmpty(account.Password))
            {
                throw new InvalidDataException("저장된 계정 형식이 올바르지 않습니다.");
            }
            return account;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    public void Save(LoginAccount account)
    {
        var plaintext = JsonSerializer.SerializeToUtf8Bytes(account);
        byte[] encrypted;
        try
        {
            encrypted = ProtectedData.Protect(plaintext, scope, DataProtectionScope.CurrentUser);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
        }

        Directory.CreateDirectory(directory);
        var pendingPath = Path.Combine(directory, $"{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(pendingPath, encrypted);
            File.Move(pendingPath, AccountPath, overwrite: true);
        }
        finally
        {
            File.Delete(pendingPath);
        }
    }

    public void Delete() => File.Delete(AccountPath);
}
