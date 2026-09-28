#include "common.h"
#include <iostream>
#include <stdexcept>
#include <filesystem>
#include <vector>
#include <cmath>
static void check(bool ok,const char* what){if(!ok)throw std::runtime_error(std::string(what)+" SDL="+SDL_GetError());std::cout<<"PASS "<<what<<std::endl;}
static void drain(){SDL_Event e{};for(int k=0;k<5000&&SDL_PollEvent(&e);++k){}}
int main(int argc,char** argv){try{
    int which=argc>1?atoi(argv[1]):2;if(which<1||which>2)return 2;
    check(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_GAMEPAD),"SDL initialized");
    auto window=SDL_CreateWindow("Hytale input fixture",320,240,SDL_WINDOW_HIDDEN);check(window,"Hidden background window created");
    SDL_VirtualJoystickTouchpadDesc touchDesc{};touchDesc.nfingers=1;SDL_Event ev{};
    SDL_VirtualJoystickDesc desc{};SDL_INIT_INTERFACE(&desc);desc.type=SDL_JOYSTICK_TYPE_GAMEPAD;desc.vendor_id=0x1234;desc.product_id=0x4321;desc.naxes=6;desc.nbuttons=SDL_GAMEPAD_BUTTON_COUNT;desc.ntouchpads=1;desc.touchpads=&touchDesc;desc.axis_mask=0x3f;desc.button_mask=(1u<<SDL_GAMEPAD_BUTTON_COUNT)-1;
    desc.name="HytaleInputFixture-A";auto a=SDL_AttachVirtualJoystick(&desc);desc.name="HytaleInputFixture-B";auto b=SDL_AttachVirtualJoystick(&desc);check(a&&b,"Identical VID/PID virtual devices created");
    auto ja=SDL_OpenJoystick(a),jb=SDL_OpenJoystick(b);auto ga=SDL_OpenGamepad(a),gb=SDL_OpenGamepad(b);check(ja&&jb&&ga&&gb,"Both controller handles opened BEFORE hook attachment");
    drain();int baseline=0;auto originalIds=SDL_GetGamepads(&baseline);SDL_free(originalIds);
    auto id=which==1?a:b;auto chosen=which==1?ga:gb;auto denied=which==1?gb:ga;
    auto chosenJ=which==1?ja:jb;auto deniedJ=which==1?jb:ja;
    HANDLE map=CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,sizeof(Shared),mappingName(GetCurrentProcessId()).c_str());auto s=(Shared*)MapViewOfFile(map,FILE_MAP_ALL_ACCESS,0,0,sizeof(Shared));check(s,"Session shared memory created");
    *s=Shared{};s->pid=GetCurrentProcessId();s->creation=creationTime(GetCurrentProcess());s->identity=deviceIdentity(id);s->escapeButton=3;check(s->identity!=0,"Selected controller has stable identity");
    SDL_CloseGamepad(chosen);chosen=nullptr;if(which==1)ga=nullptr;else gb=nullptr;
    auto dll=LoadLibraryW(L"HytaleInput-v5.dll");check(dll,"Adapter loaded");auto start=(DWORD(WINAPI*)(void*))GetProcAddress(dll,"StartAdapter");check(start&&start(nullptr)==0,"Hooks installed");drain();check(s->phase==2&&s->selected==id&&s->background==1,"Main-thread initialization and background hint acknowledged");
    check(SDL_GetGamepadFromID(id)!=nullptr,"Adapter owns selected pad even when game has not opened it");
    chosen=SDL_OpenGamepad(id);if(which==1)ga=chosen;else gb=chosen;
    // A selected input adapter must not rewrite a genuine loopback sender.
    WSADATA winsock{};check(WSAStartup(MAKEWORD(2,2),&winsock)==0,"Winsock initialized for network regression");
    SOCKET receiver=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP),sender=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);
    check(receiver!=INVALID_SOCKET&&sender!=INVALID_SOCKET,"Loopback UDP test sockets created");
    sockaddr_in local{};local.sin_family=AF_INET;local.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    check(bind(receiver,(sockaddr*)&local,sizeof(local))==0,"Loopback receiver bound");
    int localSize=sizeof(local);check(getsockname(receiver,(sockaddr*)&local,&localSize)==0,"Loopback ephemeral port resolved");
    s->wanIp=inet_addr("203.0.113.17");
    check(sendto(sender,"lan",3,0,(sockaddr*)&local,sizeof(local))==3,"Loopback datagram sent unchanged");
    DWORD timeout=2000;setsockopt(receiver,SOL_SOCKET,SO_RCVTIMEO,(char*)&timeout,sizeof(timeout));
    sockaddr_in peer{};int peerSize=sizeof(peer);char payload[8]{};
    check(recvfrom(receiver,payload,sizeof(payload),0,(sockaddr*)&peer,&peerSize)==3&&peer.sin_addr.s_addr==htonl(INADDR_LOOPBACK),"Loopback reply retains real address despite legacy WAN configuration");
    closesocket(sender);closesocket(receiver);WSACleanup();s->wanIp=0;
    SDL_SetJoystickVirtualAxis(ja,0,12345);SDL_SetJoystickVirtualAxis(jb,0,23456);SDL_SetJoystickVirtualButton(ja,0,true);SDL_SetJoystickVirtualButton(jb,0,true);SDL_UpdateJoysticks();
    check(SDL_GetGamepadAxis(denied,SDL_GAMEPAD_AXIS_LEFTX)==0&&!SDL_GetGamepadButton(denied,SDL_GAMEPAD_BUTTON_SOUTH),"Previously opened unassigned gamepad neutralized");
    check(SDL_GetGamepadAxis(chosen,SDL_GAMEPAD_AXIS_LEFTX)==(which==1?12345:23456)&&SDL_GetGamepadButton(chosen,SDL_GAMEPAD_BUTTON_SOUTH),"Assigned gamepad works while background window is hidden");
    check(SDL_GetJoystickAxis(deniedJ,0)==0&&SDL_GetJoystickAxis(chosenJ,0)!=0,"Joystick polling is also isolated");
    check(SDL_SetJoystickVirtualTouchpad(chosenJ,0,0,true,0.25f,0.5f,0.75f),"Virtual DualSense touchpad activated");SDL_UpdateJoysticks();drain();
    ev={};ev.type=SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION;ev.gtouchpad.which=id;ev.gtouchpad.touchpad=0;ev.gtouchpad.finger=0;ev.gtouchpad.x=0.25f;ev.gtouchpad.y=0.5f;check(SDL_PushEvent(&ev),"Touchpad motion queued");
    bool moved=false;for(int i=0;i<32&&SDL_PollEvent(&ev);i++){if(ev.type==SDL_EVENT_MOUSE_MOTION){moved=ev.motion.windowID==SDL_GetWindowID(window)&&ev.motion.x>70&&ev.motion.x<90&&ev.motion.y>110&&ev.motion.y<130;break;}}check(moved,"Touchpad becomes a mouse inside this player's window");
    SDL_SetJoystickVirtualButton(chosenJ,SDL_GAMEPAD_BUTTON_TOUCHPAD,true);SDL_UpdateJoysticks();
    check(SDL_GetGamepadButton(chosen,SDL_GAMEPAD_BUTTON_TOUCHPAD),"Virtual touchpad click state is exposed");
    bool clickDown=false;for(int i=0;i<32&&!clickDown;i++)if(SDL_PollEvent(&ev)&&ev.type==SDL_EVENT_MOUSE_BUTTON_DOWN)clickDown=true;
    check(clickDown&&(SDL_GetMouseState(nullptr,nullptr)&SDL_BUTTON_LMASK),"Touchpad click becomes an independent left click");
    SDL_SetJoystickVirtualButton(chosenJ,SDL_GAMEPAD_BUTTON_TOUCHPAD,false);SDL_UpdateJoysticks();
    bool clickUp=false;for(int i=0;i<32&&!clickUp;i++)if(SDL_PollEvent(&ev)&&ev.type==SDL_EVENT_MOUSE_BUTTON_UP)clickUp=true;check(clickUp,"Touchpad release becomes mouse release");
    for(auto button:{SDL_GAMEPAD_BUTTON_MISC1,SDL_GAMEPAD_BUTTON_GUIDE}){SDL_SetJoystickVirtualButton(chosenJ,button,true);SDL_UpdateJoysticks();bool keyDown=false;for(int i=0;i<32&&!keyDown;i++)if(SDL_PollEvent(&ev)&&ev.type==SDL_EVENT_KEY_DOWN)keyDown=ev.key.scancode==SDL_SCANCODE_ESCAPE;check(keyDown,"Share/PS button sends Escape down");SDL_SetJoystickVirtualButton(chosenJ,button,false);SDL_UpdateJoysticks();bool keyUp=false;for(int i=0;i<32&&!keyUp;i++)if(SDL_PollEvent(&ev)&&ev.type==SDL_EVENT_KEY_UP)keyUp=ev.key.scancode==SDL_SCANCODE_ESCAPE;check(keyUp,"Share/PS button sends Escape up");}
    drain();
    int n=99;auto ids=SDL_GetGamepads(&n);check(ids&&n==1&&ids[0]==id&&ids[1]==0,"Filtered enumeration preserves real ID and zero termination");SDL_free(ids);
    ids=SDL_GetGamepads(nullptr);check(ids&&ids[0]==id&&ids[1]==0,"Null count pointer supported");SDL_free(ids);
    check(!SDL_OpenGamepad(which==1?b:a),"Opening another player's gamepad rejected");
    drain();SDL_FlushEvents(SDL_EVENT_GAMEPAD_BUTTON_DOWN,SDL_EVENT_GAMEPAD_BUTTON_UP);ev={};ev.type=SDL_EVENT_GAMEPAD_BUTTON_DOWN;ev.gbutton.which=which==1?b:a;ev.gbutton.button=0;SDL_PushEvent(&ev);ev.gbutton.which=id;SDL_PushEvent(&ev);
    ev={};ev.type=SDL_EVENT_USER;ev.user.code=41;SDL_PushEvent(&ev);ev.user.code=42;SDL_PushEvent(&ev);
    SDL_Event peek[16]{};int k=SDL_PeepEvents(peek,16,SDL_PEEKEVENT,SDL_EVENT_GAMEPAD_BUTTON_DOWN,SDL_EVENT_GAMEPAD_BUTTON_DOWN);
    bool onlySelected=k>=1;for(int i=0;i<k;i++)onlySelected&=peek[i].gbutton.which==id;
    check(onlySelected,"PeepEvent PEEK removes only denied input and retains selected input");
    k=SDL_PeepEvents(peek,16,SDL_GETEVENT,SDL_EVENT_GAMEPAD_BUTTON_DOWN,SDL_EVENT_GAMEPAD_BUTTON_DOWN);onlySelected=k>=1;for(int i=0;i<k;i++)onlySelected&=peek[i].gbutton.which==id;check(onlySelected,"PeepEvent GET agrees with PEEK");
    k=SDL_PeepEvents(peek,16,SDL_GETEVENT,SDL_EVENT_USER,SDL_EVENT_USER);check(k==2&&peek[0].user.code==41&&peek[1].user.code==42,"Unrelated event order preserved");
    drain();ev={};ev.type=SDL_EVENT_USER;ev.user.code=77;SDL_PushEvent(&ev);
    check(SDL_WaitEventTimeout(nullptr,10),"Null-output wait reports available event");
    k=SDL_PeepEvents(peek,16,SDL_GETEVENT,SDL_EVENT_USER,SDL_EVENT_USER);check(k==1&&peek[0].user.code==77,"Null-output wait preserves queued event");
    s->command=2;drain();check(SDL_GetGamepadAxis(chosen,SDL_GAMEPAD_AXIS_LEFTX)==0,"Pause neutralizes selected state");
    s->command=1;drain();check(SDL_GetGamepadAxis(chosen,SDL_GAMEPAD_AXIS_LEFTX)!=0,"Resume restores selected state");
    POINT before{},after{};GetCursorPos(&before);SDL_WarpMouseInWindow(window,91,72);float x=0,y=0;SDL_GetMouseState(&x,&y);GetCursorPos(&after);
    check(x==91&&y==72&&before.x==after.x&&before.y==after.y,"Virtual cursor tracks warps without moving desktop cursor");
    check(SDL_SetWindowRelativeMouseMode(window,true)&&SDL_GetWindowRelativeMouseMode(window),"Relative mode request is virtualized");
    ev={};ev.type=SDL_EVENT_WINDOW_FOCUS_LOST;ev.window.windowID=SDL_GetWindowID(window);SDL_PushEvent(&ev);
    k=SDL_PeepEvents(peek,16,SDL_GETEVENT,SDL_EVENT_WINDOW_FOCUS_LOST,SDL_EVENT_WINDOW_FOCUS_LOST);check(k==0,"Focus-loss event does not pause controller client");
    check(SDL_GetWindowFlags(window)&SDL_WINDOW_INPUT_FOCUS,"Game sees process-local focus without OS focus stealing");
    // Detach requires real SDL device API, which is deliberately not hooked.
    SDL_DetachVirtualJoystick(id);Sleep(550);drain();check(s->phase==3&&SDL_GetGamepadAxis(chosen,SDL_GAMEPAD_AXIS_LEFTX)==0,"Disconnect neutralizes input without selecting another pad");
    desc.name=which==1?"HytaleInputFixture-A":"HytaleInputFixture-B";auto replacement=SDL_AttachVirtualJoystick(&desc);Sleep(550);drain();
    check(s->phase==2&&s->selected==replacement&&replacement!=id,"Reconnect resolves the same identity to its new SDL ID");
    auto newJ=SDL_OpenJoystick(replacement);auto newG=SDL_OpenGamepad(replacement);SDL_SetJoystickVirtualAxis(newJ,0,17777);SDL_UpdateJoysticks();check(SDL_GetGamepadAxis(newG,SDL_GAMEPAD_AXIS_LEFTX)==17777,"Reconnected assigned device produces input");
    s->identity=KbmIdentity;InterlockedIncrement(&s->generation);drain();
    check(s->phase==2,"KBM mode transitions to ready");
    int kbmCount=99;auto kbmIds=SDL_GetGamepads(&kbmCount);check(kbmIds&&kbmCount==0,"KBM mode bars all controllers from enumeration");SDL_free(kbmIds);
    check(!SDL_HasGamepad(),"KBM mode reports no active gamepad");
    check(SDL_GetGamepadAxis(newG,SDL_GAMEPAD_AXIS_LEFTX)==0&&!SDL_GetGamepadButton(newG,SDL_GAMEPAD_BUTTON_SOUTH),"KBM mode neutralizes controller input");
    s->command=3;drain();check(s->phase==4,"Stop acknowledged without unsafe DLL unload");
    ids=SDL_GetGamepads(&n);SDL_free(ids);check(n==baseline,"Stop restores normal enumeration");
    std::cout<<"ALL CHECKS PASSED player="<<which<<" hooks="<<s->hookCount<<"\n";
    SDL_CloseGamepad(newG);SDL_CloseJoystick(newJ);SDL_CloseGamepad(ga);SDL_CloseGamepad(gb);SDL_CloseJoystick(ja);SDL_CloseJoystick(jb);SDL_DestroyWindow(window);SDL_Quit();return 0;
}catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<std::endl;return 1;}}

