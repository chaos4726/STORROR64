# proccap.ps1 -out file.wav -secs N [-proc name]: record ONLY that process's audio (Windows process loopback,
# AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK) to a 48 kHz 16-bit stereo WAV - nothing else the user hears is taken.
# (dev tool, 2026-10-18: telling STORROR's footstep surface sounds apart)
param([string]$out = "X:\mashup-work\devtmp\cap.wav", [double]$secs = 4, [string]$proc = "STORRORParkourPRO-Win64-Shipping")
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)] public struct WAVEFORMATEX { public ushort wFormatTag; public ushort nChannels; public uint nSamplesPerSec; public uint nAvgBytesPerSec; public ushort nBlockAlign; public ushort wBitsPerSample; public ushort cbSize; }
[StructLayout(LayoutKind.Sequential)] public struct ACT_PARAMS { public int ActivationType; public uint TargetProcessId; public int ProcessLoopbackMode; }
[StructLayout(LayoutKind.Sequential)] public struct BLOB { public int cbSize; public IntPtr pBlobData; }
[StructLayout(LayoutKind.Explicit)] public struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public BLOB blob; }

[ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioClient {
  [PreserveSig] int Initialize(int shareMode, uint streamFlags, long bufferDuration, long periodicity, ref WAVEFORMATEX format, IntPtr sessionGuid);
  [PreserveSig] int GetBufferSize(out uint n);
  [PreserveSig] int GetStreamLatency(out long l);
  [PreserveSig] int GetCurrentPadding(out uint p);
  [PreserveSig] int IsFormatSupported(int s, IntPtr f, IntPtr c);
  [PreserveSig] int GetMixFormat(out IntPtr f);
  [PreserveSig] int GetDevicePeriod(out long a, out long b);
  [PreserveSig] int Start();
  [PreserveSig] int Stop();
  [PreserveSig] int Reset();
  [PreserveSig] int SetEventHandle(IntPtr h);
  [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
}
[ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioCaptureClient {
  [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong pos, out ulong qpc);
  [PreserveSig] int ReleaseBuffer(uint frames);
  [PreserveSig] int GetNextPacketSize(out uint frames);
}
[ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IActivateAudioInterfaceAsyncOperation { [PreserveSig] int GetActivateResult(out int hr, [MarshalAs(UnmanagedType.IUnknown)] out object iface); }
[ComImport, Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IActivateAudioInterfaceCompletionHandler { void ActivateCompleted(IActivateAudioInterfaceAsyncOperation op); }

[ComVisible(true), ClassInterface(ClassInterfaceType.None)]
public class Done : IActivateAudioInterfaceCompletionHandler, IAgileObject {
  public ManualResetEvent ev = new ManualResetEvent(false);
  public object result; public int hr;
  public void ActivateCompleted(IActivateAudioInterfaceAsyncOperation op) { object o; int h; op.GetActivateResult(out h, out o); hr = h; result = o; ev.Set(); }
}
[ComImport, Guid("94ea2b94-e9cc-49e0-c0ff-ee64ca8f5b90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAgileObject { }

public static class Cap {
  [DllImport("Mmdevapi.dll", ExactSpelling = true, PreserveSig = true)]
  static extern int ActivateAudioInterfaceAsync([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid iid, ref PROPVARIANT p, IActivateAudioInterfaceCompletionHandler h, out IActivateAudioInterfaceAsyncOperation op);

  public static string Run(uint pid, string outPath, double secs) {
    var ap = new ACT_PARAMS { ActivationType = 1, TargetProcessId = pid, ProcessLoopbackMode = 0 };
    IntPtr apPtr = Marshal.AllocHGlobal(Marshal.SizeOf(ap)); Marshal.StructureToPtr(ap, apPtr, false);
    var pv = new PROPVARIANT { vt = 65 /* VT_BLOB */ }; pv.blob.cbSize = Marshal.SizeOf(ap); pv.blob.pBlobData = apPtr;
    Guid iid = typeof(IAudioClient).GUID;
    var done = new Done(); IActivateAudioInterfaceAsyncOperation op;
    int hr = ActivateAudioInterfaceAsync("VAD\\Process_Loopback", ref iid, ref pv, done, out op);
    if (hr != 0) return "activate failed " + hr.ToString("X");
    done.ev.WaitOne(5000);
    if (done.hr != 0 || done.result == null) return "activate result " + done.hr.ToString("X");
    var ac = (IAudioClient)done.result;
    var wf = new WAVEFORMATEX { wFormatTag = 1, nChannels = 2, nSamplesPerSec = 48000, wBitsPerSample = 16, nBlockAlign = 4, nAvgBytesPerSec = 192000, cbSize = 0 };
    // AUDCLNT_STREAMFLAGS_LOOPBACK | AUTOCONVERTPCM | SRC_DEFAULT_QUALITY
    hr = ac.Initialize(0, 0x00020000 | 0x80000000 | 0x08000000, 2000000, 0, ref wf, IntPtr.Zero);
    if (hr != 0) return "init failed " + hr.ToString("X");
    Guid cid = typeof(IAudioCaptureClient).GUID; object co; ac.GetService(ref cid, out co);
    var cc = (IAudioCaptureClient)co;
    var ms = new MemoryStream();
    ac.Start();
    var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.Elapsed.TotalSeconds < secs) {
      Thread.Sleep(10);
      uint n; cc.GetNextPacketSize(out n);
      while (n > 0) {
        IntPtr d; uint frames, flags; ulong p, q;
        cc.GetBuffer(out d, out frames, out flags, out p, out q);
        var buf = new byte[frames * 4];
        if ((flags & 2) == 0) Marshal.Copy(d, buf, 0, buf.Length);
        ms.Write(buf, 0, buf.Length);
        cc.ReleaseBuffer(frames);
        cc.GetNextPacketSize(out n);
      }
    }
    ac.Stop();
    var data = ms.ToArray();
    using (var f = new BinaryWriter(File.Create(outPath))) {
      f.Write(new char[] { 'R', 'I', 'F', 'F' }); f.Write(36 + data.Length); f.Write(new char[] { 'W', 'A', 'V', 'E' });
      f.Write(new char[] { 'f', 'm', 't', ' ' }); f.Write(16); f.Write((short)1); f.Write((short)2); f.Write(48000); f.Write(192000); f.Write((short)4); f.Write((short)16);
      f.Write(new char[] { 'd', 'a', 't', 'a' }); f.Write(data.Length); f.Write(data);
    }
    return "ok " + data.Length + " bytes";
  }
}
"@
$p = Get-Process -Name $proc -ErrorAction Stop | Select-Object -First 1
[Cap]::Run([uint32]$p.Id, $out, $secs)
