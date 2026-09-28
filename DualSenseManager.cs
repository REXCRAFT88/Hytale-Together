using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

// All calls belong to the panel's UI thread, which owns SDL's event pump.
public static class DualSenseManager {
    const string Library = "SDL3.dll";
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] static extern bool SDL_Init(uint flags);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] static extern bool SDL_SetHint(string name, string value);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern void SDL_PumpEvents();
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern void SDL_FlushEvents(uint first, uint last);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr SDL_GetGamepads(out int count);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern void SDL_free(IntPtr memory);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr SDL_OpenGamepad(uint id);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern void SDL_CloseGamepad(IntPtr pad);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr SDL_GetJoystickPathForID(uint id);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr SDL_GetGamepadPathForID(uint id);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr SDL_GetGamepadName(IntPtr pad);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern ushort SDL_GetGamepadVendor(IntPtr pad);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr SDL_GetError();
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern void SDL_Quit();
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] static extern bool SDL_GamepadConnected(IntPtr pad);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] static extern bool SDL_SetGamepadLED(IntPtr pad, byte r, byte g, byte b);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] static extern bool SDL_RumbleGamepad(IntPtr pad, ushort low, ushort high, uint ms);

    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern uint SDL_GetGamepadProperties(IntPtr pad);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool SDL_GetBooleanProperty(uint props,string name,[MarshalAs(UnmanagedType.I1)] bool fallback);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] static extern int SDL_GetNumGamepadTouchpads(IntPtr pad);
    public sealed class Device {
        public bool HasLed { get; internal set; }
        public bool HasRumble { get; internal set; }
        public bool HasTouchpad { get; internal set; }

        public string Id { get; internal set; }
        public string Name { get; internal set; }
        public uint InstanceId { get; internal set; }
        internal IntPtr Handle;
    }
    static readonly Dictionary<string,Device> pads = new Dictionary<string,Device>(StringComparer.OrdinalIgnoreCase);
    static readonly Dictionary<string,byte[]> colors = new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
    static bool initialized;
    public static string LastError { get; private set; }
    public static int OpenHandleCount { get { return pads.Count; } }
    public static int OpenCount { get; private set; }
    public static int CloseCount { get; private set; }

    static string Utf8(IntPtr value) {
        if(value == IntPtr.Zero) return "";
        int length=0; while(Marshal.ReadByte(value,length)!=0) ++length;
        byte[] bytes=new byte[length]; Marshal.Copy(value,bytes,0,length);
        return Encoding.UTF8.GetString(bytes);
    }
    public static string ComputeId(string path) {
        if(String.IsNullOrEmpty(path)) return "";
        ulong hash=14695981039346656037UL;
        // Match native common.h: lowercase ASCII bytes, not Unicode characters.
        foreach(byte original in Encoding.UTF8.GetBytes(path)) {
            byte b=original; if(b>=65 && b<=90) b+=32;
            hash=unchecked((hash ^ b)*1099511628211UL);
        }
        return hash.ToString("x16");
    }
    public static void Initialize() {
        if(initialized) return;
        SDL_SetHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS","1");
        SDL_SetHint("SDL_JOYSTICK_ENHANCED_REPORTS","1");
        if(!SDL_Init(0x2000)) throw new InvalidOperationException("Controller initialization: "+Utf8(SDL_GetError()));
        initialized=true;
    }
    public static void Pump() {
        Initialize(); SDL_PumpEvents(); SDL_FlushEvents(0,0xffff);
    }
    public static void OpenAll() {
        Pump();
        int count; IntPtr list=SDL_GetGamepads(out count);
        if(list==IntPtr.Zero) throw new InvalidOperationException("Controller discovery: "+Utf8(SDL_GetError()));
        var present=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try {
            for(int i=0;i<count;++i) {
                uint instance=unchecked((uint)Marshal.ReadInt32(list,i*4));
                string path=Utf8(SDL_GetJoystickPathForID(instance));
                if(path.Length==0) path=Utf8(SDL_GetGamepadPathForID(instance));
                string id=ComputeId(path); if(id.Length==0) continue;
                present.Add(id); Device old;
                if(pads.TryGetValue(id,out old)) {
                    if(old.InstanceId==instance && SDL_GamepadConnected(old.Handle)) continue;
                    SDL_CloseGamepad(old.Handle); ++CloseCount; pads.Remove(id);
                }
                IntPtr handle=SDL_OpenGamepad(instance); if(handle==IntPtr.Zero) continue;
                ++OpenCount;
                uint props=SDL_GetGamepadProperties(handle);
                pads[id]=new Device { Id=id, Name=Utf8(SDL_GetGamepadName(handle)), InstanceId=instance, Handle=handle,
                    HasLed=SDL_GetBooleanProperty(props,"SDL.joystick.cap.rgb_led",false),
                    HasRumble=SDL_GetBooleanProperty(props,"SDL.joystick.cap.rumble",false),
                    HasTouchpad=SDL_GetNumGamepadTouchpads(handle)>0 };
                byte[] rgb;
                if(colors.TryGetValue(id,out rgb)) SDL_SetGamepadLED(handle,rgb[0],rgb[1],rgb[2]);
            }
            foreach(string id in new List<string>(pads.Keys)) {
                if(!present.Contains(id) || !SDL_GamepadConnected(pads[id].Handle)) {
                    SDL_CloseGamepad(pads[id].Handle); ++CloseCount; pads.Remove(id);
                }
            }
        } finally { SDL_free(list); }
    }
    public static Device[] GetDevices() {
        OpenAll(); var result=new List<Device>(pads.Values);
        result.Sort((a,b)=>StringComparer.Ordinal.Compare(a.Id,b.Id)); return result.ToArray();
    }
    static Device Find(string id) {
        LastError=""; OpenAll(); Device pad;
        if(!String.IsNullOrEmpty(id) && pads.TryGetValue(id,out pad)) return pad;
        LastError="Assigned controller is disconnected. Reconnect it using the same USB/Bluetooth connection."; return null;
    }
    public static bool VibrateById(string id, ushort strength, uint ms) {
        Device pad=Find(id); if(pad==null) return false;
        if(!pad.HasRumble){LastError="This controller does not report vibration support.";return false;}
        if(SDL_RumbleGamepad(pad.Handle,strength,strength,ms)) return true;
        LastError=Utf8(SDL_GetError()); return false;
    }
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)] static extern bool SDL_GetGamepadButton(IntPtr pad, int button);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)]
    static extern short SDL_GetGamepadAxis(IntPtr pad, int axis);
    public static string[] CrossDown() {
        Pump(); var down=new List<string>();
        foreach(Device pad in pads.Values) if(SDL_GamepadConnected(pad.Handle) && SDL_GetGamepadButton(pad.Handle,0)) down.Add(pad.Id);
        return down.ToArray();
    }
    public static string[] AnyInputDown() {
        Pump(); var down=new List<string>();
        foreach(Device pad in pads.Values) {
            if(!SDL_GamepadConnected(pad.Handle)) continue;
            bool active = false;
            for(int b = 0; b <= 20; ++b) {
                if(SDL_GetGamepadButton(pad.Handle, b)) { active = true; break; }
            }
            if(!active) {
                for(int a = 0; a < 6; ++a) {
                    short val = SDL_GetGamepadAxis(pad.Handle, a);
                    if(val > 16000 || val < -16000) { active = true; break; }
                }
            }
            if(active) down.Add(pad.Id);
        }
        return down.ToArray();
    }
    public static bool SetLedById(string id, byte r, byte g, byte b) {
        if(!String.IsNullOrEmpty(id)) colors[id]=new byte[]{r,g,b};
        Device pad=Find(id); if(pad==null) return false;
        if(!pad.HasLed){LastError="This controller does not report RGB lightbar support.";return false;}
        if(SDL_SetGamepadLED(pad.Handle,r,g,b)) return true;
        LastError=Utf8(SDL_GetError()); return false;
    }
    public static void CloseAll() {
        foreach(Device pad in pads.Values) { SDL_CloseGamepad(pad.Handle); ++CloseCount; }
        pads.Clear();
    }
    public static void Shutdown() {
        if(!initialized) return;
        CloseAll(); colors.Clear(); SDL_Quit(); initialized=false;
    }
}
