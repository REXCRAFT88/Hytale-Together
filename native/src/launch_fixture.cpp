#include "launch_adapter.cpp"
#include <iostream>
static void check(bool ok,const char* message){if(!ok)throw std::runtime_error(message);std::cout<<"PASS "<<message<<"\n";}
int wmain(int argc,wchar_t** argv){try{
 if(argc>1){return argc==7&&std::wstring(argv[2])==L"test-account"&&std::wstring(argv[4])==fs::temp_directory_path().wstring()&&std::wstring(argv[6])==L"space \" quote \\"?0:7;}
 wchar_t exe[32768];GetModuleFileNameW(nullptr,exe,32768);config=(fs::temp_directory_path()/(L"hytale-launch-test-"+std::to_wstring(GetCurrentProcessId())+L".ini")).wstring();
 WritePrivateProfileStringW(L"Session",L"Enabled",L"1",config.c_str());WritePrivateProfileStringW(L"Session",L"Executable",exe,config.c_str());WritePrivateProfileStringW(L"Accounts",L"test-account",fs::temp_directory_path().c_str(),config.c_str());
 std::wstring command=quote(exe)+L" --uuid test-account --user-dir "+quote(L"C:\\old folder")+L" --extra "+quote(L"space \" quote \\");std::wstring output;
 check(rewrite(exe,command.c_str(),output),"Known account directory rewritten");
 int count;auto parsed=CommandLineToArgvW(output.c_str(),&count);check(count==7&&std::wstring(parsed[4])==fs::temp_directory_path().wstring()&&std::wstring(parsed[6])==L"space \" quote \\","Argument boundaries and escaping preserved");LocalFree(parsed);
 output.clear();check(!rewrite(L"C:\\unrelated.exe",command.c_str(),output),"Unrelated executable unchanged");
 output.clear();check(!rewrite(exe,(quote(exe)+L" --uuid unknown --user-dir C:\\old").c_str(),output),"Unknown account unchanged");
 check(MH_Initialize()==MH_OK&&MH_CreateHookApi(L"kernel32.dll","CreateProcessW",(LPVOID)launch,(LPVOID*)&original)==MH_OK&&MH_EnableHook(MH_ALL_HOOKS)==MH_OK,"CreateProcessW hook enabled");
 STARTUPINFOW si{};si.cb=sizeof(si);PROCESS_INFORMATION pi{};check(CreateProcessW(exe,command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&si,&pi),"Hook starts actual child");
 check(WaitForSingleObject(pi.hProcess,5000)==WAIT_OBJECT_0,"Child exits normally");DWORD code;GetExitCodeProcess(pi.hProcess,&code);CloseHandle(pi.hThread);CloseHandle(pi.hProcess);check(code==0,"Actual child receives new folder and original arguments");
 MH_DisableHook(MH_ALL_HOOKS);MH_Uninitialize();DeleteFileW(config.c_str());return 0;
}catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
