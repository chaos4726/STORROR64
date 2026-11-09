# peak.ps1 <process name> <seconds> <interval ms>: the audio peak level (0..1) of that process's audio sessions, sampled,
# printed as "t:peak" lines - to tell whether a sound is actually heard (dev tool, 2026-10-18)
param([string]$proc = "STORRORParkourPRO-Win64-Shipping", [double]$secs = 5, [int]$ms = 20)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int NotImpl1(); [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface); }
[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionManager2 { int NotImpl1(); int NotImpl2(); [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator SessionEnum); }
[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionEnumerator { [PreserveSig] int GetCount(out int SessionCount); [PreserveSig] int GetSession(int SessionCount, out IAudioSessionControl Session); }
[Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl { }
[Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl2 { int n1(); int n2(); int n3(); int n4(); int n5(); int n6(); int n7(); int n8(); int n9();
  [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
  [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
  [PreserveSig] int GetProcessId(out uint pid); }
[Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float pfPeak); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom { }
public static class Peak {
  static List<IAudioMeterInformation> meters = new List<IAudioMeterInformation>();
  public static int Init(uint pid) {
    var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCom());
    IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
    Guid g = typeof(IAudioSessionManager2).GUID; object o; dev.Activate(ref g, 23, IntPtr.Zero, out o);
    var mgr = (IAudioSessionManager2)o; IAudioSessionEnumerator se; mgr.GetSessionEnumerator(out se);
    int n; se.GetCount(out n);
    for (int i = 0; i < n; i++) { IAudioSessionControl c; se.GetSession(i, out c); var c2 = (IAudioSessionControl2)c; uint p; c2.GetProcessId(out p);
      Console.WriteLine("session pid " + p);
      if (p == pid || pid == 0) meters.Add((IAudioMeterInformation)c); }
    return meters.Count;
  }
  public static float Get() { float m = 0; foreach (var x in meters) { float v; x.GetPeakValue(out v); if (v > m) m = v; } return m; }
}
"@
$p = Get-Process -Name $proc -ErrorAction Stop | Select-Object -First 1
$n = [Peak]::Init([uint32]$p.Id)
Write-Output "sessions $n"
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $secs) {
  Write-Output ("{0:F2}:{1:F4}" -f $sw.Elapsed.TotalSeconds, [Peak]::Get())
  Start-Sleep -Milliseconds $ms
}
