using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Text;
using System.Text.RegularExpressions;

// NetDump - offline .NET metadata + IL dumper (no external deps, .NET Framework 4.x)
// Usage:
//   NetDump.exe <asm> types [regex]        list types (and members counts)
//   NetDump.exe <asm> type   <regex>       IL of all methods in matching types
//   NetDump.exe <asm> method <regex>       IL of matching methods (Type::Method)
//   NetDump.exe <asm> fields <regex>       list fields of matching types
//   NetDump.exe <asm> strings              all user string literals
internal static class NetDump
{
    static Dictionary<ushort, OpCode> _ops = new Dictionary<ushort, OpCode>();
    static Dictionary<short, string> _opNames = new Dictionary<short, string>();
    static string _dir;

    static void Main(string[] args)
    {
        try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
        if (args.Length < 2) { Console.Error.WriteLine("usage: NetDump <asm> <cmd> [arg]"); return; }
        string asmPath = Path.GetFullPath(args[0]);
        _dir = Path.GetDirectoryName(asmPath);
        AppDomain.CurrentDomain.AssemblyResolve += Resolve;
        BuildOpTable();

        Assembly asm = Assembly.LoadFrom(asmPath);
        string cmd = args[1].ToLowerInvariant();
        string arg = args.Length > 2 ? args[2] : null;
        Regex rx = (arg == null) ? null : new Regex(arg, RegexOptions.IgnoreCase);

        Type[] types;
        try { types = asm.GetTypes(); }
        catch (ReflectionTypeLoadException e) { types = e.Types.Where(t => t != null).ToArray(); }

        if (cmd == "res")
        {
            foreach (string rn in asm.GetManifestResourceNames())
            {
                Console.WriteLine("# resource: " + rn);
                Stream st = asm.GetManifestResourceStream(rn);
                var rr = new System.Resources.ResourceReader(st);
                var e = rr.GetEnumerator();
                while (e.MoveNext())
                {
                    string v = e.Value as string;
                    if (v != null && (rx == null || rx.IsMatch(e.Key.ToString()) || rx.IsMatch(v)))
                        Console.WriteLine(e.Key + " = " + v);
                }
            }
            return;
        }
        switch (cmd)
        {
            case "types": DumpTypes(types, rx); break;
            case "type": DumpTypeIL(types, rx); break;
            case "method": DumpMethodIL(types, rx); break;
            case "fields": DumpFields(types, rx); break;
            case "strings": DumpStrings(types, asm); break;
            default: Console.Error.WriteLine("unknown cmd " + cmd); break;
        }
    }

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

