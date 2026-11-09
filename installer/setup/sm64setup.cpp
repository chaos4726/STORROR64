// SM64Setup.exe: the STORROR x Super Mario 64 mod's installer.
//
// The mod's Super Mario 64 files (levels, textures, sounds, music) ship locked in sm64_assets.pak: each encrypted with
// ChaCha20 under a key made from the player's own Super Mario 64 (USA) ROM. The player drags their ROM onto this window
// (or picks it with Browse); it is checked against the official dump's SHA-1, and with it the files are unlocked into
// the mod folder beside this program. Without the ROM the pack is noise.
//
//   SM64Setup.exe                                   the window
//   SM64Setup.exe --pack <rom> <list.txt> <root> <out.pak>   (making a release: the files listed, from root, locked)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "comdlg32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

namespace {

const char* kSha1 = "9bef1128717f958171a4afac3ed78ee2bb4e86ce";   // Super Mario 64 (USA), big-endian .z64
const char kMagic[8] = {'S', 'M', '6', '4', 'P', 'A', 'K', '1'};
const char kCheck[16] = {'S', 'M', '6', '4', 'M', 'A', 'P', '-', 'U', 'N', 'L', 'O', 'C', 'K', 'E', 'D'};

// ------------------------------------------------------------------------------------------- hashing

bool Hash(LPCWSTR alg, const void* data, size_t n, std::vector<uint8_t>& out) {
  BCRYPT_ALG_HANDLE a = nullptr;
  BCRYPT_HASH_HANDLE h = nullptr;
  if (BCryptOpenAlgorithmProvider(&a, alg, nullptr, 0) != 0) return false;
  DWORD len = 0, got = 0;
  BCryptGetProperty(a, BCRYPT_HASH_LENGTH, (PUCHAR)&len, sizeof len, &got, 0);
  out.assign(len, 0);
  bool ok = BCryptCreateHash(a, &h, nullptr, 0, nullptr, 0, 0) == 0 &&
            BCryptHashData(h, (PUCHAR)data, (ULONG)n, 0) == 0 && BCryptFinishHash(h, out.data(), len, 0) == 0;
  if (h) BCryptDestroyHash(h);
  BCryptCloseAlgorithmProvider(a, 0);
  return ok;
}

std::string Hex(const std::vector<uint8_t>& v) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (uint8_t b : v) { s += d[b >> 4]; s += d[b & 15]; }
  return s;
}

// --------------------------------------------------------------------------------------------- ChaCha20

inline uint32_t Rotl(uint32_t v, int c) { return (v << c) | (v >> (32 - c)); }
#define QR(a, b, c, d) a += b; d ^= a; d = Rotl(d, 16); c += d; b ^= c; b = Rotl(b, 12); a += b; d ^= a; d = Rotl(d, 8); c += d; b ^= c; b = Rotl(b, 7);

struct ChaCha {
  uint32_t s[16];
  ChaCha(const uint8_t key[32], uint32_t nonce0) {
    s[0] = 0x61707865; s[1] = 0x3320646e; s[2] = 0x79622d32; s[3] = 0x6b206574;
    for (int i = 0; i < 8; i++) std::memcpy(&s[4 + i], key + 4 * i, 4);
    s[12] = 0; s[13] = nonce0; s[14] = 0x53363452; s[15] = 0x4d415031;   // ("R46S" "1PAM": the mod's own nonce words)
  }
  void Xor(uint8_t* p, size_t n) {
    uint8_t block[64];
    size_t i = 0;
    while (i < n) {
      uint32_t x[16];
      std::memcpy(x, s, sizeof x);
      for (int r = 0; r < 10; r++) {
        QR(x[0], x[4], x[8], x[12]) QR(x[1], x[5], x[9], x[13]) QR(x[2], x[6], x[10], x[14]) QR(x[3], x[7], x[11], x[15])
        QR(x[0], x[5], x[10], x[15]) QR(x[1], x[6], x[11], x[12]) QR(x[2], x[7], x[8], x[13]) QR(x[3], x[4], x[9], x[14])
      }
      for (int k = 0; k < 16; k++) { uint32_t v = x[k] + s[k]; std::memcpy(block + 4 * k, &v, 4); }
      s[12]++;
      size_t m = n - i < 64 ? n - i : 64;
      for (size_t k = 0; k < m; k++) p[i + k] ^= block[k];
      i += m;
    }
  }
};

