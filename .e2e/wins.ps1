Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class WD {
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
  public static List<string> List(){
    var res=new List<string>();
    EnumWindows((h,l)=>{ if(!IsWindowVisible(h)) return true;
      var c=new StringBuilder(256); GetClassNameW(h,c,256);
      var t=new StringBuilder(256); GetWindowTextW(h,t,256);
      RECT r; GetWindowRect(h,out r);
      int w=r.R-r.L, ht=r.B-r.T;
      if(w>30 && ht>30){ uint pid; GetWindowThreadProcessId(h,out pid);
        res.Add(h+"|"+pid+"|"+c.ToString()+"|"+t.ToString()+"|"+r.L+","+r.T+" "+w+"x"+ht); }
      return true; }, IntPtr.Zero);
    return res; }
  public static bool Grab(IntPtr h, string path){
    RECT r; GetWindowRect(h,out r); int w=r.R-r.L, ht=r.B-r.T;
    if(w<=0||ht<=0) return false;
    var bmp=new System.Drawing.Bitmap(w,ht);
    using(var g=System.Drawing.Graphics.FromImage(bmp)){ IntPtr dc=g.GetHdc(); bool ok=PrintWindow(h,dc,2); g.ReleaseHdc(dc); if(!ok) return false; }
    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png); return true; }
  public static IntPtr H(long v){ return new IntPtr(v); }
}
"@
[void][WD]::SetProcessDPIAware()
$out = $args[0]
foreach ($s in [WD]::List()) { Write-Host $s }
if ($out) {
  $i=0
  foreach ($s in [WD]::List()) {
    $p = $s.Split('|')
    if ($p[2] -notmatch 'ApplicationFrameWindow|Chrome_WidgetWin|MozillaWindowClass|CASCADIA|Progman|WorkerW|Shell_TrayWnd') {
      $f = ($out -replace '\.png$', ("_w$i.png"))
      if ([WD]::Grab([WD]::H([int64]$p[0]), $f)) { Write-Host ('   grabbed ' + $p[2] + ' -> ' + $f) }
      $i++
    }
  }
}
