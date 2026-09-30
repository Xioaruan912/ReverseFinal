Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class QS {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static List<string> List(uint want){
    var res=new List<string>();
    EnumWindows((h,l)=>{ if(!IsWindowVisible(h)) return true;
      uint pid; GetWindowThreadProcessId(h,out pid); if(pid!=want) return true;
      RECT r; GetWindowRect(h,out r);
      if(r.R-r.L<60 || r.B-r.T<60) return true;
      var c=new StringBuilder(256); GetClassNameW(h,c,256);
      var t=new StringBuilder(256); GetWindowTextW(h,t,256);
      res.Add(h+"|"+t.ToString()+"|"+r.L+","+r.T+" "+ (r.R-r.L) +"x"+ (r.B-r.T));
      return true; }, IntPtr.Zero);
    return res; }
  public static bool Grab(long hv, string path){
    IntPtr h=new IntPtr(hv); RECT r; if(!GetWindowRect(h,out r)) return false;
    int w=r.R-r.L, ht=r.B-r.T; if(w<=0||ht<=0) return false;
    var bmp=new System.Drawing.Bitmap(w,ht);
    using(var g=System.Drawing.Graphics.FromImage(bmp)){ IntPtr dc=g.GetHdc(); bool ok=PrintWindow(h,dc,2); g.ReleaseHdc(dc); if(!ok) return false; }
    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png); return true; }
}
"@
[void][QS]::SetProcessDPIAware()
$prefix = $args[0]
$pid_ = [uint32](Get-Process Quicker | Select-Object -First 1).Id
$i = 0
foreach ($s in [QS]::List($pid_)) {
  $p = $s.Split('|')
  $f = ($prefix + "_$i.png")
  $ok = [QS]::Grab([int64]$p[0], $f)
  Write-Host ('{0}  h={1}  title={2}  rect={3}  grab={4}' -f $i, $p[0], $p[1], $p[2], $ok)
  $i++
}
if ($i -eq 0) { Write-Host 'no visible Quicker windows' }
