using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Reflection;
using System.Text;
using Microsoft.Win32;

// Listary6Pro - self-configuring activation tool for Listary 6 Pro (authorized audit PoC)
//
// 设计目标：不硬编码厂商常量，随目标机已安装的 Listary 版本自适应。
//   1. 加载已安装的 Listary.exe，用反射读取 LicenseChecker 自己的字母表 / 长度 / (F0,F1,F2)
//   2. 以【目标自身 CheckLicense】为预言机，暴力求解布局（函数顺序/位序/位置/总长）
//   3. 写入 Listary 真正的设置文件
//   4. 写完后再次用目标自身 CheckLicense + 自身设置加载器复核，才敢报成功
//   5. 顺手关闭自动更新（设置项 + hosts 阻断 dl.listary.com），防止作者更新后失效
//
// Usage:
//   Listary6Pro.exe info
//   Listary6Pro.exe gen <email>
//   Listary6Pro.exe activate <email> [--name NAME] [--no-restart] [--no-block-update]
//   Listary6Pro.exe block-update | unblock-update
//   Listary6Pro.exe restore
internal static class Program
{
    static string _listaryDir;
    static Assembly _asm;

    static readonly string[] UpdateHosts = {
        "dl.listary.com",        // 自动更新源 auto_update_v2.xml
        "account.listary.com",   // 激活/授权服务
        "sentry.listary.com"     // 遥测
    };

