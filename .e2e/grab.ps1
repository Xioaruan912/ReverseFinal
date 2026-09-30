Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class PW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static IntPtr Pick(uint want){
    IntPtr best=IntPtr.Zero; long area=0;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p);
      if(p==want && IsWindowVisible(h)){ RECT r; GetWindowRect(h,out r);
        long a=(long)(r.R-r.L)*(r.B-r.T);
        if(a>area && (r.R-r.L)>120){ area=a; best=h; } }
      return true; }, IntPtr.Zero);
    return best; }
  public static string Title(IntPtr h){ var t=new StringBuilder(512); GetWindowTextW(h,t,512); return t.ToString(); }
  public static string Rect(IntPtr h){ RECT r; GetWindowRect(h,out r); return r.L+","+r.T+" "+ (r.R-r.L) +"x"+ (r.B-r.T); }
  public static bool Grab(IntPtr h, string path){
    RECT r; if(!GetWindowRect(h,out r)) return false;
    int w=r.R-r.L, ht=r.B-r.T; if(w<=0||ht<=0) return false;
    var bmp=new System.Drawing.Bitmap(w,ht);
    using(var g=System.Drawing.Graphics.FromImage(bmp)){
      IntPtr dc=g.GetHdc();
      bool ok=PrintWindow(h,dc,2);
      g.ReleaseHdc(dc);
      if(!ok) return false;
    }
    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    return true; }
}
"@

[void][PW]::SetProcessDPIAware()
$out = $args[0]
$pid_ = [uint32](Get-Process Quicker | Select-Object -First 1).Id
$h = [PW]::Pick($pid_)
if ($h -eq [IntPtr]::Zero) { Write-Host 'no window'; exit 3 }
Write-Host ('h=' + $h + ' title=' + [PW]::Title($h) + ' rect=' + [PW]::Rect($h))
if ([PW]::Grab($h, $out)) { Write-Host ('saved ' + $out) } else { Write-Host 'PrintWindow failed'; exit 4 }
