using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
[assembly: AssemblyTitle("Hytale Together")]
[assembly: AssemblyProduct("Hytale Together")]
[assembly: AssemblyDescription("Unofficial Hytale split-screen launcher")]
[assembly: AssemblyVersion("0.3.1.0")]
internal static class Launcher
{
    [DllImport("shell32.dll", SetLastError = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

    [STAThread]
    private static int Main()
    {
        try
        {
            try { SetCurrentProcessExplicitAppUserModelID("HytaleTogether.Launcher"); } catch { }
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "Bootstrap.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Extract the entire Hytale Together ZIP into a folder before running this application. Bootstrap.ps1 is missing.");
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
            var info = new ProcessStartInfo(powershell,
                "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
            info.WorkingDirectory = root;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            using (Process child = Process.Start(info))
            {
                child.WaitForExit();
                return child.ExitCode;
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Hytale Together", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