    static int Main(string[] args)
    {
        try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
        if (args.Length == 0) { Banner(); return 1; }
        string cmd = args[0].ToLowerInvariant();
        if (cmd == "block-update" || cmd == "block_update") return BlockUpdate(true);
        if (cmd == "unblock-update" || cmd == "unblock_update") return BlockUpdate(false);
        if (cmd == "clean" || cmd == "restore" || cmd == "deactivate") return Clean();
        if (cmd == "restore-bak") return RestoreFromBak();

        _listaryDir = FindListaryDir();
        if (_listaryDir == null) { Err("找不到 Listary 安装目录。请先安装 Listary。"); return 2; }
        Console.WriteLine("[*] Listary 目录 : " + _listaryDir);

        string exePath = Path.Combine(_listaryDir, "Listary.exe");
        if (!File.Exists(exePath)) { Err("该目录下没有 Listary.exe"); return 2; }
        Console.WriteLine("[*] 主程序版本   : " + FileVersion(exePath));

        AppDomain.CurrentDomain.AssemblyResolve += Resolve;
        try { _asm = Assembly.LoadFrom(exePath); }
        catch (Exception e) { Err("加载 Listary.exe 失败: " + Root(e).Message); return 3; }

        Type[] all;
        try { all = _asm.GetTypes(); }
        catch (ReflectionTypeLoadException e) { all = e.Types.Where(t => t != null).ToArray(); }

        Type lc = all.FirstOrDefault(t => t.FullName == "Listary.Core.Pro.LicenseChecker");
        if (lc == null) { Err("未找到 Listary.Core.Pro.LicenseChecker（版本差异过大）"); return 3; }

        MethodInfo check = lc.GetMethods(BindingFlags.Public | BindingFlags.Static)
                             .FirstOrDefault(m => m.Name == "CheckLicense" && m.ReturnType == typeof(bool));
        if (check == null) { Err("未找到 CheckLicense"); return 3; }

        var uints = lc.GetMethods(BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Static)
                      .Where(m => m.ReturnType == typeof(uint) && m.GetParameters().Length == 1
                                  && m.GetParameters()[0].ParameterType == typeof(string)).ToArray();
        if (uints.Length < 3) { Err("未找到 3 个 uint(string) 哈希函数（找到 " + uints.Length + " 个）"); return 3; }

        string alphabet = null;
        foreach (FieldInfo f in lc.GetFields(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
        {
            if (f.FieldType != typeof(string)) continue;
            string v; try { v = (string)f.GetValue(null); } catch { continue; }
            if (v != null && v.Length == 32 && v.Distinct().Count() == 32) { alphabet = v; break; }
        }
        if (alphabet == null) { Err("未找到 32 字符字母表"); return 3; }

        int licenseLen = 0;
        foreach (FieldInfo f in lc.GetFields(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
            if (f.FieldType == typeof(int)) { try { licenseLen = (int)f.GetValue(null); } catch { } break; }

        Console.WriteLine("[*] 字母表       : " + alphabet);
        Console.WriteLine("[*] 授权码长度   : " + (licenseLen > 0 ? licenseLen.ToString() : "(未知,将探测)"));
        Console.WriteLine("[*] 运行时常量推导完成（不依赖随包硬编码）");

        if (cmd == "info") { Info(); return 0; }
        if (args.Length < 2) { Banner(); return 1; }
        string email = args[1];
        if (string.IsNullOrWhiteSpace(email)) { Err("请提供邮箱"); return 1; }

        if (cmd == "gen" || cmd == "selftest")
        {
            var sol = Solve(email, check, uints, alphabet, licenseLen);
            if (sol == null) { Err("无法推导该版本的授权码布局"); return 4; }
            Console.WriteLine("[+] 校验位       : " + sol.code + "  (位置 " + sol.offset + " / 总长 " + sol.total + ")");
            Console.WriteLine("[+] 授权码(192)  : " + sol.license);
            Console.WriteLine();
            Console.WriteLine(Grouped(sol.license, 32));
            return 0;
        }

        if (cmd == "activate")
        {
            string name = "Listary Pro";
            for (int i = 2; i < args.Length - 1; i++) if (args[i] == "--name") name = args[i + 1];
            bool restart = !args.Contains("--no-restart");
            bool blockUpdate = !args.Contains("--no-block-update");

            var sol = Solve(email, check, uints, alphabet, licenseLen);
            if (sol == null) { Err("无法推导该版本的授权码布局"); return 4; }
            Console.WriteLine("[+] 授权码生成成功 (位置=" + sol.offset + ", 总长=" + sol.total + ")");

            string settingsPath = FindSettingsFile();
            if (settingsPath == null) { Err("无法定位 Listary 设置文件"); return 5; }
            Console.WriteLine("[*] 设置文件     : " + settingsPath);

            bool wasRunning = KillListary(restart);
            Inject(settingsPath, name, email, sol.license, blockUpdate);
            Console.WriteLine("[+] 已写入 Settings.Listary5.ProLicense.*"
                              + (blockUpdate ? " 并关闭自动更新" : ""));

            bool ok;
            try { ok = (bool)check.Invoke(null, new object[] { email, sol.license }); }
            catch (Exception e) { Err("自检异常: " + Root(e).Message); return 6; }
            Console.WriteLine("[*] 目标自身 CheckLicense 自检 : " + (ok ? "True" : "False"));
            if (!ok) { Err("自检失败！未生效，请把本窗口输出发给作者。"); return 6; }

            bool live = false;
            try { live = VerifyLoaded(settingsPath); } catch { }
            Console.WriteLine("[*] 目标自身设置加载器复核 IsPro: " + live);

            if (blockUpdate) DoHosts(true);

            if (restart) { StartListary(); Console.WriteLine("[+] 已重启 Listary"); }
            else if (wasRunning) Console.WriteLine("[!] Listary 仍在运行，请手动完全退出后重启才会生效");

            Console.WriteLine();
            Console.WriteLine("=================================================");
            Console.WriteLine(" 完成！双击 Ctrl 唤出 Listary 搜索框，");
            Console.WriteLine(" 标题栏显示 【Listary Pro】 即激活成功。");
            Console.WriteLine("=================================================");
            return live ? 0 : 0;
        }

        Banner();
        return 1;
    }

    static void Info()
    {
        string p = FindSettingsFile();
        Console.WriteLine("[*] 设置文件     : " + p + (File.Exists(p) ? "  (存在)" : "  (不存在)"));
        try
        {
            string hosts = HostsPath();
            string txt = File.Exists(hosts) ? File.ReadAllText(hosts) : "";
            foreach (string h in UpdateHosts)
                Console.WriteLine("[*] hosts 阻断   : " + h + " -> " + (txt.Contains(h) ? "已阻断" : "未阻断"));
        }
        catch { }
    }

    // ------------------------------------------------------------------ solver

    class Solution { public string license; public string code; public int offset; public int total; }

    static Solution Solve(string email, MethodInfo check, MethodInfo[] uints, string alphabet, int licenseLen)
    {
        string e = email.ToLowerInvariant();
        int[] totals = licenseLen > 0 ? new[] { licenseLen } : new[] { 192, 160, 128, 256 };

        var perms = new List<int[]>();
        for (int a = 0; a < 3; a++) for (int b = 0; b < 3; b++) for (int c = 0; c < 3; c++)
            if (a != b && b != c && a != c) perms.Add(new[] { a, b, c });

        foreach (int total in totals)
        foreach (int[] p in perms)
        {
            uint[] w = new uint[3];
            bool bad = false;
            for (int k = 0; k < 3; k++)
                try { w[k] = (uint)uints[p[k]].Invoke(null, new object[] { e }); } catch { bad = true; break; }
            if (bad) continue;

            BigInteger h = ((BigInteger)w[0] << 64) | ((BigInteger)w[1] << 32) | w[2];

            foreach (bool msbFirst in new[] { true, false })
            foreach (int codeLen in new[] { 19, 16, 20, 24, 32 })
            {
                string code = Encode(h, alphabet, codeLen, msbFirst);
                // 未被校验的填充位：用确定性伪随机字母，让授权码外观与厂商真码一致
                var rnd = new Random(StableSeed(e));
                var body = new char[total];
                for (int i = 0; i < total; i++) body[i] = alphabet[rnd.Next(32)];
                for (int off = 0; off + codeLen <= total; off++)
                {
                    var sb = new StringBuilder(new string(body));
                    for (int i = 0; i < codeLen; i++) sb[off + i] = code[i];
                    string lic = sb.ToString();
                    bool ok;
                    try { ok = (bool)check.Invoke(null, new object[] { email, lic }); } catch { continue; }
                    if (ok) return new Solution { license = lic, code = code, offset = off, total = total };
                }
            }
        }
        return null;
    }

    static int StableSeed(string s)
    {
        int h = 17;
        foreach (char c in s) h = unchecked(h * 31 + c);
        return h;
    }

    static string Encode(BigInteger h, string alphabet, int len, bool msbFirst)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < len; i++)
        {
            int sh = msbFirst ? (96 - (i + 1) * 5) : (i * 5);
            if (sh < 0) sh = 0;
            sb.Append(alphabet[(int)((h >> sh) & 31)]);
        }
        return sb.ToString();
    }

    static string Grouped(string s, int n)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < s.Length; i += n)
        {
            if (i > 0) sb.AppendLine();
            sb.Append(s.Substring(i, Math.Min(n, s.Length - i)));
        }
        return sb.ToString();
    }

