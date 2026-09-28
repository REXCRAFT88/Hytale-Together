# Timer-owned state, never PowerShell script blocks on unmanaged/ThreadPool callbacks.
function Open-OfficialLauncher {
    $path=Resolve-OfficialLauncher
    Start-Process explorer.exe -ArgumentList ('"'+$path+'"') | Out-Null
}
function New-LaunchState { [pscustomobject]@{Phase='Idle';AutoJob=$null;AutoTarget='';AutoLauncherPid=0;AutoStarted=[DateTime]::UtcNow;Armed='';Requested=@{};UsedLaunchers=@{};Hooked=@{};HookAttempts=@{};HookJob=$null;HookPid=0;Started=[DateTime]::UtcNow;LastOpen=[DateTime]::UtcNow;OpenAttempts=0;LastMessage=''} }
function Get-LaunchDecision([string[]]$Expected,[string[]]$Running,[bool]$WindowsReady){
    $missing=@($Expected | Where-Object {$_ -notin $Running})
    if(!$missing.Count -and $WindowsReady){return 'Attach'}
    return 'AwaitAccounts'
}

function Stop-LauncherAutomation {
    if($script:launch.AutoJob){$script:launch.AutoJob.Cancel();$script:launch.AutoJob.Dispose();$script:launch.AutoJob=$null}
}
function Update-LauncherAutomation($Missing,$Launchers){
    $autoEnabled=$true
    if(Get-Variable script:autoLaunch -ErrorAction SilentlyContinue){if($false -eq $script:autoLaunch){$autoEnabled=$false}}
    if((Get-Variable uiAutoLaunch -ErrorAction SilentlyContinue) -and $uiAutoLaunch){if(!$uiAutoLaunch.IsChecked){$autoEnabled=$false}}
    if(!$autoEnabled -or !$Missing.Count){return}
    $state=$script:launch
    if($state.AutoJob){
        if(!$state.AutoJob.IsCompleted){
            if([DateTime]::UtcNow -gt $state.AutoStarted.AddSeconds(15)){
                Stop-LauncherAutomation
                $script:autoLaunch=$false
                if((Get-Variable uiAutoLaunch -ErrorAction SilentlyContinue) -and $uiAutoLaunch){$uiAutoLaunch.IsChecked=$false}
                Write-Panel 'Launcher did not answer. Continue by selecting the account and Play manually.'
            }
            return
        }
        $ok=$state.AutoJob.ExitCode -eq 0;$result=$state.AutoJob.Output.Trim();$errorText=$state.AutoJob.Error.Trim()
        $state.AutoJob.Dispose();$state.AutoJob=$null
        if(!$ok){
            $script:autoLaunch=$false
            if((Get-Variable uiAutoLaunch -ErrorAction SilentlyContinue) -and $uiAutoLaunch){$uiAutoLaunch.IsChecked=$false}
            Write-Panel ('Automatic launch paused: '+$errorText)
            return
        }
        if($result -eq 'ACCOUNT_READY'){$state.Armed=$state.AutoTarget}
        if($result -eq 'PLAY_REQUESTED'){
            $state.Requested[$state.AutoTarget]=[DateTime]::UtcNow
            if($state.AutoLauncherPid){$state.UsedLaunchers[[string]$state.AutoLauncherPid]=$state.AutoTarget}
            Write-Panel 'Play requested. Waiting for the authenticated game window.'
        }
    }
    $target=$Missing[0]
    if($state.Requested.ContainsKey($target.AccountId)){
        if([DateTime]::UtcNow -gt $state.Requested[$target.AccountId].AddMinutes(2)){Write-Panel 'Game launch needs attention. Check the official launcher; automatic Play will not be repeated.'}
        return
    }
    $ready=@($Launchers | Where-Object {
        (!$state.UsedLaunchers.ContainsKey([string]$_.Id) -or $state.UsedLaunchers[[string]$_.Id] -eq $target.AccountId) -and
        $state.Hooked[[string]$_.Id] -eq $true -and
        $_.MainWindowHandle
    })
    if($ready.Count -lt 1){return}
    $launcher=$ready[0]
    $state.AutoTarget=$target.AccountId;$state.AutoLauncherPid=$launcher.Id;$state.AutoStarted=[DateTime]::UtcNow
    $args='-NoProfile -STA -ExecutionPolicy Bypass -File '+[HytaleLaunchArgs]::Quote((Join-Path $script:BundleRoot 'LauncherStep.ps1'))+' -LauncherPid '+$launcher.Id+' -AccountId '+[HytaleLaunchArgs]::Quote($target.AccountId)+' -Branch '+[HytaleLaunchArgs]::Quote($target.Branch)
    if($state.Armed -eq $target.AccountId){$args+=' -AllowPlay'}
    $state.AutoJob=Start-LauncherStepJob $args
}

function Start-LauncherStepJob([string]$Arguments){[HytaleAssignmentProcess]::new((Join-Path $PSHOME 'powershell.exe'),$Arguments)}
