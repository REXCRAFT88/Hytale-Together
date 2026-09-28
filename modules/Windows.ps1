Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class HytaleSplitWindow {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
 [StructLayout(LayoutKind.Sequential)] public struct PLACEMENT { public int Length,Flags,Show; public POINT Min,Max; public RECT Normal; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h,ref PLACEMENT p);
 [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr h,ref PLACEMENT p);
 [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetStyle(IntPtr h,int n);
 [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] public static extern IntPtr SetStyle(IntPtr h,int n,IntPtr value);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int command);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
'@

if(-not ('HytaleAssignmentProcess' -as [type])){
Add-Type @'
using System;
using System.Diagnostics;
using System.Text;
public sealed class HytaleAssignmentProcess : IDisposable {
 private readonly Process process;
 private readonly StringBuilder output = new StringBuilder(), error = new StringBuilder();
 private readonly object gate = new object();
 private bool outputDone, errorDone;
 public HytaleAssignmentProcess(string executable, string arguments) {
  var start = new ProcessStartInfo(executable, arguments) { UseShellExecute=false, CreateNoWindow=true, RedirectStandardOutput=true, RedirectStandardError=true };
  process = new Process(); process.StartInfo=start;
  process.OutputDataReceived += (sender,e) => { lock(gate) { if(e.Data==null) outputDone=true; else output.AppendLine(e.Data); } };
  process.ErrorDataReceived += (sender,e) => { lock(gate) { if(e.Data==null) errorDone=true; else error.AppendLine(e.Data); } };
  if(!process.Start()) throw new InvalidOperationException("Could not start process.");
  process.BeginOutputReadLine(); process.BeginErrorReadLine();
 }
 public bool IsCompleted { get { lock(gate) return process.HasExited && outputDone && errorDone; } }
 public int ExitCode { get { return process.ExitCode; } }
 public string Output { get { lock(gate) return output.ToString(); } }
 public string Error { get { lock(gate) return error.ToString(); } }
 public void Cancel() { if(!process.HasExited) process.Kill(); }
 public void Dispose() { process.Dispose(); }
}
'@
}

function Restore-Windows {
    if(!(Test-Path -LiteralPath $stateFile)){return}
    $saved=Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
    foreach($item in $saved){
        $p=Get-Process -Id $item.Pid -ErrorAction SilentlyContinue
        if(!$p -or $p.ProcessName -ne 'HytaleClient' -or $p.StartTime.ToUniversalTime().Ticks.ToString() -ne $item.StartTicks){continue}
        $h=[IntPtr][long]$item.Hwnd
        if($p.MainWindowHandle -ne $h -or ![HytaleSplitWindow]::IsWindow($h)){continue}
        [void][HytaleSplitWindow]::SetStyle($h,-16,[IntPtr][long]$item.Style)
        $pl=New-Object HytaleSplitWindow+PLACEMENT
        $pl.Length=[Runtime.InteropServices.Marshal]::SizeOf($pl);$pl.Flags=$item.Flags;$pl.Show=$item.Show
        $pl.Normal.Left=$item.Left;$pl.Normal.Top=$item.Top;$pl.Normal.Right=$item.Right;$pl.Normal.Bottom=$item.Bottom
        [void][HytaleSplitWindow]::SetWindowPlacement($h,[ref]$pl)
        $restoreOrder=if($item.WasTopMost){[IntPtr](-1)}else{[IntPtr](-2)}
        # Do not use SWP_NOZORDER: it would ignore the requested topmost reset.
        [void][HytaleSplitWindow]::SetWindowPos($h,$restoreOrder,0,0,0,0,0x33)
    }
}

function Set-SplitLayout {
    param([int]$TargetMonitorIndex = $script:MonitorIndex)
    $clients=@(Get-SessionClients)
    if($clients.Count -lt 1 -or $clients.Count -gt 4){throw 'Attach 1 to 4 account clients before arranging windows.'}
    Restore-Windows
    $saved=@()
    foreach($p in $clients){
        if(!$p.MainWindowHandle){throw 'A Hytale main window is not ready yet.'}
        $pl=New-Object HytaleSplitWindow+PLACEMENT;$pl.Length=[Runtime.InteropServices.Marshal]::SizeOf($pl)
        if(![HytaleSplitWindow]::GetWindowPlacement($p.MainWindowHandle,[ref]$pl)){throw 'Cannot record window placement.'}
        $saved+=[pscustomobject]@{Pid=$p.Id;StartTicks=$p.StartTime.ToUniversalTime().Ticks.ToString();Hwnd=$p.MainWindowHandle.ToInt64();Style=[HytaleSplitWindow]::GetStyle($p.MainWindowHandle,-16).ToInt64();WasTopMost=([HytaleSplitWindow]::GetStyle($p.MainWindowHandle,-20).ToInt64() -band 8) -ne 0;Flags=$pl.Flags;Show=$pl.Show;Left=$pl.Normal.Left;Top=$pl.Normal.Top;Right=$pl.Normal.Right;Bottom=$pl.Normal.Bottom}
    }
    $saved | ConvertTo-Json | Set-Content -LiteralPath ($stateFile+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($stateFile+'.tmp') -Destination $stateFile -Force

    $allScreens = [System.Windows.Forms.Screen]::AllScreens
    $screen = if ($TargetMonitorIndex -ge 0 -and $TargetMonitorIndex -lt $allScreens.Count) {
        $allScreens[$TargetMonitorIndex]
    } else {
        [System.Windows.Forms.Screen]::PrimaryScreen
    }
    $isFull = $WindowMode -eq 'FullScreen'
    $bounds = if($isFull){$screen.Bounds}else{$screen.WorkingArea}

    $layoutSettingsPath=Join-Path $script:BundleRoot 'splitscreen-settings.json'
    $cfg=if(Test-Path $layoutSettingsPath){Get-Content -Raw $layoutSettingsPath | ConvertFrom-Json}else{$null}
    $name=if($cfg -and $cfg.LayoutName -in @(Get-LayoutNames $clients.Count)){$cfg.LayoutName}else{@(Get-LayoutNames $clients.Count)[0]}
    $ratio=if($cfg -and $cfg.PSObject.Properties['SplitRatio']){[double]$cfg.SplitRatio}else{0.5}
    $cells=@(Get-NormalizedLayout $clients.Count $name $ratio)
    $sessions=Get-Content -Raw $script:SessionIndex | ConvertFrom-Json
    $ids=@(foreach($client in $clients){($sessions | Where-Object Pid -eq $client.Id | Select-Object -First 1).AccountId})
    $order=@(Resolve-LayoutOrder $ids $cfg.PlayerOrder)
    $maintain16x9=if($cfg -and $cfg.PSObject.Properties['Maintain16x9']){[bool]$cfg.Maintain16x9}else{$false}
    for($i=0;$i -lt $clients.Count;$i++){
        $h=$clients[$i].MainWindowHandle
        [void][HytaleSplitWindow]::ShowWindow($h,9)
        $style=[long]$saved[$i].Style
        if($ManualResize){$style=$style -bor [long]0x00CF0000}else{$style=$style -band (-bnot [long]0x00C40000)}
        [void][HytaleSplitWindow]::SetStyle($h,-16,[IntPtr]$style)
        $cellIndex=[array]::IndexOf($order,[string]$ids[$i])
        $cell=Convert-LayoutCell $cells[$cellIndex] $bounds $maintain16x9
        $x=$cell.X;$y=$cell.Y;$w=$cell.Width;$height=$cell.Height
        $order=if($isFull){[IntPtr](-1)}else{[IntPtr](-2)}
        # Full display bounds plus HWND_TOPMOST cover the taskbar for every player.
        # SWP_NOACTIVATE preserves focus; omitting SWP_NOZORDER applies the order.
        if(![HytaleSplitWindow]::SetWindowPos($h,$order,$x,$y,$w,$height,0x0070)){throw 'Could not apply game window placement.'}
    }
}

