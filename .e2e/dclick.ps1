Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;using System.Runtime.InteropServices;
public class CU {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public const uint LDOWN=0x0002, LUP=0x0004;
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(250);
    mouse_event(LDOWN,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(80); mouse_event(LUP,0,0,0,IntPtr.Zero); }
}
"@
[void][CU]::SetProcessDPIAware()
$x = [int]$args[0]; $y = [int]$args[1]
Write-Host ("clicking physical $x,$y")
[CU]::Click($x, $y)