// ------------------------------------------------------------------------------------------- the ROM

bool ReadFileAll(const std::wstring& path, std::vector<uint8_t>& out) {
  HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER sz;
  GetFileSizeEx(h, &sz);
  if (sz.QuadPart > (1ll << 31)) { CloseHandle(h); return false; }
  out.resize((size_t)sz.QuadPart);
  DWORD got = 0;
  size_t at = 0;
  while (at < out.size() && ReadFile(h, out.data() + at, (DWORD)std::min<size_t>(out.size() - at, 1 << 24), &got, nullptr) && got) at += got;
  CloseHandle(h);
  return at == out.size();
}

// The ROM as the official big-endian .z64 (a .v64's bytes swapped in pairs, a .n64's in fours), checked; its key.
std::string RomKey(const std::wstring& path, uint8_t key[32]) {
  std::vector<uint8_t> r;
  if (!ReadFileAll(path, r)) return "Couldn't read that file.";
  if (r.size() != 8 * 1024 * 1024) return "That isn't a Super Mario 64 ROM (wrong size).";
  if (r[0] == 0x37 && r[1] == 0x80) {
    for (size_t i = 0; i + 1 < r.size(); i += 2) std::swap(r[i], r[i + 1]);
  } else if (r[0] == 0x40 && r[1] == 0x12) {
    for (size_t i = 0; i + 3 < r.size(); i += 4) { std::swap(r[i], r[i + 3]); std::swap(r[i + 1], r[i + 2]); }
  }
  std::vector<uint8_t> h;
  if (!Hash(BCRYPT_SHA1_ALGORITHM, r.data(), r.size(), h)) return "Couldn't check the ROM.";
  if (Hex(h) != kSha1) return "That isn't the Super Mario 64 (USA) ROM. The mod needs the original US cartridge's dump.";
  std::string salted = "SM64Map pack key|";
  std::vector<uint8_t> buf(salted.begin(), salted.end());
  buf.insert(buf.end(), r.begin(), r.end());
  if (!Hash(BCRYPT_SHA256_ALGORITHM, buf.data(), buf.size(), h)) return "Couldn't make the key.";
  std::memcpy(key, h.data(), 32);
  return "";
}

std::wstring Wide(const std::string& s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &w[0], n);
  return w;
}

std::wstring Folder(const std::wstring& p) { return p.substr(0, p.find_last_of(L"\\/")); }

void MakeDirs(const std::wstring& dir) {
  std::wstring cur;
  for (size_t i = 0; i < dir.size(); i++) {
    cur += dir[i];
    if ((dir[i] == L'\\' || dir[i] == L'/') && cur.size() > 3) CreateDirectoryW(cur.c_str(), nullptr);
  }
  CreateDirectoryW(dir.c_str(), nullptr);
}

std::wstring ExeFolder() {
  wchar_t p[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, p, MAX_PATH);
  return Folder(std::wstring(p, n));
}

// ------------------------------------------------------------------------------------------- unlocking

HWND g_wnd = nullptr, g_status = nullptr, g_bar = nullptr, g_browse = nullptr;
volatile bool g_busy = false;
const UINT WM_STATUS = WM_APP + 1, WM_PROGRESS = WM_APP + 2, WM_DONE = WM_APP + 3;

void Say(const std::string& s) {
  std::wstring* w = new std::wstring(Wide(s));
  PostMessageW(g_wnd, WM_STATUS, 0, (LPARAM)w);
}

