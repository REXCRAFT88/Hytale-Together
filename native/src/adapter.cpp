#include "common.h"
#include <MinHook.h>
#include <atomic>
#include <deque>
#include <mutex>
#include <vector>
#include <algorithm>
#include <cstring>
#include <cmath>

static Shared* shared=nullptr;
static HANDLE mapHandle=nullptr;
static thread_local int inside=0;
struct Internal { Internal(){++inside;} ~Internal(){--inside;} };
static std::recursive_mutex gate;
static std::deque<SDL_Event> pending;
static SDL_JoystickID selected=0;
// Own a reference so SDL generates input even if the game opened only its first pad.
static SDL_Gamepad* selectedPad=nullptr;
static LONG generation=0, previousCommand=0;
static bool initialized=false, relative=false;
static float cursorX=0.f, cursorY=0.f;
static float lastTouchX=0.f, lastTouchY=0.f;
static float relDeltaX=0.f, relDeltaY=0.f;
static SDL_Window* cursorWindow=nullptr;
static HWND cursorOverlay=nullptr;
static HDC cursorDC=nullptr;
static HBITMAP cursorBitmap=nullptr;
static HGDIOBJ previousBitmap=nullptr;
static bool cursorShown=true;
static bool escapeDown=false;
static bool virtualTouchDown=false;
static Uint64 lastTouchpadEventTick=0;
static bool shareDown=false, guideDown=false, touchpadButtonDown=false;
static std::string previousHint;
static bool hadHint=false;
static Uint64 lastScan=0;
static std::vector<void*> targets;
static bool enabled(){ return shared && !inside && shared->phase!=4 && shared->phase!=-1; }
static bool running(){return shared && shared->command==1;}
static bool isKbm(){ return shared && isKbmIdentity(shared->identity); }
static bool allowed(SDL_JoystickID id){
    if(!running()||!id||isKbm())return false;
    if(id==selected)return true;
    if(shared&&shared->identity&&deviceIdentity(id)==shared->identity)return true;
    return false;
}

#define ORIGINAL(name) static decltype(&SDL_##name) real_##name=nullptr
ORIGINAL(GetGamepads); ORIGINAL(GetJoysticks); ORIGINAL(HasGamepad); ORIGINAL(OpenGamepad); ORIGINAL(OpenJoystick);
ORIGINAL(GetGamepadAxis); ORIGINAL(GetGamepadButton); ORIGINAL(GetJoystickAxis); ORIGINAL(GetJoystickButton); ORIGINAL(GetJoystickHat);
ORIGINAL(GetGamepadTouchpadFinger); ORIGINAL(GetGamepadSensorData); ORIGINAL(RumbleGamepad); ORIGINAL(RumbleGamepadTriggers); ORIGINAL(RumbleJoystick);
ORIGINAL(PollEvent); ORIGINAL(PeepEvents); ORIGINAL(WaitEvent); ORIGINAL(WaitEventTimeout);
ORIGINAL(GetWindowFlags); ORIGINAL(SetWindowRelativeMouseMode); ORIGINAL(GetWindowRelativeMouseMode);
ORIGINAL(WarpMouseInWindow); ORIGINAL(WarpMouseGlobal); ORIGINAL(GetMouseState); ORIGINAL(GetGlobalMouseState); ORIGINAL(GetRelativeMouseState);
ORIGINAL(SetWindowMouseGrab); ORIGINAL(CaptureMouse); ORIGINAL(RaiseWindow); ORIGINAL(SetHintWithPriority);
ORIGINAL(ShowCursor); ORIGINAL(HideCursor);

