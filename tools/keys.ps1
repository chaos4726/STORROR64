# keys.ps1 "down:W wait:450 down:SPACE wait:150 up:SPACE wait:1500 up:W mx:400" - scancode key presses (and mx:N relative
# mouse moves, turning the camera) into the focused window
param([string]$seq)
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K {
  [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort vk; public ushort scan; public uint flags; public uint time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, IN[] a, int size);
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct MIN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public int dx; [FieldOffset(12)] public int dy; [FieldOffset(16)] public uint data; [FieldOffset(20)] public uint flags; [FieldOffset(24)] public uint time; [FieldOffset(32)] public IntPtr extra; }
  [DllImport("user32.dll", EntryPoint="SendInput")] public static extern uint SendMouse(uint n, MIN[] a, int size);
  public static void Move(int dx, int dy) { var m = new MIN(); m.type = 0; m.dx = dx; m.dy = dy; m.flags = 0x0001; SendMouse(1, new MIN[] { m }, Marshal.SizeOf(typeof(MIN))); }
  public static void Key(ushort scan, bool up, bool ext) {
    var i = new IN(); i.type = 1; i.ki.scan = scan; i.ki.flags = 0x0008u | (up ? 0x0002u : 0u) | (ext ? 0x0001u : 0u);
    SendInput(1, new IN[] { i }, Marshal.SizeOf(typeof(IN)));
  }
}
"@
$codes = @{ ESC=0x01; ENTER=0x1C; BACK=0x0E; W=0x11; A=0x1E; S=0x1F; D=0x20; SPACE=0x39; SHIFT=0x2A; CTRL=0x1D; E=0x12; Q=0x10; C=0x2E; F=0x21; R=0x13 }
foreach ($step in $seq.Split(' ')) {
  $p = $step.Split(':')
  switch ($p[0]) {
    'down' { [K]::Key([uint16]$codes[$p[1]], $false, $false) }
    'up'   { [K]::Key([uint16]$codes[$p[1]], $true, $false) }
    'wait' { Start-Sleep -Milliseconds ([int]$p[1]) }
    'mx'   { $n = [int]$p[1]; $st = [Math]::Sign($n) * 20; for ($i = 0; $i -lt [Math]::Abs($n) / 20; $i++) { [K]::Move($st, 0); Start-Sleep -Milliseconds 8 } }
  }
}