    public static string Esc(string s)
    {
        if (string.IsNullOrEmpty(s)) return "<empty>";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c < 0x21 || c > 0x7e) sb.Append("\\u" + ((int)c).ToString("x4"));
            else sb.Append(c);
        }
        return sb.ToString();
    }

    static void BuildOpTable()
    {
        foreach (FieldInfo f in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            if (f.FieldType != typeof(OpCode)) continue;
            OpCode o = (OpCode)f.GetValue(null);
            _ops[(ushort)o.Value] = o;
            _opNames[o.Value] = o.Name;
        }
    }

    static void DumpTypes(Type[] types, Regex rx)
    {
        foreach (Type t in types.OrderBy(x => x.FullName))
        {
            if (rx != null && !rx.IsMatch(t.FullName ?? t.Name)) continue;
            Console.WriteLine(Desc(t));
        }
    }

    static string Desc(Type t)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append(t.IsInterface ? "interface " : (t.IsEnum ? "enum " : (t.IsValueType ? "struct " : "class ")));
        sb.Append(Esc(t.FullName));
        if (t.BaseType != null && t.BaseType != typeof(object)) sb.Append(" : " + Esc(t.BaseType.FullName));
        int m = 0; try { m = t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).Length; } catch { }
        sb.Append("  [methods=" + m + "]");
        return sb.ToString();
    }

    static void DumpFields(Type[] types, Regex rx)
    {
        foreach (Type t in types.OrderBy(x => x.FullName))
        {
            if (rx != null && !rx.IsMatch(t.FullName ?? t.Name)) continue;
            Console.WriteLine("### " + Esc(t.FullName));
            FieldInfo[] fs;
            try { fs = t.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly); }
            catch { continue; }
            foreach (FieldInfo f in fs)
            {
                string extra = "";
                if (f.IsLiteral) { try { extra = " = " + f.GetRawConstantValue(); } catch { } }
                Console.WriteLine("   " + (f.IsStatic ? "static " : "") + Esc(f.FieldType.Name) + " " + Esc(f.Name) + extra);
            }
            PropertyInfo[] pps;
            try { pps = t.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly); }
            catch { continue; }
            foreach (PropertyInfo p in pps)
            {
                string tn = "?";
                try { tn = p.PropertyType.Name; } catch { }
                Console.WriteLine("   prop " + Esc(tn) + " " + Esc(p.Name));
            }
        }
    }

    static void DumpTypeIL(Type[] types, Regex rx)
    {
        foreach (Type t in types.OrderBy(x => x.FullName))
        {
            if (rx != null && !rx.IsMatch(t.FullName ?? t.Name)) continue;
            Console.WriteLine("=========================================================");
            Console.WriteLine("TYPE " + Esc(t.FullName));
            MethodBase[] ms;
            try { ms = t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).Cast<MethodBase>()
                     .Concat(t.GetConstructors(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)).ToArray(); }
            catch { continue; }
            foreach (MethodBase mb in ms) PrintIL(t, mb, null);
        }
    }

    static void DumpMethodIL(Type[] types, Regex rx)
    {
        foreach (Type t in types.OrderBy(x => x.FullName))
        {
            MethodBase[] ms;
            try { ms = t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).Cast<MethodBase>()
                     .Concat(t.GetConstructors(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)).ToArray(); }
            catch { continue; }
            foreach (MethodBase mb in ms)
            {
                string full = t.FullName + "::" + mb.Name;
                if (rx != null && !rx.IsMatch(full)) continue;
                PrintIL(t, mb, full);
            }
        }
    }

    static void DumpStrings(Type[] types, Assembly asm)
    {
        Module mod = asm.ManifestModule;
        HashSet<string> seen = new HashSet<string>();
        foreach (Type t in types)
        {
            MethodBase[] ms;
            try { ms = t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly).Cast<MethodBase>()
                     .Concat(t.GetConstructors(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)).ToArray(); }
            catch { continue; }
            foreach (MethodBase mb in ms)
            {
                byte[] il;
                try { il = mb.GetMethodBody() == null ? null : mb.GetMethodBody().GetILAsByteArray(); }
                catch { il = null; }
                if (il == null) continue;
                for (int i = 0; i < il.Length; )
                {
                    int off = i;
                    OpCode op; int adv;
                    if (!ReadOp(il, ref i, out op, out adv)) break;
                    if (adv > 0) i += adv;
                    if (op.OperandType == OperandType.InlineString)
                    {
                        int tok = BitConverter.ToInt32(il, off + (op.Size == 2 ? 2 : 1));
                        string s = null;
                        try { s = mod.ResolveString(tok); } catch { }
                        if (s != null && seen.Add(s)) Console.WriteLine(s);
                    }
                }
            }
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
                if (i + 3 < il.Length) adv = 4 + 4 * BitConverter.ToInt32(il, i);
                else adv = 4;
                break;
            default: adv = 0; break;
        }
        return true;
    }

    static void PrintIL(Type t, MethodBase mb, string header)
    {
        MethodBody b = null;
        try { b = mb.GetMethodBody(); } catch { }
        Console.WriteLine();
        Console.WriteLine("--- " + Esc(t.FullName) + "::" + Esc(mb.Name));
        try
        {
            Console.WriteLine("    sig  : " + Sig(mb));
        }
        catch { }
        if (b == null) { Console.WriteLine("    (no body)"); return; }
        byte[] il = b.GetILAsByteArray();
        Module mod = t.Module;
        Dictionary<int, string> labels = new Dictionary<int, string>();
        for (int i = 0; i < il.Length; )
        {
            int off = i; int p = i;
            OpCode op; int adv;
            if (!ReadOp(il, ref p, out op, out adv)) break;
            if (op.FlowControl == FlowControl.Branch || op.FlowControl == FlowControl.Cond_Branch)
            {
                if (op.OperandType == OperandType.ShortInlineBrTarget)
                    labels[off + (op.Size == 2 ? 2 : 1) + 1 + (sbyte)il[p]] = "L_" + off.ToString("x4");
                else if (op.OperandType == OperandType.InlineBrTarget)
                    labels[off + (op.Size == 2 ? 2 : 1) + 4 + BitConverter.ToInt32(il, p)] = "L_" + off.ToString("x4");
                else if (op.OperandType == OperandType.InlineSwitch)
                {
                    int n = BitConverter.ToInt32(il, p); int baseOff = p + 4 + 4 * n;
                    for (int k = 0; k < n; k++)
                        labels[baseOff + BitConverter.ToInt32(il, p + 4 + 4 * k)] = "L_" + off.ToString("x4") + "_" + k;
                }
            }
            i = p + adv;
        }
        for (int i = 0; i < il.Length; )
        {
            int off = i; int p = i;
            OpCode op; int adv;
            if (!ReadOp(il, ref p, out op, out adv)) { i++; continue; }
            string operand = "";
            switch (op.OperandType)
            {
                case OperandType.ShortInlineI:
                    operand = ((sbyte)il[p]).ToString(); break;
                case OperandType.InlineI:
                    operand = BitConverter.ToInt32(il, p).ToString(); break;
                case OperandType.InlineI8:
                    operand = BitConverter.ToInt64(il, p).ToString(); break;
                case OperandType.ShortInlineR:
                    operand = BitConverter.ToSingle(il, p).ToString("R"); break;
                case OperandType.InlineR:
                    operand = BitConverter.ToDouble(il, p).ToString("R"); break;
                case OperandType.ShortInlineVar:
                    operand = "V" + il[p]; break;
                case OperandType.InlineVar:
                    operand = "V" + BitConverter.ToUInt16(il, p); break;
                case OperandType.ShortInlineBrTarget:
                {
                    int tgt = p + 1 + (sbyte)il[p];
                    operand = "IL_" + tgt.ToString("x4"); if (labels.ContainsKey(tgt)) operand += " (" + labels[tgt] + ")";
                    break;
                }
                case OperandType.InlineBrTarget:
                {
                    int tgt = p + 4 + BitConverter.ToInt32(il, p);
                    operand = "IL_" + tgt.ToString("x4"); if (labels.ContainsKey(tgt)) operand += " (" + labels[tgt] + ")";
                    break;
                }
                case OperandType.InlineSwitch:
                {
                    int n = BitConverter.ToInt32(il, p);
                    StringBuilder sb = new StringBuilder();
                    for (int k = 0; k < n; k++)
                    {
                        int tgt = p + 4 + 4 * n + BitConverter.ToInt32(il, p + 4 + 4 * k);
                        sb.Append("IL_" + tgt.ToString("x4") + " ");
                    }
                    operand = sb.ToString(); break;
                }
                case OperandType.InlineString:
                {
                    int tok = BitConverter.ToInt32(il, p);
                    try { operand = "\"" + mod.ResolveString(tok) + "\""; } catch { operand = "tok " + tok.ToString("x8"); }
                    break;
                }
                case OperandType.InlineField:
                case OperandType.InlineMethod:
                case OperandType.InlineType:
                case OperandType.InlineTok:
                {
                    int tok = BitConverter.ToInt32(il, p);
                    operand = ResolveMember(mod, tok, op.OperandType, t);
                    break;
                }
                case OperandType.InlineSig:
                {
                    int tok = BitConverter.ToInt32(il, p);
                    try { byte[] sg = mod.ResolveSignature(tok); operand = "sig " + BitConverter.ToString(sg); } catch { operand = "sig tok " + tok.ToString("x8"); }
                    break;
                }
            }
            string lbl = labels.ContainsKey(off) ? labels[off] : null;
            string line = string.Format("    IL_{0:x4}: {1,-12} {2}", off, op.Name, operand);
            if (lbl != null) line = "  " + lbl + ":\n" + line;
            Console.WriteLine(line);
            i = p + adv;
        }
    }

    static string ResolveMember(Module mod, int tok, OperandType ot, Type scope)
    {
        try
        {
            if (ot == OperandType.InlineField)
            {
                FieldInfo f = mod.ResolveField(tok, scope.GetGenericArguments(), null);
                return "[" + Esc(f.DeclaringType.Name) + "] " + Esc(f.DeclaringType.FullName) + "::" + Esc(f.Name);
            }
            if (ot == OperandType.InlineMethod)
            {
                MethodBase m = mod.ResolveMethod(tok, scope.GetGenericArguments(), null);
                return "[" + Esc(m.DeclaringType.Name) + "] " + Esc(m.DeclaringType.FullName) + "::" + Esc(m.Name) + "(" + Sig(m) + ") @asm=" + (m.Module!=null&&m.Module.Assembly!=null?m.Module.Assembly.GetName().Name:"?") + " tok=" + tok.ToString("x8");
            }
            if (ot == OperandType.InlineType)
            {
                Type t = mod.ResolveType(tok, scope.GetGenericArguments(), null);
                return Esc(t.FullName);
            }
            MemberInfo mi = mod.ResolveMember(tok, scope.GetGenericArguments(), null);
            return Esc(mi.DeclaringType.FullName) + "::" + Esc(mi.Name);
        }
        catch (Exception e) { return "tok " + tok.ToString("x8") + " (" + e.GetType().Name + ")"; }
    }

    static string Sig(MethodBase mb)
    {
        try
        {
            ParameterInfo[] ps = mb.GetParameters();
            StringBuilder sb = new StringBuilder();
            MethodInfo mi = mb as MethodInfo;
            sb.Append(mi != null ? mi.ReturnType.Name : "void");
            sb.Append(" {" + mb.Attributes + "} ");
            sb.Append(mb.Name).Append("(");
            for (int i = 0; i < ps.Length; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.Append(Esc(ps[i].ParameterType.Name)).Append(" ").Append(Esc(ps[i].Name));
            }
            sb.Append(")");
            return sb.ToString();
        }
        catch { return "?"; }
    }
}
