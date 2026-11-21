using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace NetAuth.PClient;

internal enum PClientPreviewStartupState
{
    Off,
    EnabledHere,
    EnabledElsewhere
}

internal static class PClientPreviewStartup
{
    private const string LogonArgument = "--login-pclient-preview-at-logon";
    private const int FileNotFound = unchecked((int)0x80070002);
    private const int TaskNotRunning = unchecked((int)0x8004130B);
    private const int CreateOrUpdate = 6;
    private const int InteractiveToken = 3;
    private const int LimitedRunLevel = 0;
    private const int LogonTrigger = 9;
    private const int ExecuteAction = 0;
    private const int IgnoreNewInstance = 2;

    public static PClientPreviewStartupState ReadState()
    {
        using var user = WindowsIdentity.GetCurrent();
        dynamic folder = Connect().GetFolder(@"\");
        dynamic? task = FindTask(folder, TaskName(user));
        return task is null || !task.Enabled ? PClientPreviewStartupState.Off
            : OwnsTask(task) ? PClientPreviewStartupState.EnabledHere : PClientPreviewStartupState.EnabledElsewhere;
    }

    public static void Enable()
    {
        using var change = BeginChange();
        using var user = WindowsIdentity.GetCurrent();
        var userId = user.User!.Value;
        var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Executable path unavailable.");
        if (!string.Equals(Path.GetFileName(executable), "NetAuth.exe", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Run NetAuth.exe to register its startup task.");
        }

        dynamic scheduler = Connect();
        dynamic definition = scheduler.NewTask(0);
        definition.RegistrationInfo.Description = "NetAuth logon test using the local PClient preview only.";
        definition.Principal.UserId = userId;
        definition.Principal.LogonType = InteractiveToken;
        definition.Principal.RunLevel = LimitedRunLevel;
        definition.Triggers.Create(LogonTrigger).UserId = userId;
        definition.Settings.MultipleInstances = IgnoreNewInstance;
        definition.Settings.ExecutionTimeLimit = "PT1M";
        definition.Settings.DisallowStartIfOnBatteries = false;
        definition.Settings.StopIfGoingOnBatteries = false;

        dynamic action = definition.Actions.Create(ExecuteAction);
        action.Path = executable;
        action.WorkingDirectory = Path.GetDirectoryName(executable);
        action.Arguments = LogonArgument;
        scheduler.GetFolder(@"\").RegisterTaskDefinition(TaskName(user), definition, CreateOrUpdate,
            userId, null, InteractiveToken, null);
    }

    public static bool Disable()
    {
        using var change = BeginChange();
        using var user = WindowsIdentity.GetCurrent();
        dynamic folder = Connect().GetFolder(@"\");
        var name = TaskName(user);
        dynamic? task = FindTask(folder, name);
        if (task is null)
        {
            return true;
        }
        if (!OwnsTask(task))
        {
            return false;
        }

        try
        {
            task.Enabled = false;
            try
            {
                task.Stop(0);
            }
            catch (COMException error) when (error.HResult == TaskNotRunning)
            {
                // 실행 중인 작업이 없는 경우에도 등록 해제 진행
            }
            folder.DeleteTask(name, 0);
        }
        catch (Exception error) when (error.HResult == FileNotFound)
        {
            // 다른 설정 창에서 이미 제거한 작업은 해제 상태로 처리
        }
        return true;
    }

    private static bool OwnsTask(dynamic task)
    {
        dynamic actions = task.Definition.Actions;
        if (actions.Count != 1)
        {
            return false;
        }
        dynamic action = actions.Item(1);
        return action.Type == ExecuteAction &&
            string.Equals((string)action.Path, Environment.ProcessPath, StringComparison.OrdinalIgnoreCase) &&
            string.Equals((string)action.Arguments, LogonArgument, StringComparison.Ordinal);
    }

    private static Mutex BeginChange()
    {
        var change = new Mutex(false, @"Local\NetAuth.PClientPreview.Startup", out var created);
        if (created)
        {
            return change;
        }
        change.Dispose();
        throw new InvalidOperationException("Another NetAuth process is updating the logon task.");
    }

    private static string TaskName(WindowsIdentity user) => $"NetAuth PClient Preview Logon - {user.User!.Value}";

    public static bool IsOperationError(Exception error) =>
        error is COMException or UnauthorizedAccessException or InvalidOperationException;

    private static dynamic Connect()
    {
        var type = Type.GetTypeFromProgID("Schedule.Service", throwOnError: true)!;
        dynamic scheduler = Activator.CreateInstance(type)!;
        scheduler.Connect();
        return scheduler;
    }

    private static dynamic? FindTask(dynamic folder, string name)
    {
        try
        {
            return folder.GetTask(name);
        }
        catch (Exception error) when (error.HResult == FileNotFound)
        {
            return null;
        }
    }
}
