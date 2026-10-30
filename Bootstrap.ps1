$ErrorActionPreference='Stop'
$script:BundleRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'modules/Startup.ps1')
$stage='Checking application files'
Add-Type -AssemblyName System.Windows.Forms
try {
    Add-Type -MemberDefinition '[DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPWStr)] string AppID);' -Name 'ShellAppId' -Namespace 'HytaleTogether'
    [HytaleTogether.ShellAppId]::SetCurrentProcessExplicitAppUserModelID('HytaleTogether.Launcher')
} catch {}
try{
    if(![Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell on Windows 10 or 11.'}
    Assert-BundleWritable $PSScriptRoot
    $stage='Locating the installed game'
    . "$PSScriptRoot/modules/Installation.ps1"
    $config=Read-InstallPaths
    $candidates=@($config.Client,(Join-Path $env:APPDATA 'Hytale\install\release\package\game\latest\Client\HytaleClient.exe'),(Join-Path $env:APPDATA 'Hytale\install\pre-release\package\game\latest\Client\HytaleClient.exe'))
    $client=$candidates | Where-Object {$_ -and (Test-Path -LiteralPath $_)} | Select-Object -First 1
    if(!$client){$client=Select-InstalledExecutable 'HytaleClient.exe' 'Locate your installed Hytale game (Client folder)'}
    $stage='Loading bundled controller runtime'
    $destination=Join-Path $PSScriptRoot 'SDL3.dll'
    if(!(Test-Path -LiteralPath $destination)){throw 'Bundled SDL3.dll is missing. Extract the complete Windows ZIP again.'}
    $config.Client=$client;Save-InstallPaths $config
    $env:PATH=$PSScriptRoot+';'+$env:PATH
    $stage='Loading and checking the game SDL library'
    Import-InstalledSDL $destination
    $stage='Opening the session panel'
    & "$PSScriptRoot/SplitScreen.ps1"
}catch{
    [void][Windows.Forms.MessageBox]::Show((Write-StartupFailure $_ $stage),'Hytale Together - startup failed')
    exit 1
}
