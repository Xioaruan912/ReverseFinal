Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MM {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  public const uint LDOWN=0x0002, LUP=0x0004, RDOWN=0x0008, RUP=0x0010;
  public static void L(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(200);
    mouse_event(LDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(LUP,0,0,0,IntPtr.Zero); }
  public static void R(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(200);
    mouse_event(RDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(RUP,0,0,0,IntPtr.Zero); }
}
"@

$mode = $args[0]     # 'l' or 'r'
$out  = $args[1]

$root = [System.Windows.Automation.AutomationElement]::RootElement
$all  = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
Write-Host ('descendants scanned: ' + $all.Count)
$target = $null
foreach ($e in $all) {
  $n = $e.Current.Name
  if ($n -and $n -match 'Quicker' -and $e.Current.ControlType.ProgrammaticName -match 'Button') {
    $r = $e.Current.BoundingRectangle
    Write-Host ('  tray candidate: name=' + $n + ' class=' + $e.Current.ClassName + ' rect=' + [int]$r.X + ',' + [int]$r.Y + ' ' + [int]$r.Width + 'x' + [int]$r.Height)
    if ($r.Width -gt 0 -and -not $target) { $target = $r }
  }
}
if (-not $target) {
  Write-Host '  no tray button named Quicker found; dumping taskbar buttons'
  foreach ($e in $all) {
    $r = $e.Current.BoundingRectangle
    if ($e.Current.ControlType.ProgrammaticName -match 'Button' -and $r.Y -gt 1300 -and $r.Width -gt 0) {
      Write-Host ('    btn name=[' + $e.Current.Name + '] class=' + $e.Current.ClassName + ' @' + [int]$r.X + ',' + [int]$r.Y)
    }
  }
  exit 3
}
$cx = [int]($target.X + $target.Width / 2)
$cy = [int]($target.Y + $target.Height / 2)
Write-Host ('clicking ' + $mode + ' at ' + $cx + ',' + $cy)
if ($mode -eq 'r') { [MM]::R($cx, $cy) } else { [MM]::L($cx, $cy) }
Start-Sleep -Seconds 3
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ('saved ' + $out)