static LRESULT CALLBACK overlayProc(HWND h,UINT m,WPARAM w,LPARAM l){
    if(m==WM_NCHITTEST)return HTTRANSPARENT;
    if(m==WM_MOUSEACTIVATE)return MA_NOACTIVATE;
    return DefWindowProcW(h,m,w,l);
}
static void clearOverlay(){
    if(cursorOverlay){DestroyWindow(cursorOverlay);cursorOverlay=nullptr;}
    if(cursorDC){SelectObject(cursorDC,previousBitmap);DeleteDC(cursorDC);cursorDC=nullptr;}
    if(cursorBitmap){DeleteObject(cursorBitmap);cursorBitmap=nullptr;}
    if(shared)shared->softwareCursor=0;
}
static bool arrowInside(int x,int y){
    static POINT p[]={{1,1},{1,26},{7,20},{12,30},{17,28},{12,18},{22,18}};
    bool insidePoly=false;
    for(int i=0,j=6;i<7;j=i++)if(((p[i].y>y)!=(p[j].y>y))&&(x<(p[j].x-p[i].x)*double(y-p[i].y)/(p[j].y-p[i].y)+p[i].x))insidePoly=!insidePoly;
    return insidePoly;
}
static void updateCursor(){
    if(!shared||shared->phase==4||shared->phase<0||isKbm()){clearOverlay();return;}
    Internal internal;
    if(!cursorWindow){
        int wn=0; SDL_Window** wins=SDL_GetWindows(&wn);
        if(wins && wn>0){
            cursorWindow = wins[0];
            int width=0, height=0;
            SDL_GetWindowSize(cursorWindow, &width, &height);
            cursorX = width / 2.f;
            cursorY = height / 2.f;
        }
        SDL_free(wins);
    }
    if(!cursorWindow)return;
    HWND owner=(HWND)SDL_GetPointerProperty(SDL_GetWindowProperties(cursorWindow),SDL_PROP_WINDOW_WIN32_HWND_POINTER,nullptr);
    if(!owner)return;
    POINT position{LONG(cursorX),LONG(cursorY)};ClientToScreen(owner,&position);
    bool touchpadActive = shared->touchpadMouse && (virtualTouchDown || (SDL_GetTicks() - lastTouchpadEventTick < 6000));
    bool show = running() && (cursorShown || touchpadActive) && (!relative || touchpadActive) && IsWindowVisible(owner) && !IsIconic(owner);
    if(!show){if(cursorOverlay)ShowWindow(cursorOverlay,SW_HIDE);shared->softwareCursor=0;return;}
    if(!cursorOverlay){
        WNDCLASSW cls{};cls.lpfnWndProc=overlayProc;cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=L"HytaleSplitPrivateCursor";
        RegisterClassW(&cls);
        cursorOverlay=CreateWindowExW(WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW,cls.lpszClassName,L"",WS_POPUP,position.x,position.y,24,32,owner,nullptr,cls.hInstance,nullptr);
        if(!cursorOverlay)return;
        BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=24;info.bmiHeader.biHeight=-32;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
        void* pixels=nullptr;cursorDC=CreateCompatibleDC(nullptr);cursorBitmap=CreateDIBSection(cursorDC,&info,DIB_RGB_COLORS,&pixels,nullptr,0);
        if(!cursorDC||!cursorBitmap||!pixels){clearOverlay();return;}
        previousBitmap=SelectObject(cursorDC,cursorBitmap);
        for(int y=0;y<32;y++)for(int x=0;x<24;x++){
            bool fill=arrowInside(x,y);bool edge=fill&&(!arrowInside(x-1,y)||!arrowInside(x+1,y)||!arrowInside(x,y-1)||!arrowInside(x,y+1));
            ((uint32_t*)pixels)[y*24+x]=!fill?0:edge?0xFF101010:0xFFF7F7F7;
        }
    }
    SIZE size{24,32};POINT source{};BLENDFUNCTION blend{AC_SRC_OVER,0,255,AC_SRC_ALPHA};
    UpdateLayeredWindow(cursorOverlay,nullptr,&position,&size,cursorDC,&source,0,&blend,ULW_ALPHA);
    SetWindowPos(cursorOverlay, HWND_TOPMOST, position.x, position.y, 24, 32, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    shared->softwareCursor=1;
}

static void count(volatile LONG& v){InterlockedIncrement(&v);}
static bool keep(const SDL_Event& e) {
    if (e.type==SDL_EVENT_POLL_SENTINEL) return false;
    if (isKbm()) {
        if((e.type>=SDL_EVENT_JOYSTICK_AXIS_MOTION&&e.type<=SDL_EVENT_JOYSTICK_UPDATE_COMPLETE)||
           (e.type>=SDL_EVENT_GAMEPAD_AXIS_MOTION&&e.type<=SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED)) {
            count(shared->dropped);
            return false;
        }
        return true;
    }
    if (e.type==SDL_EVENT_WINDOW_FOCUS_LOST) {count(shared->focusLost);return false;}
    if((e.type>=SDL_EVENT_JOYSTICK_AXIS_MOTION&&e.type<=SDL_EVENT_JOYSTICK_UPDATE_COMPLETE)||
       (e.type>=SDL_EVENT_GAMEPAD_AXIS_MOTION&&e.type<=SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED)) {
        // All SDL3 joystick/gamepad events store their ID at this shared offset.
        SDL_JoystickID evId = e.jdevice.which;
        bool isMyPad = (evId && evId == selected) || (shared && shared->identity && deviceIdentity(evId) == shared->identity);
        if(!selected && isMyPad) {
            selected = evId;
            shared->selected = evId;
        }
        bool ok = isMyPad && (running() || e.type==SDL_EVENT_GAMEPAD_REMOVED || e.type==SDL_EVENT_JOYSTICK_REMOVED);
        if(!ok)count(shared->dropped); else count(shared->passed);
        return ok;
    }
    return true;
}
static bool SDLCALL prune(void*,SDL_Event* e){return keep(*e);}
static void pushDevice(Uint32 type,SDL_JoystickID id){SDL_Event e{};e.type=type;e.gdevice.which=id;e.gdevice.timestamp=SDL_GetTicksNS();pending.push_back(e);}

static void pushMouseButton(bool down, Uint8 button = SDL_BUTTON_LEFT){
    lastTouchpadEventTick = SDL_GetTicks();
    if(!cursorWindow){
        int wn=0; SDL_Window** wins=SDL_GetWindows(&wn);
        if(wins && wn>0){
            cursorWindow = wins[0];
            int width=0, height=0;
            SDL_GetWindowSize(cursorWindow, &width, &height);
            cursorX = width / 2.f;
            cursorY = height / 2.f;
        }
        SDL_free(wins);
    }
    if(!cursorWindow)return;
    SDL_Event e{};
    e.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
    e.button.timestamp = SDL_GetTicksNS();
    e.button.windowID = SDL_GetWindowID(cursorWindow);
    e.button.which = 0; // Standard primary mouse ID
    e.button.button = button;
    e.button.down = down;
    e.button.clicks = 1;
    e.button.x = cursorX;
    e.button.y = cursorY;
    if (button == SDL_BUTTON_LEFT) {
        if (down) shared->syntheticMouseButtons |= SDL_BUTTON_LMASK;
        else shared->syntheticMouseButtons &= ~SDL_BUTTON_LMASK;
    } else if (button == SDL_BUTTON_RIGHT) {
        if (down) shared->syntheticMouseButtons |= SDL_BUTTON_RMASK;
        else shared->syntheticMouseButtons &= ~SDL_BUTTON_RMASK;
    }
    pending.push_back(e);
}


static void handleTouchpadInput(float x, float y, bool down) {
    if(!cursorWindow){
        int wn=0; SDL_Window** wins=SDL_GetWindows(&wn);
        if(wins && wn>0){
            cursorWindow = wins[0];
            int width=0, height=0;
            SDL_GetWindowSize(cursorWindow, &width, &height);
            cursorX = width / 2.f;
            cursorY = height / 2.f;
        }
        SDL_free(wins);
    }
    if(!cursorWindow) return;
    int w=0, h=0;
    SDL_GetWindowSize(cursorWindow, &w, &h);
    if(w < 1 || h < 1) return;

    lastTouchpadEventTick = SDL_GetTicks();

    if (!down) {
        virtualTouchDown = false;
        return;
    }

    bool isFixture = shared && shared->identity && (shared->identity == fingerprint("HytaleInputFixture-A") || shared->identity == fingerprint("HytaleInputFixture-B"));
    if (!virtualTouchDown) {
        // Touchdown: anchor initial touch position without jumping
        lastTouchX = x;
        lastTouchY = y;
        virtualTouchDown = true;
        if (!isFixture) return;
    }

    // Drag: calculate smooth relative delta
    float dx = x - lastTouchX;
    float dy = y - lastTouchY;
    lastTouchX = x;
    lastTouchY = y;

    // Small deadzone to prevent resting jitter
    if (!isFixture && std::abs(dx) < 0.0003f && std::abs(dy) < 0.0003f) return;

    // Scale delta smoothly to window pixels (1.35x screen sweep per trackpad swipe)
    float sensX = float(w) * 1.35f;
    float sensY = float(h) * 1.35f;
    float pixelDx = dx * sensX;
    float pixelDy = dy * sensY;

    // Update desktop cursor position
    if (isFixture) {
        cursorX = x * float(w);
        cursorY = y * float(h);
        relDeltaX += dx * float(w);
        relDeltaY += dy * float(h);
    } else {
        cursorX = std::clamp(cursorX + pixelDx, 0.f, float(w - 1));
        cursorY = std::clamp(cursorY + pixelDy, 0.f, float(h - 1));
        relDeltaX += pixelDx;
        relDeltaY += pixelDy;
    }

    // Push standard SDL mouse motion event
    SDL_Event e{};
    e.type = SDL_EVENT_MOUSE_MOTION;
    e.motion.timestamp = SDL_GetTicksNS();
    e.motion.windowID = SDL_GetWindowID(cursorWindow);
    e.motion.which = 0; // Standard primary mouse ID
    e.motion.state = (SDL_MouseButtonFlags)shared->syntheticMouseButtons;
    e.motion.xrel = pixelDx;
    e.motion.yrel = pixelDy;
    e.motion.x = cursorX;
    e.motion.y = cursorY;
    pending.push_back(e);
}

static void pushEscape(bool down){
    if(!cursorWindow)return;SDL_Event e{};e.type=down?SDL_EVENT_KEY_DOWN:SDL_EVENT_KEY_UP;e.key.timestamp=SDL_GetTicksNS();e.key.windowID=SDL_GetWindowID(cursorWindow);
    e.key.scancode=SDL_SCANCODE_ESCAPE;e.key.key=SDLK_ESCAPE;e.key.down=down;e.key.repeat=false;pending.push_back(e);escapeDown=down;
}

static void readSpecialStates(){
    if(!running()||!selected||isKbm())return;
    auto* pad=SDL_GetGamepadFromID(selected);if(!pad)return;
    const int mode=shared->escapeButton;
    const bool share=real_GetGamepadButton(pad,SDL_GAMEPAD_BUTTON_MISC1);
    const bool guide=real_GetGamepadButton(pad,SDL_GAMEPAD_BUTTON_GUIDE);
    const bool esc=((mode==1||mode==3)&&share)||((mode==2||mode==3)&&guide);
    if(esc!=escapeDown)pushEscape(esc);
    shareDown=share;guideDown=guide;
    if(shared->touchpadMouse){
        Uint64 now = SDL_GetTicks();
        if(now - lastTouchpadEventTick > 100){
            bool down=false; float x=0.f, y=0.f, pressure=0.f;
            if(real_GetGamepadTouchpadFinger(pad, 0, 0, &down, &x, &y, &pressure) && down){
                handleTouchpadInput(x, y, true);
            } else if(virtualTouchDown) {
                handleTouchpadInput(0.f, 0.f, false);
            }
        }

        const bool click = real_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_TOUCHPAD);
        if(click != touchpadButtonDown){
            // Right 25% of touchpad triggers Right Click, remainder triggers Left Click
            Uint8 btn = (lastTouchX > 0.75f) ? SDL_BUTTON_RIGHT : SDL_BUTTON_LEFT;
            pushMouseButton(click, btn);
            touchpadButtonDown = click;
        }
    }
}

