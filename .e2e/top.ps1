Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class TP {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x,int y,int cx,int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static readonly IntPtr TOPMOST = new IntPtr(-1);
  public static readonly IntPtr NOTOPMOST = new IntPtr(-2);
  public const uint SWP_NOMOVE=0x0002, SWP_NOSIZE=0x0001, SWP_SHOWWINDOW=0x0040;
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
  public static void Raise(IntPtr h){
    ShowWindow(h, 9);
    SetWindowPos(h, TOPMOST, 0,0,0,0, SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
    SetWindowPos(h, NOTOPMOST, 0,0,0,0, SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
  }
}
"@

$out = $args[0]
$pid_ = [uint32](Get-Process Quicker | Select-Object -First 1).Id
$h = [TP]::Pick($pid_)
if ($h -eq [IntPtr]::Zero) { Write-Host 'no window'; exit 3 }
Write-Host ('window h=' + $h + ' title=' + [TP]::Title($h) + ' rect=' + [TP]::Rect($h))
[TP]::Raise($h)
Start-Sleep -Seconds 2
$r = New-Object TP+RECT
[void][TP]::GetWindowRect($h, [ref]$r)
Write-Host ('after raise rect=' + [TP]::Rect($h))

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)

$w = $r.R-$r.L; $ht = $r.B-$r.T
if ($w -gt 0 -and $ht -gt 0) {
  $crop = New-Object System.Drawing.Bitmap $w, $ht
  $g2 = [System.Drawing.Graphics]::FromImage($crop)
  $g2.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0,0,$w,$ht), (New-Object System.Drawing.Rectangle $r.L,$r.T,$w,$ht), [System.Drawing.GraphicsUnit]::Pixel)
  $crop.Save(($out -replace '\.png$','_crop.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
Write-Host ('saved ' + $out)
