using System;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Automation;
// Runs in a separate worker process so an unresponsive accessibility provider cannot freeze Studio.
public static class LauncherAutomation {
 [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] static extern bool IsChild(IntPtr parent,IntPtr child);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent,EnumWindowsProc proc,IntPtr lParam);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int cx,int cy,uint flags);
 [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int cmd);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] struct POINT {public int X,Y;}
 [StructLayout(LayoutKind.Sequential)] struct RECT {public int Left,Top,Right,Bottom;}
 delegate bool EnumWindowsProc(IntPtr h,IntPtr l);

 static void BringToFront(IntPtr hwnd){
  if(hwnd==IntPtr.Zero)return;
  if(IsIconic(hwnd))ShowWindow(hwnd,9);
  SetWindowPos(hwnd,new IntPtr(-1),0,0,0,0,0x0043);
  SetWindowPos(hwnd,new IntPtr(-2),0,0,0,0,0x0043);
  BringWindowToTop(hwnd);
  SetForegroundWindow(hwnd);
 }

 static IntPtr FindTargetWindow(IntPtr window,POINT p){
  var target=WindowFromPoint(p);
  if(target==window || IsChild(window,target))return target;
  IntPtr best=window;
  EnumChildWindows(window,(h,l)=>{
   RECT r;
   if(IsWindowVisible(h) && GetWindowRect(h,out r)){
    if(p.X>=r.Left && p.X<r.Right && p.Y>=r.Top && p.Y<r.Bottom){
     best=h;
    }
   }
   return true;
  },IntPtr.Zero);
  return best;
 }

 static AutomationElement[] Named(AutomationElement root,string name) {
  return root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.NameProperty,name))
   .Cast<AutomationElement>().Where(e=>!e.Current.IsOffscreen && e.Current.ControlType==ControlType.Text)
   .OrderBy(e=>e.Current.BoundingRectangle.Top).ToArray();
 }
 static void Activate(AutomationElement e,IntPtr window) {
  object pattern;
  if(e.TryGetCurrentPattern(InvokePattern.Pattern,out pattern)){((InvokePattern)pattern).Invoke();return;}
  var r=e.Current.BoundingRectangle;
  if(r.IsEmpty || r.Width<1 || r.Height<1)throw new Exception("Launcher control is not visible. Bring the launcher into view or select the account manually.");
  var p=new POINT{X=(int)(r.Left+r.Width/2),Y=(int)(r.Top+r.Height/2)};
  var target=FindTargetWindow(window,p);
  if(!ScreenToClient(target,ref p))throw new Exception("Cannot locate launcher control.");
  var xy=new IntPtr((p.Y<<16)|(p.X&65535));
  if(!PostMessage(target,0x201,new IntPtr(1),xy)||!PostMessage(target,0x202,IntPtr.Zero,xy))throw new Exception("Launcher input failed.");
 }
 public static string Step(int pid,string targetName,string branch,string[] knownNames,bool allowPlay){
  var process=Process.GetProcessById(pid);
  if(process.ProcessName!="hytale-launcher")throw new Exception("Unexpected launcher process.");
  var hwnd=process.MainWindowHandle;if(hwnd==IntPtr.Zero)return "WAIT";
  BringToFront(hwnd);
  var root=AutomationElement.FromHandle(hwnd);
  var accounts=knownNames.SelectMany(n=>Named(root,n)).OrderBy(e=>e.Current.BoundingRectangle.Top).ToArray();
  if(accounts.Length==0)return "WAIT";
  var current=accounts[0];
  if(current.Current.Name!=targetName){
   var options=Named(root,targetName);
   Activate(options.Length>0 ? options[options.Length-1] : current,hwnd);
   System.Threading.Thread.Sleep(60);
   options=Named(root,targetName);
   if(options.Length>0){Activate(options[options.Length-1],hwnd);System.Threading.Thread.Sleep(50);}
   accounts=knownNames.SelectMany(n=>Named(root,n)).OrderBy(e=>e.Current.BoundingRectangle.Top).ToArray();
   if(accounts.Length>0)current=accounts[0];
   if(current.Current.Name!=targetName)return "SELECTING";
  }
  // An open account menu duplicates the current name. Close it before Play.
  if(Named(root,targetName).Length>1){Activate(current,hwnd);System.Threading.Thread.Sleep(40);}
  var text=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text)).Cast<AutomationElement>()
   .Select(e=>e.Current.Name).FirstOrDefault(n=>n.StartsWith("Version:",StringComparison.OrdinalIgnoreCase));
  if(text==null)return "WAIT";
  bool prerelease=text.IndexOf("pre",StringComparison.OrdinalIgnoreCase)>=0;
  if(prerelease!=(branch=="pre-release"))throw new Exception("Select the saved profile's game branch in launcher Settings before continuing.");
  if(!allowPlay)return "ACCOUNT_READY";
  var play=root.FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button),new PropertyCondition(AutomationElement.NameProperty,"PLAY")));
  if(play==null || !play.Current.IsEnabled)return "WAIT";
  Activate(play,hwnd);return "PLAY_REQUESTED";
 }
}