std::string Unlock(const std::wstring& rom) {
  uint8_t key[32];
  Say("Checking your ROM...");
  std::string err = RomKey(rom, key);
  if (!err.empty()) return err;
  const std::wstring dir = ExeFolder();
  HANDLE h = CreateFileW((dir + L"\\sm64_assets.pak").c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  if (h == INVALID_HANDLE_VALUE) return "sm64_assets.pak isn't beside SM64Setup.exe.";
  auto rd = [&](void* p, size_t n) { DWORD got = 0; return ReadFile(h, p, (DWORD)n, &got, nullptr) && got == n; };
  char magic[8];
  uint32_t count = 0;
  uint8_t check[16];
  if (!rd(magic, 8) || std::memcmp(magic, kMagic, 8) || !rd(&count, 4) || !rd(check, 16)) { CloseHandle(h); return "sm64_assets.pak is damaged."; }
  ChaCha(key, 0xFFFFFFFF).Xor(check, 16);
  if (std::memcmp(check, kCheck, 16)) { CloseHandle(h); return "This ROM doesn't open this pack."; }
  struct E { std::string path; uint64_t size, off; };
  std::vector<E> es(count);
  uint64_t total = 0;
  for (auto& e : es) {
    uint16_t n = 0;
    if (!rd(&n, 2)) { CloseHandle(h); return "sm64_assets.pak is damaged."; }
    e.path.resize(n);
    if (!rd(&e.path[0], n) || !rd(&e.size, 8) || !rd(&e.off, 8)) { CloseHandle(h); return "sm64_assets.pak is damaged."; }
    total += e.size;
  }
  uint64_t done = 0;
  std::vector<uint8_t> buf;
  for (uint32_t i = 0; i < count; i++) {
    const E& e = es[i];
    buf.resize((size_t)e.size);
    LARGE_INTEGER at;
    at.QuadPart = (LONGLONG)e.off;
    SetFilePointerEx(h, at, nullptr, FILE_BEGIN);
    if (e.size && !rd(buf.data(), (size_t)e.size)) { CloseHandle(h); return "sm64_assets.pak is damaged (" + e.path + ")."; }
    ChaCha(key, i).Xor(buf.data(), buf.size());
    std::wstring out = dir + L"\\" + Wide(e.path);
    for (auto& c : out) if (c == L'/') c = L'\\';
    MakeDirs(Folder(out));
    HANDLE o = CreateFileW(out.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (o == INVALID_HANDLE_VALUE) { CloseHandle(h); return "Couldn't write " + e.path + "."; }
    DWORD put = 0;
    if (e.size) WriteFile(o, buf.data(), (DWORD)buf.size(), &put, nullptr);
    CloseHandle(o);
    done += e.size;
    if (i % 16 == 0 || i + 1 == count) PostMessageW(g_wnd, WM_PROGRESS, (WPARAM)(total ? done * 1000 / total : 1000), 0);
  }
  CloseHandle(h);
  HANDLE m = CreateFileW((dir + L"\\installed.txt").c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
  if (m != INVALID_HANDLE_VALUE) { DWORD put; WriteFile(m, "installed\r\n", 11, &put, nullptr); CloseHandle(m); }
  return "";
}

DWORD WINAPI Worker(LPVOID p) {
  std::wstring* rom = (std::wstring*)p;
  std::string err = Unlock(*rom);
  delete rom;
  std::wstring* w = new std::wstring(Wide(err.empty() ? "Done! Super Mario 64 is installed. Start STORROR Parkour Pro to play." : err));
  PostMessageW(g_wnd, WM_DONE, err.empty() ? 1 : 0, (LPARAM)w);
  return 0;
}

void Start(const std::wstring& rom) {
  if (g_busy) return;
  g_busy = true;
  EnableWindow(g_browse, FALSE);
  SendMessageW(g_bar, PBM_SETPOS, 0, 0);
  CreateThread(nullptr, 0, Worker, new std::wstring(rom), 0, nullptr);
}

LRESULT CALLBACK Proc(HWND w, UINT m, WPARAM wp, LPARAM lp) {
  switch (m) {
    case WM_DROPFILES: {
      wchar_t p[MAX_PATH];
      if (DragQueryFileW((HDROP)wp, 0, p, MAX_PATH)) Start(p);
      DragFinish((HDROP)wp);
      return 0;
    }
    case WM_COMMAND:
      if (LOWORD(wp) == 1 && !g_busy) {
        wchar_t p[MAX_PATH] = L"";
        OPENFILENAMEW of = {};
        of.lStructSize = sizeof of;
        of.hwndOwner = w;
        of.lpstrFilter = L"Nintendo 64 ROM (*.z64; *.n64; *.v64)\0*.z64;*.n64;*.v64\0All files\0*.*\0";
        of.lpstrFile = p;
        of.nMaxFile = MAX_PATH;
        of.lpstrTitle = L"Your Super Mario 64 (USA) ROM";
        of.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
        if (GetOpenFileNameW(&of)) Start(p);
      }
      return 0;
    case WM_STATUS: {
      std::wstring* s = (std::wstring*)lp;
      SetWindowTextW(g_status, s->c_str());
      delete s;
      return 0;
    }
    case WM_PROGRESS:
      SendMessageW(g_bar, PBM_SETPOS, wp, 0);
      SetWindowTextW(g_status, L"Unlocking the Super Mario 64 files...");
      return 0;
    case WM_DONE: {
      std::wstring* s = (std::wstring*)lp;
      SetWindowTextW(g_status, s->c_str());
      if (wp) SendMessageW(g_bar, PBM_SETPOS, 1000, 0);
      delete s;
      g_busy = false;
      EnableWindow(g_browse, TRUE);
      return 0;
    }
    case WM_CTLCOLORSTATIC:
      SetBkMode((HDC)wp, TRANSPARENT);
      return (LRESULT)GetStockObject(WHITE_BRUSH);
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(w, m, wp, lp);
}

int Pack(int argc, wchar_t** argv) {
  // --pack <rom> <list.txt> <root> <out.pak>
  if (argc != 6) { std::fprintf(stderr, "--pack <rom> <list.txt> <root> <out.pak>\n"); return 2; }
  uint8_t key[32];
  std::string err = RomKey(argv[2], key);
  if (!err.empty()) { std::fprintf(stderr, "%s\n", err.c_str()); return 1; }
  std::vector<uint8_t> list;
  if (!ReadFileAll(argv[3], list)) { std::fprintf(stderr, "no list\n"); return 1; }
  std::vector<std::string> paths;
  std::string cur;
  for (uint8_t c : list) {
    if (c == '\n' || c == '\r') { if (!cur.empty()) paths.push_back(cur); cur.clear(); } else cur += (char)c;
  }
  if (!cur.empty()) paths.push_back(cur);
  const std::wstring root = argv[4];
  FILE* f = _wfopen(argv[5], L"wb");
  if (!f) { std::fprintf(stderr, "can't write the pack\n"); return 1; }
  uint32_t count = (uint32_t)paths.size();
  uint8_t check[16];
  std::memcpy(check, kCheck, 16);
  ChaCha(key, 0xFFFFFFFF).Xor(check, 16);
  std::fwrite(kMagic, 1, 8, f);
  std::fwrite(&count, 4, 1, f);
  std::fwrite(check, 1, 16, f);
  std::vector<uint64_t> sizes(count);
  uint64_t table = 8 + 4 + 16;
  for (uint32_t i = 0; i < count; i++) {
    std::wstring p = root + L"\\" + Wide(paths[i]);
    WIN32_FILE_ATTRIBUTE_DATA a;
    if (!GetFileAttributesExW(p.c_str(), GetFileExInfoStandard, &a)) { std::fprintf(stderr, "missing %s\n", paths[i].c_str()); return 1; }
    sizes[i] = ((uint64_t)a.nFileSizeHigh << 32) | a.nFileSizeLow;
    table += 2 + paths[i].size() + 16;
  }
  uint64_t off = table;
  for (uint32_t i = 0; i < count; i++) {
    uint16_t n = (uint16_t)paths[i].size();
    std::fwrite(&n, 2, 1, f);
    std::fwrite(paths[i].data(), 1, n, f);
    std::fwrite(&sizes[i], 8, 1, f);
    std::fwrite(&off, 8, 1, f);
    off += sizes[i];
  }
  std::vector<uint8_t> buf;
  for (uint32_t i = 0; i < count; i++) {
    if (!ReadFileAll(root + L"\\" + Wide(paths[i]), buf)) { std::fprintf(stderr, "can't read %s\n", paths[i].c_str()); return 1; }
    ChaCha(key, i).Xor(buf.data(), buf.size());
    std::fwrite(buf.data(), 1, buf.size(), f);
  }
  std::fclose(f);
  std::printf("packed %u files, %.1f MB\n", count, (double)off / 1048576.0);
  return 0;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, LPWSTR, int show) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argc >= 2 && std::wstring(argv[1]) == L"--pack") {
    AttachConsole(ATTACH_PARENT_PROCESS);
    std::freopen("CONOUT$", "w", stdout);
    std::freopen("CONOUT$", "w", stderr);
    return Pack(argc, argv);
  }
  if (argc >= 2 && std::wstring(argv[1]) == L"--unlock") {   // (a test: the ROM given, no window)
    AttachConsole(ATTACH_PARENT_PROCESS);
    std::freopen("CONOUT$", "w", stdout);
    g_wnd = nullptr;
    std::string err = Unlock(argv[2]);
    std::printf("%s\n", err.empty() ? "unlocked" : err.c_str());
    return err.empty() ? 0 : 1;
  }
  INITCOMMONCONTROLSEX ic = {sizeof ic, ICC_PROGRESS_CLASS};
  InitCommonControlsEx(&ic);
  WNDCLASSW wc = {};
  wc.lpfnWndProc = Proc;
  wc.hInstance = inst;
  wc.lpszClassName = L"SM64Setup";
  wc.hbrBackground = (HBRUSH)GetStockObject(WHITE_BRUSH);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  g_wnd = CreateWindowExW(WS_EX_ACCEPTFILES, L"SM64Setup", L"Super Mario 64 for STORROR - Setup",
                          WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, 560, 300,
                          nullptr, nullptr, inst, nullptr);
  HFONT big = CreateFontW(26, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
  HFONT norm = CreateFontW(17, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
  HWND t = CreateWindowW(L"STATIC", L"Drag your Super Mario 64 ROM here", WS_CHILD | WS_VISIBLE | SS_CENTER, 20, 30, 505, 34, g_wnd, nullptr, inst, nullptr);
  SendMessageW(t, WM_SETFONT, (WPARAM)big, TRUE);
  HWND sub = CreateWindowW(L"STATIC", L"The original Super Mario 64 (USA) cartridge's dump: .z64, .n64 or .v64.\r\nIt is checked, then the mod's Super Mario 64 files are unlocked with it.",
                           WS_CHILD | WS_VISIBLE | SS_CENTER, 20, 70, 505, 44, g_wnd, nullptr, inst, nullptr);
  SendMessageW(sub, WM_SETFONT, (WPARAM)norm, TRUE);
  g_browse = CreateWindowW(L"BUTTON", L"Browse...", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 210, 124, 125, 34, g_wnd, (HMENU)1, inst, nullptr);
  SendMessageW(g_browse, WM_SETFONT, (WPARAM)norm, TRUE);
  g_bar = CreateWindowW(PROGRESS_CLASSW, nullptr, WS_CHILD | WS_VISIBLE, 20, 176, 505, 20, g_wnd, nullptr, inst, nullptr);
  SendMessageW(g_bar, PBM_SETRANGE32, 0, 1000);
  g_status = CreateWindowW(L"STATIC", L"Waiting for your ROM.", WS_CHILD | WS_VISIBLE | SS_CENTER, 20, 206, 505, 40, g_wnd, nullptr, inst, nullptr);
  SendMessageW(g_status, WM_SETFONT, (WPARAM)norm, TRUE);
  // (a window that runs elevated still takes the drop from Explorer)
  ChangeWindowMessageFilterEx(g_wnd, WM_DROPFILES, MSGFLT_ALLOW, nullptr);
  ChangeWindowMessageFilterEx(g_wnd, WM_COPYDATA, MSGFLT_ALLOW, nullptr);
  ChangeWindowMessageFilterEx(g_wnd, 0x0049, MSGFLT_ALLOW, nullptr);
  ShowWindow(g_wnd, show);
  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
  return 0;
}
