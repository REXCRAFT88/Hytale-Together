#include <windows.h>
#include <shellapi.h>
#include <MinHook.h>
#include <filesystem>
#include <string>
#include <vector>
namespace fs=std::filesystem;
static HMODULE self;
static decltype(&CreateProcessW) original=nullptr;
static std::wstring config;
static std::wstring quote(const std::wstring& v){
 std::wstring out=L"\"";size_t slash=0;
 for(auto c:v){if(c==L'\\'){++slash;continue;}out.append(c==L'"'?slash*2+1:slash,L'\\');out+=c;slash=0;}
 out.append(slash*2,L'\\');return out+L'"';
}
// Only the user-dir argument changes. Authentication and the launcher's process
// ownership/environment are passed through untouched.
static bool rewrite(const wchar_t* app,const wchar_t* command,std::wstring& result){
 if(!command||GetPrivateProfileIntW(L"Session",L"Enabled",0,config.c_str())!=1)return false;
 int count=0;auto raw=CommandLineToArgvW(command,&count);if(!raw)return false;
 std::vector<std::wstring> args;for(int i=0;i<count;i++)args.emplace_back(raw[i]);LocalFree(raw);
 if(args.empty())return false;
 wchar_t expected[32768]{};GetPrivateProfileStringW(L"Session",L"Executable",L"",expected,32768,config.c_str());
 if(!*expected||_wcsicmp(app&&*app?app:args[0].c_str(),expected))return false;
 std::wstring uuid;int directory=-1;bool equals=false;
 for(size_t i=1;i<args.size();i++){
  if(args[i]==L"--uuid"&&i+1<args.size())uuid=args[i+1];
  else if(args[i].rfind(L"--uuid=",0)==0)uuid=args[i].substr(7);
  if(args[i]==L"--user-dir"&&i+1<args.size()){directory=int(i+1);equals=false;}
  else if(args[i].rfind(L"--user-dir=",0)==0){directory=int(i);equals=true;}
 }
 if(uuid.empty()||directory<0)return false;
 wchar_t target[32768]{};GetPrivateProfileStringW(L"Accounts",uuid.c_str(),L"",target,32768,config.c_str());
 if(!*target||!fs::path(target).is_absolute()||!fs::is_directory(target))return false;
 args[directory]=(equals?L"--user-dir=":L"")+std::wstring(target);
 for(auto& arg:args){if(!result.empty())result+=L' ';result+=quote(arg);}return true;
}
static BOOL WINAPI launch(LPCWSTR app,LPWSTR command,LPSECURITY_ATTRIBUTES pa,LPSECURITY_ATTRIBUTES ta,BOOL inherit,DWORD flags,LPVOID env,LPCWSTR cwd,LPSTARTUPINFOW startup,LPPROCESS_INFORMATION process){
 std::wstring changed;
 try{if(rewrite(app,command,changed))return original(app,changed.data(),pa,ta,inherit,flags,env,cwd,startup,process);}catch(...){SetLastError(ERROR_INVALID_DATA);return FALSE;}
 return original(app,command,pa,ta,inherit,flags,env,cwd,startup,process);
}
extern "C" __declspec(dllexport) DWORD WINAPI StartLaunchAdapter(void*){
 if(original)return 0;
 wchar_t path[32768]{};GetModuleFileNameW(self,path,32768);config=(fs::path(path).parent_path()/L"launcher-routing.ini").wstring();
 if(MH_Initialize()!=MH_OK)return 1;
 if(MH_CreateHookApi(L"kernel32.dll","CreateProcessW",(LPVOID)launch,(LPVOID*)&original)!=MH_OK)return 2;
 if(MH_EnableHook(MH_ALL_HOOKS)!=MH_OK){original=nullptr;return 3;}return 0;
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH){self=instance;DisableThreadLibraryCalls(instance);}return TRUE;}