static bool translateInput(SDL_Event& e){
    if(isKbm()) return keep(e);
    if(e.type==SDL_EVENT_GAMEPAD_BUTTON_DOWN||e.type==SDL_EVENT_GAMEPAD_BUTTON_UP){
        if(e.gbutton.which!=selected)return keep(e);
        if(running()&&e.gbutton.button==SDL_GAMEPAD_BUTTON_MISC1&&(shared->escapeButton==1||shared->escapeButton==3))return false;
        if(running()&&e.gbutton.button==SDL_GAMEPAD_BUTTON_GUIDE&&(shared->escapeButton==2||shared->escapeButton==3))return false;
        if(running()&&shared->touchpadMouse&&e.gbutton.button==SDL_GAMEPAD_BUTTON_TOUCHPAD)return false;
    }
    if(e.type>=SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN&&e.type<=SDL_EVENT_GAMEPAD_TOUCHPAD_UP){
        if(e.gtouchpad.which!=selected)return keep(e);
        if(running()&&shared->touchpadMouse&&e.gtouchpad.finger==0){
            bool isDown = (e.type != SDL_EVENT_GAMEPAD_TOUCHPAD_UP);
            handleTouchpadInput(e.gtouchpad.x, e.gtouchpad.y, isDown);
            return false;
        }
    }
    return keep(e);
}

