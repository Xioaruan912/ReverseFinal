Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public const uint LDOWN=0x0002, LUP=0x0004, RDOWN=0x0008, RUP=0x0010;
  public static void LClick(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(150);
    mouse_event(LDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(LUP,0,0,0,IntPtr.Zero); }
  public static void RClick(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(150);
    mouse_event(RDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(RUP,0,0,0,IntPtr.Zero); }
  public static void Move(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(200); }
}
"@
$out = $args[0]
$mode = $args[1]
$x = [int]$args[2]
$y = [int]$args[3]
if ($mode -eq 'r') { [M]::RClick($x, $y) } else { [M]::LClick($x, $y) }
Start-Sleep -Seconds 3
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ('clicked ' + $mode + ' @' + $x + ',' + $y + ' -> ' + $out)
