#include "common.h"
#include "remote_ops.h"
#include <tlhelp32.h>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <vector>
#include <algorithm>
#include <stdexcept>
namespace fs=std::filesystem;
static fs::path folder(){wchar_t b[32768];GetModuleFileNameW(nullptr,b,32768);return fs::path(b).parent_path();}
static void fail(const char* text){throw std::runtime_error(std::string(text)+" (Windows error "+std::to_string(GetLastError())+")");}
struct Handle{HANDLE h=nullptr;Handle(HANDLE p=nullptr):h(p){}~Handle(){if(h&&h!=INVALID_HANDLE_VALUE)CloseHandle(h);}operator HANDLE()const{return h;}};
struct Mapping{
    Handle handle;Shared* s=nullptr;
    Mapping(DWORD pid,bool create):handle(create?CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,sizeof(Shared),mappingName(pid).c_str()):OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,mappingName(pid).c_str())){
        if(handle.h)s=(Shared*)MapViewOfFile(handle,FILE_MAP_ALL_ACCESS,0,0,sizeof(Shared));
    }
    ~Mapping(){if(s)UnmapViewOfFile(s);}
};
static uintptr_t module(DWORD pid,const wchar_t* name){
    Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPMODULE|TH32CS_SNAPMODULE32,pid));MODULEENTRY32W m{};m.dwSize=sizeof(m);
    if(Module32FirstW(snap,&m))do{if(!_wcsicmp(m.szModule,name))return (uintptr_t)m.modBaseAddr;}while(Module32NextW(snap,&m));return 0;
}
static DWORD remote(HANDLE process,uintptr_t entry,void* arg){
    Handle thread(RemoteOps::RemoteThread(process,nullptr,0,(LPTHREAD_START_ROUTINE)entry,arg,0,nullptr));if(!thread.h)fail("Remote execution initiation failed");
    if(WaitForSingleObject(thread,15000)!=WAIT_OBJECT_0)throw std::runtime_error("Remote operation timed out; game must be restarted before retrying");
    DWORD code=0;GetExitCodeThread(thread,&code);return code;
}
static void print(Shared* s){
    std::cout<<"{\"pid\":"<<s->pid<<",\"phase\":"<<s->phase<<",\"sdlVersion\":"<<s->version
      <<",\"selectedId\":"<<s->selected<<",\"background\":"<<s->background<<",\"hooks\":"<<s->hookCount
      <<",\"pollCalls\":"<<s->polls<<",\"peepCalls\":"<<s->peeps<<",\"stateReads\":"<<s->stateReads
      <<",\"passedEvents\":"<<s->passed<<",\"droppedEvents\":"<<s->dropped<<",\"cursorWarps\":"<<s->warps
      <<",\"relativeRequests\":"<<s->relatives<<",\"focusLosses\":"<<s->focusLost<<",\"openCalls\":"<<s->opens<<",\"softwareCursor\":"<<s->softwareCursor
      <<",\"touchpadMouse\":"<<s->touchpadMouse<<",\"escapeButton\":"<<s->escapeButton<<"}"<<std::endl;
    if(s->error[0])std::cerr<<s->error<<std::endl;
}
static void attach(DWORD pid,uint64_t identity,bool touchpadMouse=true,LONG escapeButton=1,uint32_t wanIp=0){
    Handle process(OpenProcess(PROCESS_CREATE_THREAD|PROCESS_QUERY_INFORMATION|PROCESS_VM_OPERATION|PROCESS_VM_WRITE|PROCESS_VM_READ|SYNCHRONIZE,FALSE,pid));if(!process.h)fail("Cannot open target; run at the same privilege level as the game");
    wchar_t path[32768]{};DWORD n=32768;if(!QueryFullProcessImageNameW(process,0,path,&n))fail("Cannot verify target path");
    auto name=fs::path(path).filename().wstring();
    bool fixture=name==L"HytaleInputFixture.exe" && fs::equivalent(fs::path(path).parent_path(),folder());
    if(_wcsicmp(name.c_str(),L"HytaleClient.exe")&&!fixture)throw std::runtime_error("Refusing unrelated target executable");
    if(!module(pid,L"SDL3.dll"))throw std::runtime_error("Target SDL3.dll is not loaded yet");
    if(module(pid,L"ProtoInputHooks64.dll"))throw std::runtime_error("Restart client without old Proto Input hooks before attaching SDL3 adapter");
    auto dll=folder()/L"HytaleInput-v5.dll";if(!fs::exists(dll))throw std::runtime_error("HytaleInput-v5.dll is missing");
    Mapping map(pid,true);if(!map.s)fail("Cannot create session mapping");
    if(map.s->protocol==Protocol&&map.s->creation==creationTime(process)){
        if(map.s->phase==4)throw std::runtime_error("Adapter stopped: restart this client to attach again");
        map.s->identity=identity;map.s->touchpadMouse=touchpadMouse;map.s->escapeButton=escapeButton;
        if(wanIp)map.s->wanIp=wanIp;
        map.s->command=1;InterlockedIncrement(&map.s->generation);
    }else{
        if(module(pid,L"HytaleInput-v5.dll"))throw std::runtime_error("An old adapter is already loaded; restart this client");
        *map.s=Shared{};map.s->pid=pid;map.s->creation=creationTime(process);map.s->identity=identity;
        map.s->touchpadMouse=touchpadMouse;map.s->escapeButton=escapeButton;
        if(wanIp)map.s->wanIp=wanIp;
        map.s->command=1;InterlockedIncrement(&map.s->generation);
        std::wstring value=dll.wstring();SIZE_T bytes=(value.size()+1)*sizeof(wchar_t);
        void* buffer=RemoteOps::Alloc(process,nullptr,bytes,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);if(!buffer)fail("Remote allocation failed");
        if(!RemoteOps::Write(process,buffer,value.c_str(),bytes,nullptr))fail("Remote write failed");
        // Resolve the actual owner of LoadLibraryW, then compute its remote RVA.
        auto load=RemoteOps::GetProc(GetModuleHandleW(L"kernel32.dll"),OBF_STR("LoadLibraryW").c_str());HMODULE owner=nullptr;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,(LPCWSTR)load,&owner);
        wchar_t ownerPath[32768];GetModuleFileNameW(owner,ownerPath,32768);
        uintptr_t ownerRemote=module(pid,fs::path(ownerPath).filename().c_str());if(!ownerRemote)fail("Remote loader module missing");
        remote(process,ownerRemote+((uintptr_t)load-(uintptr_t)owner),buffer);
        RemoteOps::Free(process,buffer,0,MEM_RELEASE);
        uintptr_t base=module(pid,L"HytaleInput-v5.dll");if(!base)throw std::runtime_error("LoadLibrary did not load the adapter");
        HMODULE local=LoadLibraryExW(dll.c_str(),nullptr,DONT_RESOLVE_DLL_REFERENCES);if(!local)fail("Cannot read adapter export");
        auto start=GetProcAddress(local,"StartAdapter");if(!start)fail("Adapter export missing");uintptr_t offset=(uintptr_t)start-(uintptr_t)local;FreeLibrary(local);
        DWORD result=remote(process,base+offset,nullptr);if(result)throw std::runtime_error("Adapter initialization failed: "+std::to_string(result)+" "+map.s->error);
    }
    // A newly started game can finish SDL discovery after the first event poll.
    // Wait briefly up to 2 seconds for initial poll.
    for(int i=0;i<40&&map.s->phase!=2&&map.s->phase>=0&&map.s->phase!=4;++i)Sleep(50);
    print(map.s);
    if(map.s->phase<0||map.s->phase==4)throw std::runtime_error("Adapter initialization error: "+std::string(map.s->error));
}
struct Device{SDL_JoystickID id;uint64_t key;std::string name;Uint16 vendor,product;SDL_Gamepad* pad;};
static std::vector<Device> devices(){
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,"1");
    if(!SDL_Init(SDL_INIT_GAMEPAD))throw std::runtime_error(SDL_GetError());
    // Discovery is asynchronous on Windows; immediate enumeration is misleading.
    for(int i=0;i<20;++i){SDL_PumpEvents();Sleep(50);}
    std::vector<Device> result;int n=0;auto ids=SDL_GetGamepads(&n);
    for(int i=0;ids&&i<n;++i){auto p=SDL_OpenGamepad(ids[i]);if(!p)continue;auto name=SDL_GetGamepadName(p);result.push_back({ids[i],deviceIdentity(ids[i]),name?name:"Unknown",SDL_GetGamepadVendor(p),SDL_GetGamepadProduct(p),p});}
    SDL_free(ids);return result;
}
static void listDevices(){auto d=devices();for(auto& p:d){printf("%016llx  %-32s VID=%04x PID=%04x\n",p.key,p.name.c_str(),p.vendor,p.product);}if(d.empty())throw std::runtime_error("No controllers discovered after event pumping");SDL_Quit();}
static std::vector<uint64_t> assignments(){std::ifstream f(folder()/"players.txt");std::vector<uint64_t> a;uint64_t id;while(f>>std::hex>>id)a.push_back(id);if(a.size()!=2||!a[0]||!a[1]||a[0]==a[1])throw std::runtime_error("Run HytaleInputHost assign first; two distinct physical controllers are required");return a;}
static void assign(){
    auto all=devices();std::vector<Device> pads;for(auto& d:all)if(d.vendor==0x054c&&d.product==0x0ce6&&d.key)pads.push_back(d);
    if(pads.size()!=2)throw std::runtime_error("Expected two physical DualSense devices with stable SDL paths; reconnect both and retry");
    uint64_t chosen[2]{};
    for(int player=0;player<2;++player){
        std::cout<<"Release all buttons, then press CROSS on Player "<<player+1<<"'s DualSense."<<std::endl;
        bool released=false;Uint64 deadline=SDL_GetTicks()+90000;
        while(SDL_GetTicks()<deadline){SDL_PumpEvents();bool any=false;for(auto& d:pads)any|=SDL_GetGamepadButton(d.pad,SDL_GAMEPAD_BUTTON_SOUTH);
            if(!any)released=true;
            if(released)for(auto& d:pads)if(d.key!=chosen[0]&&SDL_GetGamepadButton(d.pad,SDL_GAMEPAD_BUTTON_SOUTH)){chosen[player]=d.key;break;}
            if(chosen[player])break;Sleep(15);
        }
        if(!chosen[player])throw std::runtime_error("Assignment timed out without saving changes");std::cout<<"Player "<<player+1<<" assigned."<<std::endl;
    }
    std::ofstream out(folder()/"players.txt",std::ios::trunc);if(!out)throw std::runtime_error("Cannot write assignment file");out<<std::hex<<chosen[0]<<"\n"<<chosen[1]<<"\n";out.close();SDL_Quit();
}
static std::vector<DWORD> gamePids(){
    std::vector<std::pair<uint64_t,DWORD>> found;Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0));PROCESSENTRY32W p{};p.dwSize=sizeof(p);
    if(Process32FirstW(snap,&p))do{if(!_wcsicmp(p.szExeFile,L"HytaleClient.exe")){Handle proc(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,p.th32ProcessID));if(proc.h)found.push_back({creationTime(proc),p.th32ProcessID});}}while(Process32NextW(snap,&p));
    std::sort(found.begin(),found.end());std::vector<DWORD> ids;for(auto x:found)ids.push_back(x.second);return ids;
}
int main(int argc,char** argv){try{
    if(argc<2){std::cout<<"devices | assign | attach PID ID_HEX [TOUCHPAD 0|1] [ESCAPE 0-3] | hid PID HID_PATH | player PID 1|2 | attach-pair | status PID | pause PID | resume PID | stop PID\n";return 0;}
    std::string cmd=argv[1];
    if(cmd=="devices"){listDevices();return 0;}if(cmd=="assign"){assign();return 0;}
    if(argc<3)throw std::runtime_error("Missing PID");DWORD pid=std::stoul(argv[2]);
    if(cmd=="attach"&&argc>=4){
        bool touchpad=argc<5||std::stoi(argv[4])!=0;
        LONG escape=argc<6?1:std::stol(argv[5]);
        if(escape<0||escape>3)throw std::runtime_error("Escape button must be 0 (off), 1 (Share), 2 (PS), or 3 (both)");
        uint32_t wanIp = 0;
        if(argc>=7 && argv[6] && argv[6][0]) {
            wanIp = inet_addr(argv[6]);
            if(wanIp == INADDR_NONE) wanIp = 0;
        }
        uint64_t id = 0;
        if(_stricmp(argv[3],"kbm")==0 || _stricmp(argv[3],"keyboard")==0){
            id = KbmIdentity;
        } else {
            id = std::stoull(argv[3],nullptr,16);
        }
        attach(pid,id,touchpad,escape,wanIp);
        return 0;
    }
    if(cmd=="hid"&&argc==4){
        auto key=fingerprint(argv[3]);auto pads=devices();int matches=0;
        for(auto& p:pads)if(p.key==key)++matches;
        SDL_Quit();if(matches!=1)throw std::runtime_error("Nucleus device does not match one native SDL gamepad. Select the physical DualSense, not its virtual Xbox copy.");
        attach(pid,key);return 0;
    }
    if(cmd=="player"&&argc==4){auto a=assignments();int player=std::stoi(argv[3]);if(player<1||player>2)throw std::runtime_error("Player must be 1 or 2");attach(pid,a[player-1]);return 0;}
    Mapping map(pid,false);if(!map.s||map.s->protocol!=Protocol)throw std::runtime_error("No adapter session for this PID");
    Handle target(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid));if(!target.h||creationTime(target)!=map.s->creation)throw std::runtime_error("Target exited or PID changed");
    if(cmd=="pause")map.s->command=2;else if(cmd=="resume")map.s->command=1;else if(cmd=="stop")map.s->command=3;else if(cmd!="status")throw std::runtime_error("Unknown command");
    print(map.s);return 0;
}catch(const std::exception& e){std::cerr<<"ERROR: "<<e.what()<<"\n";return 1;}}