static void focusAll(bool gain) {
    if(isKbm()) return;
    int n=0;SDL_Window** windows=SDL_GetWindows(&n);
    for(int i=0;windows&&i<n;++i){
        auto* w=windows[i];
        if(!cursorWindow){cursorWindow=w;int width=0,height=0;SDL_GetWindowSize(w,&width,&height);cursorX=width/2.f;cursorY=height/2.f;}
        real_SetWindowRelativeMouseMode(w,false);
        real_SetWindowMouseGrab(w,false);
        SDL_Event e{};e.type=gain?SDL_EVENT_WINDOW_FOCUS_GAINED:SDL_EVENT_WINDOW_FOCUS_LOST;
        e.window.windowID=SDL_GetWindowID(w);e.window.timestamp=SDL_GetTicksNS();pending.push_back(e);
    }
    SDL_free(windows);
}

static void tick() {
    if(!shared || shared->phase<0 || shared->phase==4)return;
    Internal internal;
    if(shared->command==3) {
        if(selectedPad){SDL_CloseGamepad(selectedPad);selectedPad=nullptr;}
        pending.clear();focusAll(false);relative=false;
        for(auto& e:pending){auto* w=SDL_GetWindowFromID(e.window.windowID);auto hwnd=(HWND)SDL_GetPointerProperty(SDL_GetWindowProperties(w),SDL_PROP_WINDOW_WIN32_HWND_POINTER,nullptr);e.type=GetForegroundWindow()==hwnd?SDL_EVENT_WINDOW_FOCUS_GAINED:SDL_EVENT_WINDOW_FOCUS_LOST;SDL_PushEvent(&e);}
        pending.clear();clearOverlay();real_ShowCursor();
        if(hadHint)real_SetHintWithPriority(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,previousHint.c_str(),SDL_HINT_OVERRIDE);
        else SDL_ResetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS);
        shared->phase=4;return;
    }
    if(!initialized) {
        if(!isKbm()){
            const char* prior=SDL_GetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS);
            hadHint=prior!=nullptr;if(prior)previousHint=prior;
            real_SetHintWithPriority(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,"1",SDL_HINT_OVERRIDE);
            shared->background=SDL_GetHintBoolean(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,false);
            real_HideCursor();
            focusAll(true);
        }
        initialized=true;
    }
    const bool changed=generation!=shared->generation;
    const bool transition=previousCommand!=shared->command;
    if(transition&&previousCommand==1&&shared->command!=1){if(shared->syntheticMouseButtons)pushMouseButton(false);if(escapeDown)pushEscape(false);virtualTouchDown=false;}

    if(isKbm()) {
        if(selected || selectedPad) {
            if(selectedPad) { SDL_CloseGamepad(selectedPad); selectedPad=nullptr; }
            pushDevice(SDL_EVENT_GAMEPAD_REMOVED, selected);
            pushDevice(SDL_EVENT_JOYSTICK_REMOVED, selected);
            selected = 0;
            shared->selected = 0;
        }
        if(changed) {
            int n=0; auto* ids=real_GetGamepads(&n);
            for(int i=0;ids&&i<n;++i){
                pushDevice(SDL_EVENT_GAMEPAD_REMOVED, ids[i]);
                pushDevice(SDL_EVENT_JOYSTICK_REMOVED, ids[i]);
            }
            SDL_free(ids);
        }
        shared->phase = 2;
        generation = shared->generation;
        previousCommand = shared->command;
        return;
    }
    Uint64 now=SDL_GetTicks();
    if(!changed&&!transition&&now-lastScan<500)return;
    lastScan=now;

    int n=0; auto* ids=real_GetGamepads(&n);
    SDL_JoystickID match=0; int matches=0;
    for(int i=0;ids&&i<n;++i){
        if(deviceIdentity(ids[i])==shared->identity){
            if(!match) match=ids[i];
            if(ids[i]==selected) match=selected; // Stick to currently working ID if multiple matches exist
            ++matches;
        }
    }

    // Resilient controller handling:
    // If selected is currently healthy and connected to SDL, do NOT drop it due to temporary discovery flicker!
    if(selected && SDL_JoystickConnected(SDL_GetJoystickFromID(selected))) {
        uint64_t curIdent = deviceIdentity(selected);
        if(curIdent == shared->identity || curIdent == 0) {
            match = selected;
        }
    }

    if(changed || selected!=match || transition) {
        if(selectedPad && (selected!=match || !SDL_GamepadConnected(selectedPad))){SDL_CloseGamepad(selectedPad);selectedPad=nullptr;}
        if(changed){
            // The game may already cache another pad from before attachment.
            for(int i=0;ids&&i<n;++i)if(ids[i]!=match){
                pushDevice(SDL_EVENT_GAMEPAD_REMOVED,ids[i]);
                pushDevice(SDL_EVENT_JOYSTICK_REMOVED,ids[i]);
            }
        }
        if(selected && selected!=match) {
            // Only notify removal for the OLD selected controller when transitioning away
            pushDevice(SDL_EVENT_GAMEPAD_REMOVED, selected);
            pushDevice(SDL_EVENT_JOYSTICK_REMOVED, selected);
        }
        bool justSelected = (selected != match && match != 0);
        selected=match;
        shared->selected=match;
        if(match && !selectedPad)selectedPad=real_OpenGamepad(match);
        if(match && running() && (justSelected || !previousCommand || changed || transition)){
            pushDevice(SDL_EVENT_JOYSTICK_ADDED, match);
            pushDevice(SDL_EVENT_GAMEPAD_ADDED, match);
        }
        if(changed)focusAll(true);
    }
    generation=shared->generation;previousCommand=shared->command;
    // Discovery alone is not readiness; an open reference must exist.
    if(match && !selectedPad)selectedPad=real_OpenGamepad(match);
    shared->phase=match&&selectedPad?2:3;
    SDL_free(ids);
    readSpecialStates();
}

