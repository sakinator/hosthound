using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;

namespace HostreamioLauncher {
    static class Program {
        [STAThread]
        static void Main(string[] args) {
            try {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string appDir = Path.Combine(localAppData, "Hostreamio", "app");
                string exePath = Path.Combine(appDir, "hostreamio.exe");
                var assembly = Assembly.GetExecutingAssembly();
                long payloadSize = 0;
                using (Stream probeStream = assembly.GetManifestResourceStream("payload.zip")) {
                    if (probeStream != null) {
                        payloadSize = probeStream.Length;
                    }
                }
                string currentVersion = "1.0.0_" + payloadSize;
                string versionFile = Path.Combine(appDir, "version.txt");
                bool needsExtract = !File.Exists(exePath) || !File.Exists(versionFile) || File.ReadAllText(versionFile).Trim() != currentVersion;

                if (needsExtract) {
                    if (Directory.Exists(appDir)) {
                        try {
                            Directory.Delete(appDir, true);
                        } catch {}
                    }
                    Directory.CreateDirectory(appDir);

                    using (Stream stream = assembly.GetManifestResourceStream("payload.zip")) {
                        if (stream != null) {
                            using (ZipArchive archive = new ZipArchive(stream)) {
                                foreach (ZipArchiveEntry entry in archive.Entries) {
                                    if (string.IsNullOrEmpty(entry.Name) && (entry.FullName.EndsWith("/") || entry.FullName.EndsWith("\\"))) {
                                        continue;
                                    }
                                    string destPath = Path.Combine(appDir, entry.FullName);
                                    string destDir = Path.GetDirectoryName(destPath);
                                    if (!Directory.Exists(destDir)) {
                                        Directory.CreateDirectory(destDir);
                                    }
                                    entry.ExtractToFile(destPath, true);
                                }
                            }
                        }
                    }
                    File.WriteAllText(versionFile, currentVersion);
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = exePath;
                psi.WorkingDirectory = appDir;
                if (args != null && args.Length > 0) {
                    psi.Arguments = string.Join(" ", args);
                }
                psi.UseShellExecute = false;

                Process.Start(psi);
            } catch (Exception ex) {
                System.Windows.Forms.MessageBox.Show(
                    "Error launching Hostreamio: " + ex.Message, 
                    "Hostreamio Error", 
                    System.Windows.Forms.MessageBoxButtons.OK, 
                    System.Windows.Forms.MessageBoxIcon.Error
                );
            }
        }
    }
}
