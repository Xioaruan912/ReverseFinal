using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Text;

// BabelDump - runtime recovery of Babel Obfuscator encrypted method bodies (v10 / BabelOut)
//   BabelDump.exe <asm> scan
//   BabelDump.exe <asm> dump <typeRegex> [methodRegex]
//   BabelDump.exe <asm> str <id>...
//   BabelDump.exe <asm> strs <start> <end>
internal static class BabelDump
{
    static string _dir;
    static Dictionary<ushort, OpCode> _ops = new Dictionary<ushort, OpCode>();
    static Type _dispType;
    static MethodInfo _disp;
    static object _singleton;
    static MethodInfo _resolve;
    static MethodInfo _strDec;
    static System.Collections.IList _toks;   // current dynamic token table

    static void Main(string[] args)
    {
        try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
        if (args.Length < 2) { Console.Error.WriteLine("usage: BabelDump <asm> <scan|dump|str|strs> [...]"); return; }
        string asmPath = Path.GetFullPath(args[0]);
        _dir = Path.GetDirectoryName(asmPath);
        AppDomain.CurrentDomain.AssemblyResolve += Resolve;
        BuildOps();
        Assembly asm = Assembly.LoadFrom(asmPath);
        Type[] types = SafeTypes(asm);

        foreach (Type t in types)
        {
            foreach (MethodInfo mi in SafeMethods(t))
            {
                if (!mi.IsStatic || mi.ReturnType != typeof(object)) continue;
                ParameterInfo[] ps = mi.GetParameters();
                if (ps.Length == 4 && ps[0].ParameterType == typeof(int) && ps[1].ParameterType == typeof(MethodBase)
                    && ps[2].ParameterType == typeof(object) && ps[3].ParameterType == typeof(object[]))
                { _dispType = t; _disp = mi; break; }
            }
            if (_disp != null) break;
        }
        if (_disp == null) { Console.Error.WriteLine("dispatcher not found"); return; }
        Console.WriteLine("# dispatcher: " + _dispType.FullName + "::" + _disp.Name + "  (0x" + _disp.MetadataToken.ToString("x8") + ")");

        foreach (FieldInfo f in _dispType.GetFields(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
            if (f.FieldType == _dispType) { _singleton = f.GetValue(null); break; }
        if (_singleton == null) { Console.Error.WriteLine("singleton not found"); return; }

        foreach (MethodInfo mi in SafeMethods(_dispType))
        {
            if (mi.IsStatic) continue;
            ParameterInfo[] ps = mi.GetParameters();
            if (ps.Length == 3 && ps[0].ParameterType == typeof(int) && ps[1].ParameterType == typeof(MethodBase) && ps[2].ParameterType == typeof(object))
            { _resolve = mi; break; }
        }
        if (_resolve == null) { Console.Error.WriteLine("resolver not found"); return; }
        Console.WriteLine("# resolver  : " + _resolve.Name + "  (0x" + _resolve.MetadataToken.ToString("x8") + ")");

        foreach (Type t in types)
            foreach (MethodInfo mi in SafeMethods(t))
            {
                if (!mi.IsStatic || mi.ReturnType != typeof(string)) continue;
                ParameterInfo[] ps = mi.GetParameters();
                if (ps.Length != 1 || ps[0].ParameterType != typeof(int)) continue;
                try
                {
                    string s = mi.Invoke(null, new object[] { 32725 }) as string;
                    if (s == "23456789ABCDEFGHJKLMNPQRSTUVWXYZ") { _strDec = mi; Console.WriteLine("# strdec    : " + t.FullName + "::" + mi.Name); break; }
                }
                catch { }
            }

        string cmd = args[1].ToLowerInvariant();
        if (cmd == "scan") { Scan(types); return; }
        if (cmd == "dump")
        {
            var rx = new System.Text.RegularExpressions.Regex(args[2], System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            var mr = args.Length > 3 ? new System.Text.RegularExpressions.Regex(args[3], System.Text.RegularExpressions.RegexOptions.IgnoreCase) : null;
            Dump(types, rx, mr); return;
        }
        if (cmd == "loadtest")
        {
            string prefsPath = args[2];
            Type lst = asm.GetType("Listary.Core.Settings.ListarySettings");
            Type iss = asm.GetType("Listary.Core.Settings.ISaveSetting");
            Console.WriteLine("# prefs   : " + prefsPath + "  exists=" + File.Exists(prefsPath));
            object settings = Activator.CreateInstance(lst);
            Array arr = Array.CreateInstance(iss, 1);
            arr.SetValue(settings, 0);
            Type mgrT = asm.GetType("Listary.Core.Settings.");
            object mgr = Activator.CreateInstance(mgrT, new object[] { prefsPath, arr });
            mgrT.GetMethod("").Invoke(mgr, null);
            object em = lst.GetProperty("Listary5LicenseEmail").GetValue(settings, null);
            object ky = lst.GetProperty("Listary5LicenseKey").GetValue(settings, null);
            Console.WriteLine("loaded email = [" + (em == null ? "<null>" : em.ToString()) + "]");
            Console.WriteLine("loaded keylen= " + (ky == null ? -1 : ((string)ky).Length));
            Type pst = asm.GetType("Listary.Core.Pro.ProService");
            object ps = Activator.CreateInstance(pst, new object[] { settings, null });
            Console.WriteLine("ProService.IsPro = " + pst.GetProperty("IsPro").GetValue(ps, null));
            return;
        }
        if (cmd == "savejson")
        {
            string email = args[2];
            string key = args[3];
            Type lst = asm.GetType("Listary.Core.Settings.ListarySettings");
            object settings = Activator.CreateInstance(lst);
            lst.GetProperty("Listary5LicenseName").SetValue(settings, "Audit User", null);
            lst.GetProperty("Listary5LicenseEmail").SetValue(settings, email, null);
            lst.GetProperty("Listary5LicenseKey").SetValue(settings, key, null);
            MethodInfo save = null;
            for (Type bt = lst; bt != null && save == null; bt = bt.BaseType)
                save = bt.GetMethod("SaveSetting", BindingFlags.Public | BindingFlags.Instance);
            object tok = save.Invoke(settings, null);
            Console.WriteLine("--- section name: " + (string)lst.GetProperty("SettingSectionName", BindingFlags.Public | BindingFlags.Instance | BindingFlags.FlattenHierarchy).GetValue(settings, null));
            Console.WriteLine(tok.ToString());
            return;
        }
        if (cmd == "pro")
        {
            string email = args[2];
            string key = args[3];
            Type lst = asm.GetType("Listary.Core.Settings.ListarySettings");
            object settings = Activator.CreateInstance(lst);
            lst.GetProperty("Listary5LicenseName").SetValue(settings, "Audit User", null);
            lst.GetProperty("Listary5LicenseEmail").SetValue(settings, email, null);
            lst.GetProperty("Listary5LicenseKey").SetValue(settings, key, null);
            Console.WriteLine("settings.Listary5LicenseEmail = " + lst.GetProperty("Listary5LicenseEmail").GetValue(settings, null));
            Console.WriteLine("settings.Listary5LicenseKey.len = " + ((string)lst.GetProperty("Listary5LicenseKey").GetValue(settings, null)).Length);
            Type pst = asm.GetType("Listary.Core.Pro.ProService");
            object ps = Activator.CreateInstance(pst, new object[] { settings, null });
            Console.WriteLine("ProService.IsPro      = " + pst.GetProperty("IsPro").GetValue(ps, null));
            Console.WriteLine("ProService.LicenseEmail = " + pst.GetProperty("LicenseEmail").GetValue(ps, null));
            PropertyInfo lt = pst.GetProperty("LicensedTo");
            if (lt != null) Console.WriteLine("ProService.LicensedTo = " + lt.GetValue(ps, null));
            return;
        }
        if (cmd == "check")
        {
            MethodInfo ck = null;
            foreach (Type t in types)
                foreach (MethodInfo mi in SafeMethods(t))
                    if (t.FullName == "Listary.Core.Pro.LicenseChecker" && mi.Name == "CheckLicense") ck = mi;
            if (ck == null) { Console.WriteLine("CheckLicense not found"); return; }
            try
            {
                bool r = (bool)ck.Invoke(null, new object[] { args[2], args[3] });
                Console.WriteLine("CheckLicense(" + args[2] + ", len=" + args[3].Length + ") = " + r);
            }
            catch (Exception ex)
            {
                Exception c = ex;
                while (c != null) { Console.WriteLine("EXC " + c.GetType().FullName + " | msg-len=" + (c.Message == null ? -1 : c.Message.Length)); c = c.InnerException; }
                try
                {
                    System.Diagnostics.StackTrace st = new System.Diagnostics.StackTrace(Root(ex), false);
                    for (int fi = 0; fi < st.FrameCount && fi < 12; fi++)
                    {
                        MethodBase fm = st.GetFrame(fi).GetMethod();
                        if (fm == null) continue;
                        Console.WriteLine("    at " + Escape(fm.DeclaringType == null ? "?" : fm.DeclaringType.FullName) + "::" + Escape(fm.Name));
                    }
                }
                catch { }
            }
            return;
        }
        if (cmd == "str")
        {
            for (int i = 2; i < args.Length; i++) Console.WriteLine(args[i] + " => " + Show(DecStr(int.Parse(args[i]))));
            return;
        }
        if (cmd == "strs")
        {
            int a = int.Parse(args[2]), b = int.Parse(args[3]);
            for (int i = a; i <= b; i++) { string s = DecStr(i); if (s != null) Console.WriteLine(i + " => " + Show(s)); }
            return;
        }
    }

    static string Show(string s) { return s == null ? "<null>" : "\"" + s.Replace("\\", "\\\\").Replace("\r", "\\r").Replace("\n", "\\n").Replace("\"", "\\\"") + "\""; }
    static Exception Root(Exception e) { while (e.InnerException != null) e = e.InnerException; return e; }

    static Assembly Resolve(object s, ResolveEventArgs a)
    {
        try
        {
            string n = new AssemblyName(a.Name).Name;
            string p = Path.Combine(_dir, n + ".dll");
            if (File.Exists(p)) return Assembly.LoadFrom(p);
            p = Path.Combine(_dir, n + ".exe");
            if (File.Exists(p)) return Assembly.LoadFrom(p);
        }
        catch { }
        return null;
    }

    static Type[] SafeTypes(Assembly a)
    {
        try { return a.GetTypes(); }
        catch (ReflectionTypeLoadException e) { return e.Types.Where(t => t != null).ToArray(); }
    }

    static IEnumerable<MethodInfo> SafeMethods(Type t)
    {
        try { return t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly); }
        catch { return new MethodInfo[0]; }
    }

    static IEnumerable<ConstructorInfo> SafeCtors(Type t)
    {
        try { return t.GetConstructors(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly); }
        catch { return new ConstructorInfo[0]; }
    }

    static string DecStr(int id)
    {
        if (_strDec == null) return null;
        try { return (string)_strDec.Invoke(null, new object[] { id }); } catch { return null; }
    }

    static int? StubId(MethodBase mb)
    {
        MethodBody b = null;
        try { b = mb.GetMethodBody(); } catch { return null; }
        if (b == null) return null;
        byte[] il = b.GetILAsByteArray();
        int? id = null; int? lastLdc = null; bool sawDisp = false;
        for (int i = 0; i < il.Length; )
        {
            int p = i; OpCode op; int adv;
            if (!ReadOp(il, ref p, out op, out adv)) { i++; continue; }
            if (op.OperandType == OperandType.InlineMethod)
            {
                int tok = BitConverter.ToInt32(il, p);
                try { if (mb.Module.ResolveMethod(tok) == (MethodBase)_disp) { sawDisp = true; id = lastLdc; } } catch { }
            }
            switch (op.Value)
            {
                case 0x16: lastLdc = 0; break; case 0x17: lastLdc = 1; break; case 0x18: lastLdc = 2; break;
                case 0x19: lastLdc = 3; break; case 0x1a: lastLdc = 4; break; case 0x1b: lastLdc = 5; break;
                case 0x1c: lastLdc = 6; break; case 0x1d: lastLdc = 7; break; case 0x1e: lastLdc = 8; break;
                case 0x15: lastLdc = -1; break;
                case 0x1f: lastLdc = (int)(sbyte)il[p]; break;
                case 0x20: lastLdc = BitConverter.ToInt32(il, p); break;
            }
            i = p + adv;
        }
        return sawDisp ? id : null;
    }

    static void Scan(Type[] types)
    {
        int n = 0;
        foreach (Type t in types)
        {
            foreach (MethodInfo mi in SafeMethods(t))
            {
                int? id = StubId(mi);
                if (id == null) continue; n++;
                Console.WriteLine(string.Format("PROTECTED 0x{0:x8}  id={1,-9} {2}::{3}({4})", mi.MetadataToken, id, t.FullName, mi.Name,
                    string.Join(", ", mi.GetParameters().Select(p => p.ParameterType.Name).ToArray())));
            }
            foreach (ConstructorInfo ci in SafeCtors(t))
            {
                int? id = StubId(ci);
                if (id == null) continue; n++;
                Console.WriteLine(string.Format("PROTECTED 0x{0:x8}  id={1,-9} {2}::.ctor", ci.MetadataToken, id, t.FullName));
            }
        }
        Console.WriteLine("# total protected methods: " + n);
    }

    static void Dump(Type[] types, System.Text.RegularExpressions.Regex trx, System.Text.RegularExpressions.Regex mrx)
    {
        Directory.CreateDirectory("dump");
        foreach (Type t in types.OrderBy(x => x.FullName))
        {
            if (!trx.IsMatch(t.FullName ?? t.Name)) continue;
            foreach (MethodInfo mi in SafeMethods(t))
            {
                if (mrx != null && !mrx.IsMatch(mi.Name)) continue;
                int? id = StubId(mi); if (id == null) continue;
                DumpOne(t, mi, id.Value);
            }
            foreach (ConstructorInfo ci in SafeCtors(t))
            {
                int? id = StubId(ci); if (id == null) continue;
                DumpOne(t, ci, id.Value);
            }
        }
    }

    static void DumpOne(Type t, MethodBase mb, int id)
    {
        Console.WriteLine("=== " + Escape(t.FullName) + "::" + Escape(mb.Name) + "  id=" + id);
        object invoker;
        try { invoker = _resolve.Invoke(_singleton, new object[] { id, null, null }); }
        catch (Exception e) { Console.WriteLine("   resolve THROW: " + Root(e).Message); return; }
        if (invoker == null) { Console.WriteLine("   resolve -> null"); return; }

        MethodInfo dm = null;
        foreach (FieldInfo f in invoker.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
        {
            object v = null; try { v = f.GetValue(invoker); } catch { }
            if (v is Delegate) { dm = ((Delegate)v).Method; break; }
        }
        if (dm == null) { Console.WriteLine("   no delegate in " + invoker.GetType().FullName); return; }

        byte[] il = ExtractBody(dm);
        if (il == null) { Console.WriteLine("   IL extraction failed"); return; }
        if (_toks != null)
        {
            for (int z = 0; z < _toks.Count; z++)
            {
                object oo = _toks[z];
                string d;
                if (oo == null) d = "null";
                else if (oo is string) d = "str " + Show((string)oo);
                else if (oo is byte[]) d = "SIG[" + ((byte[])oo).Length + "]";
                else d = FmtTokObj(oo, z);
                Console.WriteLine("   tok[" + z + "] = " + d);
            }
        }
        string safe = Safe(t.FullName + "." + mb.Name);
        File.WriteAllBytes("dump/" + safe + ".ilraw", il);
        Console.WriteLine("   IL bytes: " + il.Length + "  tokens: " + (_toks == null ? 0 : _toks.Count));
        Disasm(il, mb.Module, t);
    }

    static string Safe(string s) { return s.Replace('\\', '_').Replace('/', '_').Replace(':', '_').Replace('*', '_').Replace('?', '_').Replace('"', '_').Replace('<', '_').Replace('>', '_'); }

    static byte[] ExtractBody(MethodInfo dm)
    {
        try
        {
            object owner = dm;
            if (dm.GetType().Name == "RTDynamicMethod")
            {
                FieldInfo fo = dm.GetType().GetField("m_owner", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
                if (fo != null) owner = fo.GetValue(dm);
            }
            object res = GetField(owner, "m_resolver");
            byte[] code = res == null ? null : (byte[])GetField(res, "m_code");
            object dii = GetField(owner, "m_DynamicILInfo");
            object scope = dii == null ? null : GetField(dii, "m_scope");
            if (scope == null && dii != null) scope = GetField(dii, "m_scope");
            _toks = (System.Collections.IList)(scope == null ? null : GetField(scope, "m_tokens"));
            if (_toks == null && res != null) { /* nothing */ }
            return code;
        }
        catch (Exception e) { Console.WriteLine("   IL extract err: " + Root(e).Message); return null; }
    }

    static object GetField(object o, string name)
    {
        if (o == null) return null;
        FieldInfo f = o.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
        return f == null ? null : f.GetValue(o);
    }

    static void BuildOps()
    {
        foreach (FieldInfo f in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            if (f.FieldType != typeof(OpCode)) continue;
            OpCode o = (OpCode)f.GetValue(null);
            _ops[(ushort)o.Value] = o;
        }
    }

    static bool ReadOp(byte[] il, ref int i, out OpCode op, out int adv)
    {
        op = default(OpCode); adv = 0;
        if (i >= il.Length) return false;
        ushort v = il[i];
        if (v == 0xFE) { if (i + 1 >= il.Length) return false; v = (ushort)(0xFE00 | il[i + 1]); }
        if (!_ops.TryGetValue(v, out op)) { i += (v >= 0xFE00) ? 2 : 1; return false; }
        i += (v >= 0xFE00) ? 2 : 1;
        switch (op.OperandType)
        {
            case OperandType.InlineNone: adv = 0; break;
            case OperandType.ShortInlineBrTarget:
            case OperandType.ShortInlineI:
            case OperandType.ShortInlineVar: adv = 1; break;
            case OperandType.InlineVar: adv = 2; break;
            case OperandType.InlineBrTarget:
            case OperandType.InlineField:
            case OperandType.InlineI:
            case OperandType.InlineMethod:
            case OperandType.InlineSig:
            case OperandType.InlineString:
            case OperandType.InlineTok:
            case OperandType.InlineType:
            case OperandType.ShortInlineR: adv = 4; break;
            case OperandType.InlineI8:
            case OperandType.InlineR: adv = 8; break;
            case OperandType.InlineSwitch:
                adv = (i + 3 < il.Length) ? 4 + 4 * BitConverter.ToInt32(il, i) : 4;
                break;
        }
        return true;
    }

    static void Disasm(byte[] il, Module mod, Type scope)
    {
        for (int i = 0; i < il.Length; )
        {
            int p = i; OpCode op; int adv;
            if (!ReadOp(il, ref p, out op, out adv)) { i++; continue; }
            string operand = "";
            switch (op.OperandType)
            {
                case OperandType.ShortInlineI: operand = ((sbyte)il[p]).ToString(); break;
                case OperandType.InlineI: operand = BitConverter.ToInt32(il, p).ToString(); break;
                case OperandType.InlineI8: operand = BitConverter.ToInt64(il, p).ToString(); break;
                case OperandType.ShortInlineR: operand = BitConverter.ToSingle(il, p).ToString("R"); break;
                case OperandType.InlineR: operand = BitConverter.ToDouble(il, p).ToString("R"); break;
                case OperandType.ShortInlineVar: operand = "V" + il[p]; break;
                case OperandType.InlineVar: operand = "V" + BitConverter.ToUInt16(il, p); break;
                case OperandType.ShortInlineBrTarget: operand = "IL_" + (p + 1 + (sbyte)il[p]).ToString("x4"); break;
                case OperandType.InlineBrTarget: operand = "IL_" + (p + 4 + BitConverter.ToInt32(il, p)).ToString("x4"); break;
                case OperandType.InlineSwitch:
                {
                    int n = BitConverter.ToInt32(il, p); StringBuilder sb = new StringBuilder();
                    for (int k = 0; k < n; k++) sb.Append("IL_" + (p + 4 + 4 * n + BitConverter.ToInt32(il, p + 4 + 4 * k)).ToString("x4") + " ");
                    operand = sb.ToString(); break;
                }
                case OperandType.InlineField:
                case OperandType.InlineMethod:
                case OperandType.InlineType:
                case OperandType.InlineTok:
                case OperandType.InlineString:
                case OperandType.InlineSig:
                {
                    int tok = BitConverter.ToInt32(il, p);
                    operand = FmtTok(tok, mod, scope);
                    break;
                }
                default: operand = ""; break;
            }
            Console.WriteLine(string.Format("    IL_{0:x4}: {1,-12} {2}", i, op.Name, operand));
            i = p + adv;
        }
    }

    static string FmtTokObj(object o, int idx)
    {
        if (o is MethodBase) { MethodBase m = (MethodBase)o; return "M " + Escape(m.DeclaringType == null ? "?" : m.DeclaringType.FullName) + "::" + Escape(m.Name); }
        if (o is FieldInfo) { FieldInfo f = (FieldInfo)o; return "F " + Escape(f.DeclaringType == null ? "?" : f.DeclaringType.FullName) + "::" + Escape(f.Name); }
        if (o is Type) return "T " + Escape(((Type)o).FullName);
        if (o is RuntimeMethodHandle) { try { MethodBase m = MethodBase.GetMethodFromHandle((RuntimeMethodHandle)o); return "M " + Escape(m.DeclaringType.FullName) + "::" + Escape(m.Name); } catch { return "MH"; } }
        if (o is RuntimeFieldHandle) { try { FieldInfo f = FieldInfo.GetFieldFromHandle((RuntimeFieldHandle)o); return "F " + Escape(f.DeclaringType.FullName) + "::" + Escape(f.Name); } catch { return "FH"; } }
        foreach (FieldInfo iz in o.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
        {
            object iv = null; try { iv = iz.GetValue(o); } catch { }
            if (iv is FieldInfo) { FieldInfo f = (FieldInfo)iv; return "F " + Escape(f.DeclaringType == null ? "?" : f.DeclaringType.FullName) + "::" + Escape(f.Name); }
            if (iv is MethodBase) { MethodBase m = (MethodBase)iv; return "M " + Escape(m.DeclaringType == null ? "?" : m.DeclaringType.FullName) + "::" + Escape(m.Name); }
            if (iv is RuntimeFieldHandle) { try { FieldInfo f = FieldInfo.GetFieldFromHandle((RuntimeFieldHandle)iv); return "F " + Escape(f.DeclaringType.FullName) + "::" + Escape(f.Name); } catch { } }
            if (iv is RuntimeMethodHandle) { try { MethodBase m = MethodBase.GetMethodFromHandle((RuntimeMethodHandle)iv); return "M " + Escape(m.DeclaringType.FullName) + "::" + Escape(m.Name); } catch { } }
        }
        return o.GetType().FullName;
    }

    static string FmtTok(int tok, Module mod, Type scope)
    {
        string raw = "raw=0x" + tok.ToString("x8") + " ";
        return raw + FmtTok2(tok, mod, scope);
    }
    static string FmtTok2(int tok, Module mod, Type scope)
    {
        // dynamic IL token table
        if (_toks != null)
        {
            int idx = (tok & 0x00FFFFFF);
            if (idx >= 0 && idx < _toks.Count)
            {
                object o = _toks[idx];
                if (o == null) return "dyn[" + idx + "]=null";
                if (o is string) return "dyn[" + idx + "] str=" + Show((string)o);
                if (o is MethodBase) { MethodBase m = (MethodBase)o; return "dyn[" + idx + "] " + Escape(m.DeclaringType == null ? "?" : m.DeclaringType.FullName) + "::" + Escape(m.Name); }
                if (o is FieldInfo) { FieldInfo f = (FieldInfo)o; return "dyn[" + idx + "] " + Escape(f.DeclaringType == null ? "?" : f.DeclaringType.FullName) + "::" + Escape(f.Name); }
                if (o is Type) return "dyn[" + idx + "] " + Escape(((Type)o).FullName);
                if (o is byte[]) return "dyn[" + idx + "] sign";
                if (o is RuntimeMethodHandle)
                {
                    try { MethodBase mm = MethodBase.GetMethodFromHandle((RuntimeMethodHandle)o); return Escape(mm.DeclaringType.FullName) + "::" + Escape(mm.Name); }
                    catch { return "dyn[" + idx + "] mh"; }
                }
                if (o is RuntimeFieldHandle)
                {
                    try { FieldInfo ff = FieldInfo.GetFieldFromHandle((RuntimeFieldHandle)o); return Escape(ff.DeclaringType.FullName) + "::" + Escape(ff.Name); }
                    catch { return "dyn[" + idx + "] fh"; }
                }
                foreach (FieldInfo iz in o.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
                {
                    object iv = null; try { iv = iz.GetValue(o); } catch { }
                    if (iv is FieldInfo) { FieldInfo ff = (FieldInfo)iv; return Escape(ff.DeclaringType.FullName) + "::" + Escape(ff.Name); }
                    if (iv is MethodBase) { MethodBase mm = (MethodBase)iv; return Escape(mm.DeclaringType.FullName) + "::" + Escape(mm.Name); }
                    if (iv is RuntimeFieldHandle) { try { FieldInfo ff = FieldInfo.GetFieldFromHandle((RuntimeFieldHandle)iv); return Escape(ff.DeclaringType.FullName) + "::" + Escape(ff.Name); } catch { } }
                    if (iv is RuntimeMethodHandle) { try { MethodBase mm = MethodBase.GetMethodFromHandle((RuntimeMethodHandle)iv); return Escape(mm.DeclaringType.FullName) + "::" + Escape(mm.Name); } catch { } }
                }
                return "dyn[" + idx + "] " + o.GetType().FullName;
            }
            return "dyn[?] tok 0x" + tok.ToString("x8");
        }
        try
        {
            MemberInfo mi = mod.ResolveMember(tok, scope.GetGenericArguments(), null);
            return Escape(mi.DeclaringType == null ? "" : mi.DeclaringType.FullName) + "::" + Escape(mi.Name);
        }
        catch { return "tok 0x" + tok.ToString("x8"); }
    }

    static string Escape(string s)
    {
        if (string.IsNullOrEmpty(s)) return "<empty>";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s) { if (c < 0x21 || c > 0x7e) sb.Append("\\u" + ((int)c).ToString("x4")); else sb.Append(c); }
        return sb.ToString();
    }
}
