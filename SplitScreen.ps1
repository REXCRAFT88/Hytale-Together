param(
 [ValidateSet('Open','Prepare','Discover','Attach','Pause','Resume','Stop','Status','Restore','LocalWorlds','Arrange')][string]$Action='Open',
 [ValidateSet('Horizontal','Vertical')][string]$Layout='Horizontal',
 [ValidateSet('Windowed','FullScreen')][string]$WindowMode='Windowed',
 [switch]$ManualResize,[int]$MonitorIndex=0
)
$ErrorActionPreference='Stop'
$script:BundleRoot=$PSScriptRoot
$script:stateFile=Join-Path $PSScriptRoot 'window-state.json'
$env:PATH="$PSScriptRoot;"+$env:PATH
$env:SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS='1'
. "$PSScriptRoot/Profiles.ps1"
. "$PSScriptRoot/modules/Accounts.ps1"
. "$PSScriptRoot/modules/Layouts.ps1"
. "$PSScriptRoot/modules/Windows.ps1"
. "$PSScriptRoot/modules/Installation.ps1"
. "$PSScriptRoot/modules/Launcher.ps1"
. "$PSScriptRoot/modules/LocalWorld.ps1"
if($Action -ne 'Open'){
 try {
  switch($Action){
   Prepare { Write-RoutingConfiguration }
   Discover { Import-RunningAccounts }
   LocalWorlds { Save-LocalWorldEndpoints }
   Attach { Attach-SelectedAccounts; Set-SplitLayout -TargetMonitorIndex $MonitorIndex }
   Arrange { Set-SplitLayout -TargetMonitorIndex $MonitorIndex }
   Restore { Restore-Windows }
   default {
    foreach($client in @(Get-SessionClients)){Invoke-InputHost @($Action.ToLowerInvariant(),[string]$client.Id)}
    if($Action -eq 'Stop'){Disable-OfficialRouting;Restore-Windows}
   }
  }
  exit 0
 } catch { [Console]::Error.WriteLine($_.Exception.Message);exit 1 }
}
$panelLock=New-Object Threading.Mutex($false,'Local\HytaleSplitScreenStudio')
$ownsPanel=$false
try {
    try{$ownsPanel=$panelLock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsPanel=$true}
    if(!$ownsPanel){[void][Windows.MessageBox]::Show('Hytale Split Screen Studio is already open.');return}
    $pendingAdapter=Join-Path $PSScriptRoot 'pending/HytaleInput-v5.dll'
    if((Test-Path -LiteralPath $pendingAdapter) -and !@(Get-Process HytaleClient -ErrorAction SilentlyContinue).Count){
        $activeAdapter=Join-Path $PSScriptRoot 'HytaleInput-v5.dll'
        Copy-Item -LiteralPath $activeAdapter -Destination ($activeAdapter+'.previous') -Force
        Copy-Item -LiteralPath $pendingAdapter -Destination $activeAdapter -Force
        if((Get-FileHash -LiteralPath $activeAdapter).Hash -ne (Get-FileHash -LiteralPath $pendingAdapter).Hash){throw 'Adapter update verification failed.'}
        Remove-Item -LiteralPath $pendingAdapter
    }
    . "$PSScriptRoot/modules/Studio.ps1"
} finally {if($ownsPanel){$panelLock.ReleaseMutex()};$panelLock.Dispose()}
