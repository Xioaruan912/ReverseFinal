Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class SP {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static readonly uint MDOWN=0x0020, MUP=0x0040, LDOWN=0x0002, LUP=0x0004;
  public static void Mid(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(250);
    mouse_event(MDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(MUP,0,0,0,IntPtr.Zero); }
  public static void Lft(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(250);
    mouse_event(LDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(LUP,0,0,0,IntPtr.Zero); }
  public static List<string> List(uint want){
    var res=new List<string>();
    EnumWindows((h,l)=>{ if(!IsWindowVisible(h)) return true;
      uint pid; GetWindowThreadProcessId(h,out pid); if(pid!=want) return true;
      RECT r; GetWindowRect(h,out r);
      if(r.R-r.L<60 || r.B-r.T<60) return true;
      var t=new StringBuilder(256); GetWindowTextW(h,t,256);
      res.Add(h+"|"+t.ToString()+"|"+r.L+"|"+r.T+"|"+(r.R-r.L)+"|"+(r.B-r.T));
      return true; }, IntPtr.Zero);
    return res; }
  public static bool Grab(long hv, string path){
    IntPtr h=new IntPtr(hv); RECT r; GetWindowRect(h,out r);
    int w=r.R-r.L, ht=r.B-r.T; if(w<=0||ht<=0) return false;
    var bmp=new System.Drawing.Bitmap(w,ht);
    using(var g=System.Drawing.Graphics.FromImage(bmp)){ IntPtr dc=g.GetHdc(); bool ok=PrintWindow(h,dc,2); g.ReleaseHdc(dc); if(!ok) return false; }
    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png); return true; }
}
"@
[void][SP]::SetProcessDPIAware()
$prefix = $args[0]
$pid_ = [uint32](Get-Process Quicker | Select-Object -First 1).Id

# 1) open the panel
[SP]::Mid(1280, 700)
Start-Sleep -Seconds 3
$panel = $null
foreach ($s in [SP]::List($pid_)) {
  Write-Host ('  win: ' + $s)
  $p = $s.Split('|')
  if ($p[1] -match '面板' -and [int]$p[4] -gt 500) { $panel = $p }
}
if (-not $panel) { Write-Host 'panel not found'; exit 3 }
$L = [int]$panel[2]; $T = [int]$panel[3]; $W = [int]$panel[4]; $H = [int]$panel[5]
Write-Host ("panel rect = $L,$T ${W}x${H}")
# header icons scale with the panel: gear ~ (136/543, 28/1090) of the panel
$gx = [int]($L + $W * 0.250)
$gy = [int]($T + $H * 0.026)
Write-Host ("clicking gear at $gx,$gy")
[SP]::Lft($gx, $gy)
Start-Sleep -Seconds 4
$i = 0
foreach ($s in [SP]::List($pid_)) {
  Write-Host ('  after: ' + $s)
  $p = $s.Split('|')
  if ([int]$p[4] -gt 900) {
    $f = ($prefix + "_$i.png")
    if ([SP]::Grab([int64]$p[0], $f)) { Write-Host ('      -> ' + $f) }
  }
  $i++
}