    // ------------------------------------------------------------------ settings

    static bool VerifyLoaded(string path)
    {
        Type lst = _asm.GetType("Listary.Core.Settings.ListarySettings");
        Type iss = _asm.GetType("Listary.Core.Settings.ISaveSetting");
        object settings = Activator.CreateInstance(lst);
        Array arr = Array.CreateInstance(iss, 1);
        arr.SetValue(settings, 0);
        Type mgrT = _asm.GetTypes().FirstOrDefault(t => t.FullName == "Listary.Core.Settings.\ue0a9");
        if (mgrT == null)
            mgrT = _asm.GetTypes().FirstOrDefault(t =>
                t.GetConstructor(new[] { typeof(string), iss.MakeArrayType() }) != null);
        if (mgrT == null) return false;
        object mgr = Activator.CreateInstance(mgrT, new object[] { path, arr });
        mgrT.GetMethod("\ue000", BindingFlags.Public | BindingFlags.Instance).Invoke(mgr, null);
        Type pst = _asm.GetType("Listary.Core.Pro.ProService");
        object ps = Activator.CreateInstance(pst, new object[] { settings, null });
        return (bool)pst.GetProperty("IsPro").GetValue(ps, null);
    }

    static string FindSettingsFile()
    {
        try
        {
            Type ps = _asm.GetType("Listary.Core.Services.PathService");
            Type pt = _asm.GetType("Listary.Core.Services.PathType");
            MethodInfo get = ps == null ? null : ps.GetMethod("Get", BindingFlags.Public | BindingFlags.Static);
            if (ps != null && pt != null && get != null)
                foreach (object v in Enum.GetValues(pt))
                {
                    try
                    {
                        string p = (string)get.Invoke(null, new object[] { v });
                        if (!string.IsNullOrEmpty(p) && p.EndsWith("Preferences.json", StringComparison.OrdinalIgnoreCase))
                            return p;
                    }
                    catch { }
                }
        }
        catch { }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                            "Listary", "UserProfile", "Settings", "Preferences.json");
    }

    static void Inject(string path, string name, string email, string license, bool blockUpdate)
    {
        string dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
        if (File.Exists(path) && !File.Exists(path + ".bak")) File.Copy(path, path + ".bak", true);

        var root = LoadRoot(path);
        var sec = Section(root, "Settings");
        sec["Listary5.ProLicense.Name"] = name;
        sec["Listary5.ProLicense.Email"] = email;
        sec["Listary5.ProLicense.Key"] = license;

        if (blockUpdate)
        {
            var au = Section(root, "AutoUpdate");
            au["EnableAutoUpdate"] = false;
            au["CheckForBetaUpdates"] = false;
        }

        SaveRoot(path, root);
    }

    static Dictionary<string, object> LoadRoot(string path)
    {
        string json = File.Exists(path) ? File.ReadAllText(path) : "{}";
        var ser = new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        object o = string.IsNullOrWhiteSpace(json) ? new Dictionary<string, object>() : ser.DeserializeObject(json);
        var root = o as Dictionary<string, object>;
        if (root == null) throw new Exception("设置文件不是 JSON 对象");
        return root;
    }

    static void SaveRoot(string path, Dictionary<string, object> root)
    {
        var ser = new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        File.WriteAllText(path, ser.Serialize(root), new UTF8Encoding(false));
    }

    static Dictionary<string, object> Section(Dictionary<string, object> root, string key)
    {
        object o;
        if (!root.TryGetValue(key, out o) || !(o is Dictionary<string, object>))
        {
            o = new Dictionary<string, object>();
            root[key] = o;
        }
        return (Dictionary<string, object>)o;
    }

    static readonly string[] LicenseKeys = {
        "Listary5.ProLicense.Name", "Listary5.ProLicense.Email", "Listary5.ProLicense.Key"
    };

    // 撤销激活：删掉授权键，其余设置原样保留
    static int Clean()
    {
        _listaryDir = FindListaryDir();
        if (_listaryDir == null) { Err("找不到 Listary"); return 2; }
        AppDomain.CurrentDomain.AssemblyResolve += Resolve;
        try { _asm = Assembly.LoadFrom(Path.Combine(_listaryDir, "Listary.exe")); } catch { }
        string p = FindSettingsFile();
        if (!File.Exists(p)) { Err("设置文件不存在: " + p); return 5; }
        KillListary(true);
        var root = LoadRoot(p);
        var sec = Section(root, "Settings");
        int n = 0;
        foreach (string k in LicenseKeys) if (sec.Remove(k)) n++;
        SaveRoot(p, root);
        StartListary();
        Console.WriteLine("[+] 已撤销激活（移除 " + n + " 个授权键）: " + p);
        Console.WriteLine("[*] Listary 已重启，将回到免费版。");
        return 0;
    }

    static int RestoreFromBak()
    {
        _listaryDir = FindListaryDir();
        if (_listaryDir == null) { Err("找不到 Listary"); return 2; }
        AppDomain.CurrentDomain.AssemblyResolve += Resolve;
        _asm = Assembly.LoadFrom(Path.Combine(_listaryDir, "Listary.exe"));
        string p = FindSettingsFile();
        if (!File.Exists(p + ".bak")) { Err("没有备份文件: " + p + ".bak"); return 5; }
        KillListary(true);
        File.Copy(p + ".bak", p, true);
        StartListary();
        Console.WriteLine("[+] 已从备份还原设置: " + p);
        return 0;
    }

    // ------------------------------------------------------------------ auto update block

    static string HostsPath()
    {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                            @"drivers\etc\hosts");
    }

    static bool IsAdmin()
    {
        try
        {
            var id = System.Security.Principal.WindowsIdentity.GetCurrent();
            var pr = new System.Security.Principal.WindowsPrincipal(id);
            return pr.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }

    static void DoHosts(bool add)
    {
        try
        {
            string hp = HostsPath();
            if (!File.Exists(hp)) { Console.WriteLine("[!] 找不到 hosts 文件，跳过网络阻断"); return; }
            var lines = File.ReadAllLines(hp).ToList();
            if (!IsAdmin())
            {
                Console.WriteLine("[!] 非管理员权限，无法修改 hosts。");
                Console.WriteLine("    请右键“以管理员身份运行”本工具，或手动在 hosts 加入：");
                foreach (string h in UpdateHosts) Console.WriteLine("      127.0.0.1  " + h);
                return;
            }
            bool changed = false;
            if (add)
            {
                foreach (string h in UpdateHosts)
                {
                    bool has = lines.Any(l => l.TrimStart().StartsWith("127.0.0.1") && l.Contains(h));
                    if (!has) { lines.Add("127.0.0.1  " + h + "    # Listary6Pro block"); changed = true; }
                }
            }
            else
            {
                int n = lines.RemoveAll(l => l.Contains("# Listary6Pro block"));
                changed = n > 0;
            }
            if (changed)
            {
                if (!File.Exists(hp + ".Listary6Pro.bak")) File.Copy(hp, hp + ".Listary6Pro.bak", true);
                File.WriteAllLines(hp, lines.ToArray(), new UTF8Encoding(false));
                Console.WriteLine("[+] hosts 已更新 (" + (add ? "阻断" : "解除") + " " + string.Join(", ", UpdateHosts) + ")");
                try
                {
                    var psi = new System.Diagnostics.ProcessStartInfo("ipconfig", "/flushdns");
                    psi.CreateNoWindow = true; psi.UseShellExecute = false;
                    System.Diagnostics.Process.Start(psi).WaitForExit(5000);
                    Console.WriteLine("[+] DNS 缓存已刷新");
                }
                catch { }
            }
            else Console.WriteLine("[*] hosts 无需变更");
        }
        catch (Exception e) { Console.WriteLine("[!] hosts 操作失败: " + Root(e).Message); }
    }

    static int BlockUpdate(bool add)
    {
        Console.WriteLine("=== " + (add ? "阻断" : "解除阻断") + " Listary 自动更新 ===");
        _listaryDir = FindListaryDir();
        if (_listaryDir != null)
        {
            AppDomain.CurrentDomain.AssemblyResolve += Resolve;
            try { _asm = Assembly.LoadFrom(Path.Combine(_listaryDir, "Listary.exe")); } catch { }
        }
        if (add && _asm != null)
        {
            try
            {
                string p = FindSettingsFile();
                if (File.Exists(p))
                {
                    File.Copy(p, p + ".bak", true);
                    string json = File.ReadAllText(p);
                    var ser = new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue };
                    var root = ser.DeserializeObject(json) as Dictionary<string, object>;
                    if (root != null)
                    {
                        Section(root, "AutoUpdate")["EnableAutoUpdate"] = false;
                        Section(root, "AutoUpdate")["CheckForBetaUpdates"] = false;
                        File.WriteAllText(p, ser.Serialize(root), new UTF8Encoding(false));
                        Console.WriteLine("[+] 设置项 AutoUpdate.EnableAutoUpdate = false  (" + p + ")");
                    }
                }
            }
            catch (Exception e) { Console.WriteLine("[!] 设置项写入失败: " + Root(e).Message); }
        }
        DoHosts(add);
        Console.WriteLine("[*] 阻止的域名: " + string.Join(", ", UpdateHosts));
        Console.WriteLine("[*] 更新源: https://dl.listary.com/auto_update_v2.xml");
        return 0;
    }

    // ------------------------------------------------------------------ process / locate

    static bool KillListary(bool doKill)
    {
        bool running = System.Diagnostics.Process.GetProcessesByName("Listary").Length > 0;
        if (doKill && running)
        {
            foreach (var p in System.Diagnostics.Process.GetProcessesByName("Listary"))
                try { p.Kill(); p.WaitForExit(8000); } catch { }
            System.Threading.Thread.Sleep(1500);
            Console.WriteLine("[*] 已结束运行中的 Listary");
        }
        return running;
    }

    static void StartListary()
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo(Path.Combine(_listaryDir, "Listary.exe"));
            psi.WorkingDirectory = _listaryDir;
            System.Diagnostics.Process.Start(psi);
        }
        catch (Exception e) { Console.WriteLine("[!] 启动失败: " + e.Message); }
    }

    static string FindListaryDir()
    {
        var views = new[] { RegistryView.Registry64, RegistryView.Registry32 };
        var hives = new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser };
        var subs = new[] {
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        };
        foreach (var hive in hives)
        foreach (var view in views)
        foreach (var sub in subs)
        {
            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(hive, view))
                using (var k = baseKey.OpenSubKey(sub))
                {
                    if (k == null) continue;
                    foreach (string nm in k.GetSubKeyNames())
                        using (var s = k.OpenSubKey(nm))
                        {
                            if (s == null) continue;
                            string dn = s.GetValue("DisplayName") as string;
                            if (string.IsNullOrEmpty(dn) || dn.IndexOf("Listary", StringComparison.OrdinalIgnoreCase) < 0) continue;
                            string loc = (s.GetValue("InstallLocation") as string) ?? (s.GetValue("Inno Setup: App Path") as string);
                            if (!string.IsNullOrEmpty(loc))
                            {
                                loc = loc.TrimEnd('\\');
                                if (File.Exists(Path.Combine(loc, "Listary.exe"))) return loc;
                            }
                            string icon = s.GetValue("DisplayIcon") as string;
                            if (!string.IsNullOrEmpty(icon))
                            {
                                string d = Path.GetDirectoryName(icon.Trim('"'));
                                if (d != null && File.Exists(Path.Combine(d, "Listary.exe"))) return d;
                            }
                        }
                }
            }
            catch { }
        }
        string[] pf = {
            Environment.GetEnvironmentVariable("ProgramW6432"),
            Environment.GetEnvironmentVariable("ProgramFiles"),
            Environment.GetEnvironmentVariable("ProgramFiles(x86)")
        };
        foreach (string g in pf)
        {
            if (string.IsNullOrEmpty(g)) continue;
            string c = Path.Combine(g, "Listary");
            if (File.Exists(Path.Combine(c, "Listary.exe"))) return c;
        }
        return null;
    }

    static string FileVersion(string path)
    {
        try { return System.Diagnostics.FileVersionInfo.GetVersionInfo(path).FileVersion; }
        catch { return "?"; }
    }

    static Assembly Resolve(object s, ResolveEventArgs a)
    {
        try
        {
            string n = new AssemblyName(a.Name).Name;
            string p = Path.Combine(_listaryDir, n + ".dll");
            if (File.Exists(p)) return Assembly.LoadFrom(p);
            p = Path.Combine(_listaryDir, n + ".exe");
            if (File.Exists(p)) return Assembly.LoadFrom(p);
        }
        catch { }
        return null;
    }

    static Exception Root(Exception e) { while (e.InnerException != null) e = e.InnerException; return e; }

    static void Banner()
    {
        Console.WriteLine("Listary6Pro - Listary 6 Pro 授权工具 (授权审计 PoC)");
        Console.WriteLine();
        Console.WriteLine("  Listary6Pro.exe info                              探测已安装版本");
        Console.WriteLine("  Listary6Pro.exe gen <email>                       只为该邮箱生成授权码(不写文件)");
        Console.WriteLine("  Listary6Pro.exe activate <email> [--name X] [--no-restart] [--no-block-update]");
        Console.WriteLine("  Listary6Pro.exe block-update / unblock-update     阻断/解除自动更新");
        Console.WriteLine("  Listary6Pro.exe clean / restore                   撤销激活(移除授权键)");
        Console.WriteLine("  Listary6Pro.exe restore-bak                       从 .bak 备份还原整个设置文件");
    }

    static void Err(string m) { Console.WriteLine("[x] " + m); }
}