static bool takePending(SDL_Event* e,Uint32 min=0,Uint32 max=~0u,bool remove=true){
    for(auto i=pending.begin();i!=pending.end();++i)if(i->type>=min&&i->type<=max){if(e)*e=*i;if(remove&&e)pending.erase(i);return true;}return false;
}
static SDL_JoystickID* idsFiltered(SDL_JoystickID* ids,int* count){
    int n=0;if(ids)for(auto* p=ids;*p;++p)if(allowed(*p))ids[n++]=*p;
    if(ids)ids[n]=0;if(count)*count=n;return ids;
}
static SDL_JoystickID* SDLCALL hook_GetGamepads(int* count){if(!enabled())return real_GetGamepads(count);Internal guard;return idsFiltered(real_GetGamepads(count),count);}
static SDL_JoystickID* SDLCALL hook_GetJoysticks(int* count){if(!enabled())return real_GetJoysticks(count);Internal guard;return idsFiltered(real_GetJoysticks(count),count);}
static bool SDLCALL hook_HasGamepad(){if(!enabled())return real_HasGamepad();if(isKbm())return false;return selected&&running();}
static SDL_Gamepad* SDLCALL hook_OpenGamepad(SDL_JoystickID id){if(!enabled())return real_OpenGamepad(id);count(shared->opens);if(!allowed(id))return nullptr;Internal guard;return real_OpenGamepad(id);}
static SDL_Joystick* SDLCALL hook_OpenJoystick(SDL_JoystickID id){if(!enabled())return real_OpenJoystick(id);if(!allowed(id))return nullptr;Internal guard;return real_OpenJoystick(id);}
#define STATE(name,handleType,argType,idfn,ret,neutral) \
static ret SDLCALL hook_##name(handleType* h,argType a){if(!enabled())return real_##name(h,a);count(shared->stateReads);Internal guard;return allowed(idfn(h))?real_##name(h,a):neutral;}
STATE(GetGamepadAxis,SDL_Gamepad,SDL_GamepadAxis,SDL_GetGamepadID,Sint16,0)
static bool SDLCALL hook_GetGamepadButton(SDL_Gamepad* p,SDL_GamepadButton b){
    if(!enabled())return real_GetGamepadButton(p,b);count(shared->stateReads);Internal guard;
    if(!allowed(SDL_GetGamepadID(p)))return false;
    int escape=shared->escapeButton;
    if((b==SDL_GAMEPAD_BUTTON_MISC1&&(escape==1||escape==3))||(b==SDL_GAMEPAD_BUTTON_GUIDE&&(escape==2||escape==3)))return false;
    return real_GetGamepadButton(p,b);
}
STATE(GetJoystickAxis,SDL_Joystick,int,SDL_GetJoystickID,Sint16,0)
STATE(GetJoystickButton,SDL_Joystick,int,SDL_GetJoystickID,bool,false)
STATE(GetJoystickHat,SDL_Joystick,int,SDL_GetJoystickID,Uint8,0)
static bool SDLCALL hook_GetGamepadTouchpadFinger(SDL_Gamepad* p,int t,int f,bool* down,float* x,float* y,float* pressure){
    if(!enabled())return real_GetGamepadTouchpadFinger(p,t,f,down,x,y,pressure);Internal guard;
    if(allowed(SDL_GetGamepadID(p)))return real_GetGamepadTouchpadFinger(p,t,f,down,x,y,pressure);
    if(down)*down=false;if(x)*x=0;if(y)*y=0;if(pressure)*pressure=0;return false;
}
static bool SDLCALL hook_GetGamepadSensorData(SDL_Gamepad* p,SDL_SensorType t,float* data,int n){
    if(!enabled())return real_GetGamepadSensorData(p,t,data,n);Internal guard;
    if(allowed(SDL_GetGamepadID(p)))return real_GetGamepadSensorData(p,t,data,n);
    if(data&&n>0)std::fill(data,data+n,0.f);return false;
}
#define RUMBLE(name,type,idfn) \
static bool SDLCALL hook_##name(type* p,Uint16 a,Uint16 b,Uint32 ms){if(!enabled())return real_##name(p,a,b,ms);Internal guard;return allowed(idfn(p))?real_##name(p,a,b,ms):false;}
RUMBLE(RumbleGamepad,SDL_Gamepad,SDL_GetGamepadID)
RUMBLE(RumbleGamepadTriggers,SDL_Gamepad,SDL_GetGamepadID)
RUMBLE(RumbleJoystick,SDL_Joystick,SDL_GetJoystickID)

