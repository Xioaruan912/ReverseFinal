Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class WW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k,byte s,uint f,IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static IntPtr Find(uint want, string titlePart){
    IntPtr found = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p);
      if(p==want && IsWindowVisible(h)){ var t=new StringBuilder(256); GetWindowTextW(h,t,256);
        if(t.ToString().Contains(titlePart)){ found=h; return false; } }
      return true; }, IntPtr.Zero);
    return found; }
  public static void Esc(){ keybd_event(0x1B,0,0,IntPtr.Zero); keybd_event(0x1B,0,2,IntPtr.Zero); }
}
"@

$out = $args[0]
$pid_ = [uint32](Get-Process Quicker | Select-Object -First 1).Id
$h = [WW]::Find($pid_, 'Quicker')
if ($h -eq [IntPtr]::Zero) { Write-Host 'login window not found'; exit 3 }
[WW]::ShowWindow($h, 9) | Out-Null      # SW_RESTORE
[WW]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Seconds 1
[WW]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Seconds 1
$r = New-Object WW+RECT
[void][WW]::GetWindowRect($h, [ref]$r)
Write-Host ('window handle=' + $h + '  rect=' + $r.L + ',' + $r.T + ' - ' + $r.R + ',' + $r.B + '  (' + ($r.R-$r.L) + 'x' + ($r.B-$r.T) + ')')

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)

# also crop the window area for a close look
$w = $r.R - $r.L; $ht = $r.B - $r.T
if ($w -gt 0 -and $ht -gt 0) {
  $crop = New-Object System.Drawing.Bitmap $w, $ht
  $g2 = [System.Drawing.Graphics]::FromImage($crop)
  $g2.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0,0,$w,$ht), (New-Object System.Drawing.Rectangle $r.L,$r.T,$w,$ht), [System.Drawing.GraphicsUnit]::Pixel)
  $crop.Save(($out -replace '\.png$', '_crop.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
Write-Host ('saved ' + $out)
