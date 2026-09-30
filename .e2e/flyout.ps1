Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class FL {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static readonly uint LDOWN=0x0002, LUP=0x0004;
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(200);
    mouse_event(LDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(LUP,0,0,0,IntPtr.Zero); }
  public static List<string> List(){
    var res=new List<string>();
    EnumWindows((h,l)=>{ if(!IsWindowVisible(h)) return true;
      var c=new StringBuilder(256); GetClassNameW(h,c,256);
      var t=new StringBuilder(256); GetWindowTextW(h,t,256);
      RECT r; GetWindowRect(h,out r);
      int w=r.R-r.L, ht=r.B-r.T;
      if(w>50 && ht>50) res.Add(h+"|"+c.ToString()+"|"+t.ToString()+"|"+r.L+","+r.T+" "+w+"x"+ht);
      return true; }, IntPtr.Zero);
    return res; }
  public static bool Grab(IntPtr h, string path){
    RECT r; GetWindowRect(h,out r); int w=r.R-r.L, ht=r.B-r.T;
    if(w<=0||ht<=0) return false;
    var bmp=new System.Drawing.Bitmap(w,ht);
    using(var g=System.Drawing.Graphics.FromImage(bmp)){ IntPtr dc=g.GetHdc(); bool ok=PrintWindow(h,dc,2); g.ReleaseHdc(dc); if(!ok) return false; }
    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png); return true; }
  public static IntPtr ByHandle(long h){ return new IntPtr(h); }
}
"@
[void][FL]::SetProcessDPIAware()
$chevX = [int]$args[0]; $chevY = [int]$args[1]; $out = $args[2]
$before = [FL]::List()
Write-Host ('windows before: ' + $before.Count)
[FL]::Click($chevX, $chevY)
Start-Sleep -Milliseconds 900
$after = [FL]::List()
Write-Host '--- windows after click ---'
foreach ($s in $after) { Write-Host ('   ' + $s) }
$new = $after | Where-Object { $before -notcontains $_ }
Write-Host ('NEW: ' + ($new -join ' ;; '))
$i = 0
foreach ($s in $new) {
  $p = $s.Split('|'); $h = [FL]::ByHandle([int64]$p[0])
  $f = ($out -replace '\.png$', ("_$i.png"))
  if ([FL]::Grab($h, $f)) { Write-Host ('   grabbed -> ' + $f) }
  $i++
}
