function Read-InstallPaths {
    $path=Join-Path $script:BundleRoot 'install-paths.json'
    if(Test-Path -LiteralPath $path){return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json}
    [pscustomobject]@{Client='';Launcher=''}
}
function Save-InstallPaths($Value){$Value | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:BundleRoot 'install-paths.json') -Encoding UTF8}
function Select-InstalledExecutable([string]$Name,[string]$Title){
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object Windows.Forms.OpenFileDialog
    $dialog.Title=$Title;$dialog.Filter="$Name|$Name";$dialog.CheckFileExists=$true
    try{if($dialog.ShowDialog() -ne 'OK'){throw 'Setup canceled. No installation files were changed.'};return $dialog.FileName}finally{$dialog.Dispose()}
}
function Resolve-OfficialLauncher {
    $config=Read-InstallPaths
    $candidates=@($config.Launcher,(Join-Path $env:ProgramFiles 'Hypixel Studios\Hytale Launcher\hytale-launcher.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\Hytale Launcher\hytale-launcher.exe'))
    foreach($candidate in $candidates){if($candidate -and (Test-Path -LiteralPath $candidate)){return $candidate}}
    $config.Launcher=Select-InstalledExecutable 'hytale-launcher.exe' 'Locate your official Hytale Launcher'
    Save-InstallPaths $config
    $config.Launcher
}
