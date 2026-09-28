#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <SDL3/SDL.h>
#include <cstdint>
#include <string>
#include <cstdio>
constexpr uint32_t Protocol = 0x48594905;
struct Shared {
    uint32_t protocol = Protocol;
    uint32_t pid = 0;
    uint64_t creation = 0;
    uint64_t identity = 0;
    volatile LONG command = 1; // 1 run, 2 pause (neutral), 3 stop/pass through
    volatile LONG phase = 0;   // 0 pending, 1 hooks installed, 2 ready, 3 disconnected, 4 stopped, -1 error
    volatile LONG generation = 1;
    volatile LONG selected = 0;
    volatile LONG version = 0;
    volatile LONG polls = 0, peeps = 0, stateReads = 0, passed = 0, dropped = 0;
    volatile LONG warps = 0, relatives = 0, focusLost = 0, opens = 0;
    volatile LONG background = 0, hookCount = 0;
    volatile LONG softwareCursor = 0;
    volatile LONG touchpadMouse = 1;
    volatile LONG escapeButton = 1; // 1 Share, 2 Guide/PS, 3 either
    volatile LONG syntheticMouseButtons = 0;
    uint32_t wanIp = 0; // IPv4 address in network byte order to redirect locally
    char error[256] = {};
};
constexpr uint64_t KbmIdentity = 0xFFFFFFFFFFFFFFFFULL;
inline bool isKbmIdentity(uint64_t id) { return id == KbmIdentity; }

inline uint64_t fingerprint(const char* text) {
    if (!text || !*text) return 0;
    uint64_t h=14695981039346656037ULL;
    for (;*text;++text) { unsigned char c=*text; if(c>='A'&&c<='Z')c+=32; h=(h^c)*1099511628211ULL; }
    return h;
}
inline uint64_t deviceIdentity(SDL_JoystickID id) {
    const char* p = SDL_GetJoystickPathForID(id);
    if (!p || !*p) p = SDL_GetGamepadPathForID(id);
    if (p && *p) return fingerprint(p);
    // Virtual fixtures have no path. Real assignments require a nonempty path.
    const char* n = SDL_GetJoystickNameForID(id);
    return n && strncmp(n, "HytaleInputFixture-", 19) == 0 ? fingerprint(n) : 0;
}
inline std::wstring mappingName(DWORD pid) { return L"Local\\HytaleInput-v5-"+std::to_wstring(pid); }
inline uint64_t creationTime(HANDLE process) { FILETIME a{},b{},c{},d{}; if(!GetProcessTimes(process,&a,&b,&c,&d))return 0; return (uint64_t(a.dwHighDateTime)<<32)|a.dwLowDateTime; }
