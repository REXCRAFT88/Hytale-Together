$ErrorActionPreference='Stop'
$script:BundleRoot=$PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms
try {
    Add-Type -MemberDefinition '[DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPWStr)] string AppID);' -Name 'ShellAppId' -Namespace 'HytaleTogether'
    [HytaleTogether.ShellAppId]::SetCurrentProcessExplicitAppUserModelID('HytaleTogether.Launcher')
} catch {}
try{
    if(![Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell on Windows 10 or 11.'}
    . "$PSScriptRoot/modules/Installation.ps1"
    $config=Read-InstallPaths
    $candidates=@($config.Client,(Join-Path $env:APPDATA 'Hytale\install\release\package\game\latest\Client\HytaleClient.exe'),(Join-Path $env:APPDATA 'Hytale\install\pre-release\package\game\latest\Client\HytaleClient.exe'))
    $client=$candidates | Where-Object {$_ -and (Test-Path -LiteralPath $_)} | Select-Object -First 1
    if(!$client){$client=Select-InstalledExecutable 'HytaleClient.exe' 'Locate your installed Hytale game (Client folder)'}
    $sdl=Join-Path (Split-Path $client) 'SDL3.dll'
    if(!(Test-Path -LiteralPath $sdl)){throw 'The selected installation has no SDL3.dll next to HytaleClient.exe.'}
    $config.Client=$client;Save-InstallPaths $config
    $destination=Join-Path $PSScriptRoot 'SDL3.dll'
    if(!(Test-Path $destination) -or (Get-FileHash $sdl).Hash -ne (Get-FileHash $destination).Hash){Copy-Item -LiteralPath $sdl -Destination $destination -Force}
    $env:PATH=$PSScriptRoot+';'+$env:PATH
    Add-Type 'public static class InstalledSDL { [System.Runtime.InteropServices.DllImport("SDL3.dll", CallingConvention=System.Runtime.InteropServices.CallingConvention.Cdecl)] public static extern int SDL_GetVersion(); }'
    if([InstalledSDL]::SDL_GetVersion() -ne 3002026){throw 'This preview supports SDL 3.2.26. Your Hytale installation uses another SDL build; an adapter update is required before attaching. No game files were changed.'}
    & "$PSScriptRoot/SplitScreen.ps1"
}catch{
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message+"`r`n`r`nExtract the full ZIP to a writable folder before running it.",'Hytale Split Screen - setup')
    exit 1
}
