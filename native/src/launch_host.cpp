#include <windows.h>
#include "remote_ops.h"
#include <tlhelp32.h>
#include <filesystem>
#include <iostream>
#include <stdexcept>
namespace fs=std::filesystem;
struct Handle{HANDLE h;Handle(HANDLE v):h(v){}~Handle(){if(h&&h!=INVALID_HANDLE_VALUE)CloseHandle(h);}operator HANDLE()const{return h;}};
static uintptr_t module(DWORD pid,const wchar_t* name){Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPMODULE,pid));MODULEENTRY32W m{};m.dwSize=sizeof(m);if(Module32FirstW(snap,&m))do{if(!_wcsicmp(m.szModule,name))return uintptr_t(m.modBaseAddr);}while(Module32NextW(snap,&m));return 0;}
static DWORD call(HANDLE p,uintptr_t address,void* arg){Handle t(RemoteOps::RemoteThread(p,nullptr,0,(LPTHREAD_START_ROUTINE)address,arg,0,nullptr));if(!t.h||WaitForSingleObject(t,10000)!=WAIT_OBJECT_0)throw std::runtime_error("Launcher adapter operation failed or timed out. Restart launcher before retrying.");DWORD result;GetExitCodeThread(t,&result);return result;}
int wmain(int argc,wchar_t** argv){try{
 if(argc!=2)throw std::runtime_error("Usage: HytaleLaunchHost PID");DWORD pid=std::stoul(argv[1]);
 Handle p(OpenProcess(PROCESS_CREATE_THREAD|PROCESS_QUERY_INFORMATION|PROCESS_VM_OPERATION|PROCESS_VM_WRITE|PROCESS_VM_READ,FALSE,pid));if(!p.h)throw std::runtime_error("Cannot open launcher");
 wchar_t path[32768]{};DWORD n=32768;if(!QueryFullProcessImageNameW(p,0,path,&n))throw std::runtime_error("Cannot verify launcher");
 if(_wcsicmp(path,L"C:\\Program Files\\Hypixel Studios\\Hytale Launcher\\hytale-launcher.exe"))throw std::runtime_error("Only the installed official Hytale launcher is supported");
 GetModuleFileNameW(nullptr,path,32768);auto dll=fs::path(path).parent_path()/L"HytaleLaunch.dll";
 auto base=module(pid,L"HytaleLaunch.dll");
 if(!base){
  auto text=dll.wstring();auto size=(text.size()+1)*sizeof(wchar_t);void* buffer=RemoteOps::Alloc(p,nullptr,size,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
  if(!buffer||!RemoteOps::Write(p,buffer,text.c_str(),size,nullptr))throw std::runtime_error("Cannot pass adapter path");
  auto load=RemoteOps::GetProc(GetModuleHandleW(L"kernel32.dll"),OBF_STR("LoadLibraryW").c_str());HMODULE owner=nullptr;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,(LPCWSTR)load,&owner);
  GetModuleFileNameW(owner,path,32768);auto remote=module(pid,fs::path(path).filename().c_str());if(!remote)throw std::runtime_error("Launcher loader not found");
  call(p,remote+uintptr_t(load)-uintptr_t(owner),buffer);RemoteOps::Free(p,buffer,0,MEM_RELEASE);base=module(pid,L"HytaleLaunch.dll");if(!base)throw std::runtime_error("Launcher adapter did not load");
 }
 auto local=LoadLibraryExW(dll.c_str(),nullptr,DONT_RESOLVE_DLL_REFERENCES);if(!local)throw std::runtime_error("Cannot read launcher adapter");auto start=GetProcAddress(local,"StartLaunchAdapter");if(!start)throw std::runtime_error("Launcher adapter export missing");auto offset=uintptr_t(start)-uintptr_t(local);FreeLibrary(local);
 if(call(p,base+offset,nullptr))throw std::runtime_error("Launcher hook initialization failed");std::cout<<"Official launcher routing enabled. New game launches use account-specific folders.\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