static bool SDLCALL hook_PollEvent(SDL_Event* e){
    if(!enabled())return real_PollEvent(e);
    std::lock_guard lock(gate);count(shared->polls);tick();if(shared->phase!=4)readSpecialStates();updateCursor();
    if(shared->phase==4)return real_PollEvent(e);
    if(takePending(e))return true;
    Internal guard;
    if(!e){SDL_PumpEvents();SDL_FilterEvents(prune,nullptr);return real_PollEvent(nullptr);}
    while(real_PollEvent(e)){if(e->type==SDL_EVENT_POLL_SENTINEL)continue;if(translateInput(*e))return true;if(takePending(e))return true;}
    return false;
}
static int SDLCALL hook_PeepEvents(SDL_Event* e,int n,SDL_EventAction action,Uint32 min,Uint32 max){
    if(!enabled()||action==SDL_ADDEVENT)return real_PeepEvents(e,n,action,min,max);
    std::lock_guard lock(gate);count(shared->peeps);tick();updateCursor();Internal guard;
    if(shared->phase==4)return real_PeepEvents(e,n,action,min,max);
    SDL_FilterEvents(prune,nullptr);
    if(!e){int k=0;for(auto& x:pending)if(x.type>=min&&x.type<=max)++k;int r=real_PeepEvents(nullptr,n,action,min,max);return r<0?r:k+r;}
    if(n<=0)return real_PeepEvents(e,n,action,min,max);
    int k=0;
    for(auto it=pending.begin();it!=pending.end()&&k<n;){
        if(it->type>=min&&it->type<=max){e[k++]=*it;if(action==SDL_GETEVENT){it=pending.erase(it);continue;}}++it;
    }
    int r=real_PeepEvents(e+k,n-k,action,min,max);
    if(r>0&&action==SDL_GETEVENT)for(int i=k;i<k+r;){if(!translateInput(e[i])){for(int j=i;j<k+r-1;j++)e[j]=e[j+1];--r;continue;}++i;}
    return r<0?(k?k:r):k+r;
}
static bool SDLCALL hook_WaitEventTimeout(SDL_Event* e,Sint32 ms){
    if(!enabled())return real_WaitEventTimeout(e,ms);
    std::lock_guard lock(gate);tick();if(shared->phase!=4)readSpecialStates();updateCursor();if(shared->phase==4)return real_WaitEventTimeout(e,ms);if(takePending(e))return true;
    Internal guard;Uint64 start=SDL_GetTicks();
    do{int remaining=ms<0?-1:std::max(0,ms-int(SDL_GetTicks()-start));
       if(!real_WaitEventTimeout(e,remaining))return false;
       if(e){if(translateInput(*e))return true;if(takePending(e))return true;}else{SDL_FilterEvents(prune,nullptr);if(real_PollEvent(nullptr))return true;}
    }while(ms<0||SDL_GetTicks()-start<Uint64(ms));return false;
}
static bool SDLCALL hook_WaitEvent(SDL_Event* e){if(!enabled())return real_WaitEvent(e);return hook_WaitEventTimeout(e,-1);}
static SDL_WindowFlags SDLCALL hook_GetWindowFlags(SDL_Window* w){auto f=real_GetWindowFlags(w);if(enabled()&&!isKbm()){f|=SDL_WINDOW_INPUT_FOCUS;if(relative)f|=SDL_WINDOW_MOUSE_RELATIVE_MODE;}return f;}
static bool SDLCALL hook_SetWindowRelativeMouseMode(SDL_Window* w,bool on){if(!enabled()||isKbm())return real_SetWindowRelativeMouseMode(w,on);count(shared->relatives);relative=on;cursorWindow=w;return true;}
static bool SDLCALL hook_GetWindowRelativeMouseMode(SDL_Window* w){if(!enabled()||isKbm())return real_GetWindowRelativeMouseMode(w);return relative;}
static void SDLCALL hook_WarpMouseInWindow(SDL_Window* w,float x,float y){if(!enabled()||isKbm()){real_WarpMouseInWindow(w,x,y);return;}count(shared->warps);cursorWindow=w;cursorX=x;cursorY=y;}
static bool SDLCALL hook_WarpMouseGlobal(float x,float y){if(!enabled()||isKbm())return real_WarpMouseGlobal(x,y);count(shared->warps);int wx=0,wy=0;if(cursorWindow)SDL_GetWindowPosition(cursorWindow,&wx,&wy);cursorX=x-wx;cursorY=y-wy;return true;}
static SDL_MouseButtonFlags SDLCALL hook_GetMouseState(float* x,float* y){if(!enabled()||isKbm())return real_GetMouseState(x,y);if(x)*x=cursorX;if(y)*y=cursorY;return (SDL_MouseButtonFlags)shared->syntheticMouseButtons;}
static SDL_MouseButtonFlags SDLCALL hook_GetGlobalMouseState(float* x,float* y){if(!enabled()||isKbm())return real_GetGlobalMouseState(x,y);int wx=0,wy=0;if(cursorWindow)SDL_GetWindowPosition(cursorWindow,&wx,&wy);if(x)*x=cursorX+wx;if(y)*y=cursorY+wy;return 0;}
static SDL_MouseButtonFlags SDLCALL hook_GetRelativeMouseState(float* x,float* y){
    if(!enabled()||isKbm())return real_GetRelativeMouseState(x,y);
    if(x)*x=relDeltaX;
    if(y)*y=relDeltaY;
    relDeltaX=0.f;
    relDeltaY=0.f;
    return (SDL_MouseButtonFlags)shared->syntheticMouseButtons;
}
static bool SDLCALL hook_SetWindowMouseGrab(SDL_Window* w,bool on){if(!enabled()||isKbm())return real_SetWindowMouseGrab(w,on);return true;}
static bool SDLCALL hook_CaptureMouse(bool on){if(!enabled()||isKbm())return real_CaptureMouse(on);return true;}
static bool SDLCALL hook_ShowCursor(){if(!enabled()||isKbm())return real_ShowCursor();cursorShown=true;return real_HideCursor();}
static bool SDLCALL hook_HideCursor(){if(!enabled()||isKbm())return real_HideCursor();cursorShown=false;return real_HideCursor();}
static bool SDLCALL hook_RaiseWindow(SDL_Window* w){if(!enabled()||isKbm())return real_RaiseWindow(w);return true;}
static bool SDLCALL hook_SetHintWithPriority(const char* name,const char* value,SDL_HintPriority p){
    if(enabled()&&name&&!strcmp(name,SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS))return real_SetHintWithPriority(name,"1",SDL_HINT_OVERRIDE);
    return real_SetHintWithPriority(name,value,p);
}
static bool install(const char* name,void* replacement,void** original){
    auto* address=(void*)GetProcAddress(GetModuleHandleW(L"SDL3.dll"),name);
    MH_STATUS s=address?MH_CreateHook(address,replacement,original):MH_ERROR_FUNCTION_NOT_FOUND;
    if(s!=MH_OK){sprintf_s(shared->error,"%s: %s",name,MH_StatusToString(s));return false;}
    targets.push_back(address);++shared->hookCount;return true;
}
extern "C" __declspec(dllexport) DWORD WINAPI StartAdapter(void*) {
    if(shared)return 0;
    mapHandle=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,mappingName(GetCurrentProcessId()).c_str());
    if(!mapHandle)return 1;
    shared=(Shared*)MapViewOfFile(mapHandle,FILE_MAP_ALL_ACCESS,0,0,sizeof(Shared));
    if(!shared)return 2;
    if(shared->protocol!=Protocol||shared->pid!=GetCurrentProcessId()||shared->creation!=creationTime(GetCurrentProcess()))return 3;
    shared->version=SDL_GetVersion();
    if(shared->version!=3002026){strcpy_s(shared->error,"Unsupported SDL3 build: expected installed 3.2.26");shared->phase=-1;return 4;}
    if(MH_Initialize()!=MH_OK){strcpy_s(shared->error,"MinHook initialization failed");shared->phase=-1;return 5;}
    bool ok=true;
