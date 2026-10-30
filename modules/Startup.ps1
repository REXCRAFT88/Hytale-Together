function Assert-BundleWritable([string]$Root){
    $probe=Join-Path $Root ('.write-check-'+[guid]::NewGuid().ToString('N'))
    try {
        $stream=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Dispose()
        [IO.File]::Delete($probe)
    } catch { throw "The application folder cannot be written to: $Root. Extract the full ZIP into a folder you own, such as Documents. Details: $($_.Exception.Message)" }
}
function Write-StartupFailure($Record,[string]$Stage){
    $cause=$Record.Exception
    while($cause.InnerException){$cause=$cause.InnerException}
    $message="Startup failed during: $Stage`r`n`r`n$($cause.Message)"
    $folder=Join-Path $env:LOCALAPPDATA 'HytaleTogether/Diagnostics'
    try {
        [void][IO.Directory]::CreateDirectory($folder)
        $file=Join-Path $folder ('startup-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')+'.log')
        $details="Hytale Together 0.3.2-preview`r`n$([DateTime]::UtcNow.ToString('o'))`r`n$message`r`nPowerShell: $($PSVersionTable.PSVersion); 64-bit: $([Environment]::Is64BitProcess)`r`n$($Record.ScriptStackTrace)`r`n$($Record.Exception.ToString())"
        [IO.File]::WriteAllText($file,$details)
        $message+="`r`n`r`nDiagnostic log: $file"
    } catch { $message+="`r`n`r`nCould not write a diagnostic log: $($_.Exception.Message)" }
    return $message
}
function Import-InstalledSDL([string]$Path){
    if(-not ('HytaleTogether.NativeLoader' -as [type])){
        Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace HytaleTogether {
 public static class NativeLoader {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Ansi,SetLastError=true)] static extern IntPtr GetProcAddress(IntPtr module,string name);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Version();
  public static int Load(string path){
   var module=LoadLibraryEx(path,IntPtr.Zero,0x1100);
   if(module==IntPtr.Zero){int code=Marshal.GetLastWin32Error();throw new Win32Exception(code,"Cannot load SDL3.dll or a dependency. Windows error "+code+": "+new Win32Exception(code).Message);}
   var proc=GetProcAddress(module,"SDL_GetVersion");
   if(proc==IntPtr.Zero)throw new Exception("SDL3.dll does not export SDL_GetVersion.");
   return ((Version)Marshal.GetDelegateForFunctionPointer(proc,typeof(Version)))();
  }
 }
}
'@
    }
    $version=[HytaleTogether.NativeLoader]::Load([IO.Path]::GetFullPath($Path))
    if($version -ne 3002026){
        $display='{0}.{1}.{2}' -f [math]::Floor($version/1000000),([math]::Floor($version/1000)%1000),($version%1000)
        throw "Unsupported game SDL version: $display. This adapter requires SDL 3.2.26. A compatible adapter update is needed; moving or extracting the folder again will not fix this. No game files were changed."
    }
}
