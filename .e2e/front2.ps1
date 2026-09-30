Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class WV {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static List<IntPtr> Visible(uint want){
    var res = new List<IntPtr>();
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p);
      if(p==want && IsWindowVisible(h)){ RECT r; GetWindowRect(h,out r);
        if((r.R-r.L) > 120 && (r.B-r.T) > 120) res.Add(h); }
      return true; }, IntPtr.Zero);
    return res; }
  public static string Title(IntPtr h){ var t=new StringBuilder(512); GetWindowTextW(h,t,512); return t.ToString(); }
  public static string Rect(IntPtr h){ RECT r; GetWindowRect(h,out r); return r.L+","+r.T+" "+ (r.R-r.L) +"x"+ (r.B-r.T); }
}
"@

$out = $args[0]
$pid_ = [uint32](Get-Process Quicker | Select-Object -First 1).Id
Write-Host ('Quicker pid=' + $pid_)
$wins = [WV]::Visible($pid_)
Write-Host ('visible big windows: ' + $wins.Count)
foreach ($h in $wins) { Write-Host ('   h=' + $h + '  rect=' + [WV]::Rect($h) + '  title=' + [WV]::Title($h)) }
if ($wins.Count -eq 0) { Write-Host 'no visible window'; exit 3 }

$h = $wins[0]
[WV]::ShowWindow($h, 9) | Out-Null
for ($i=0; $i -lt 3; $i++) { [WV]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 600 }
Start-Sleep -Seconds 1
Write-Host ('brought to front: h=' + $h + ' rect=' + [WV]::Rect($h))

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)

$r = New-Object WV+RECT
[void][WV]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $ht = $r.B - $r.T
$crop = New-Object System.Drawing.Bitmap $w, $ht
$g2 = [System.Drawing.Graphics]::FromImage($crop)
$g2.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0,0,$w,$ht), (New-Object System.Drawing.Rectangle $r.L,$r.T,$w,$ht), [System.Drawing.GraphicsUnit]::Pixel)
$crop.Save(($out -replace '\.png$', '_crop.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ('saved ' + $out)