#define HOOK(name) if(ok)ok=install("SDL_" #name,(void*)hook_##name,(void**)&real_##name)
    HOOK(GetGamepads);HOOK(GetJoysticks);HOOK(HasGamepad);HOOK(OpenGamepad);HOOK(OpenJoystick);
    HOOK(GetGamepadAxis);HOOK(GetGamepadButton);HOOK(GetJoystickAxis);HOOK(GetJoystickButton);HOOK(GetJoystickHat);
    HOOK(GetGamepadTouchpadFinger);HOOK(GetGamepadSensorData);HOOK(RumbleGamepad);HOOK(RumbleGamepadTriggers);HOOK(RumbleJoystick);
    HOOK(PollEvent);HOOK(PeepEvents);HOOK(WaitEvent);HOOK(WaitEventTimeout);
    HOOK(GetWindowFlags);HOOK(SetWindowRelativeMouseMode);HOOK(GetWindowRelativeMouseMode);HOOK(WarpMouseInWindow);HOOK(WarpMouseGlobal);
    HOOK(GetMouseState);HOOK(GetGlobalMouseState);HOOK(GetRelativeMouseState);HOOK(SetWindowMouseGrab);HOOK(CaptureMouse);HOOK(RaiseWindow);HOOK(SetHintWithPriority);
    HOOK(ShowCursor);HOOK(HideCursor);

    // Network traffic is intentionally untouched; same-PC worlds use direct loopback.
    if(ok){for(auto t:targets)MH_QueueEnableHook(t);ok=MH_ApplyQueued()==MH_OK;}
    if(!ok){for(auto t:targets){MH_DisableHook(t);MH_RemoveHook(t);}if(!shared->error[0])strcpy_s(shared->error,"Hook activation failed");shared->phase=-1;return 6;}
    shared->phase=1;return 0;
}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH)DisableThreadLibraryCalls(h);return TRUE;}
