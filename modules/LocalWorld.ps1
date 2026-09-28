# Discover an active shared world, never an old port from an unrelated process.
function Get-SharedWorldPort([string[]]$Lines){
    $port=0
    foreach($line in $Lines){
        if($line -match 'Server requested access change to: (\w+), external port: (\d+)'){
            $port=if($Matches[1] -in @('LAN','Online','Public','Friends')){[int]$Matches[2]}else{0}
        }
    }
    if($port -gt 0 -and $port -le 65535){return $port}
    return 0
}
function Test-ProcessDescendant([int]$Child,[int]$Ancestor,$Processes){
    $seen=@{}
    for($depth=0;$depth -lt 8;$depth++){
        if($Child -eq $Ancestor){return $true}
        if($seen.ContainsKey($Child)){return $false};$seen[$Child]=$true
        $node=$Processes | Where-Object {$_.ProcessId -eq $Child} | Select-Object -First 1
        if(!$node){return $false};$Child=[int]$node.ParentProcessId
    }
    return $false
}
function Get-LocalWorldEndpoints {
    $launches=@(Get-AccountLaunches)
    if(!$launches.Count){return}
    $processes=@(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name -OperationTimeoutSec 3)
    $udp=@(Get-NetUDPEndpoint -ErrorAction Stop)
    foreach($launch in $launches){
        $log=Get-ChildItem -LiteralPath (Join-Path $launch.SourceDir 'Logs') -Filter '*client.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if(!$log){continue}
        $port=Get-SharedWorldPort @(Get-Content -LiteralPath $log.FullName -Tail 12000)
        if(!$port){continue}
        $listeners=@($udp | Where-Object {$_.LocalPort -eq $port -and $_.LocalAddress -in @('0.0.0.0','127.0.0.1','::','::1')})
        foreach($listener in $listeners){
            if(!(Test-ProcessDescendant $listener.OwningProcess $launch.Pid $processes)){continue}
            $address=if($listener.LocalAddress -in @('::','::1')){'[::1]'}else{'127.0.0.1'}
            # Prefer IPv4 when both bindings exist.
            $ipv4=$listeners | Where-Object {$_.OwningProcess -eq $listener.OwningProcess -and $_.LocalAddress -in @('0.0.0.0','127.0.0.1')} | Select-Object -First 1
            if($ipv4){$address='127.0.0.1'}
            [pscustomobject]@{AccountId=$launch.AccountId;Name=$launch.Name;HostPid=$launch.Pid;HostStartTicks=$launch.StartTicks;ServerPid=[int]$listener.OwningProcess;Port=$port;Address=($address+':'+$port);Label=($launch.Name+' - '+$address+':'+$port)}
            break
        }
    }
}
function Save-LocalWorldEndpoints {
    $worlds=@(Get-LocalWorldEndpoints)
    Save-PublicJson $worlds (Join-Path $script:BundleRoot 'local-worlds.json')
    if(!$worlds.Count){'No active shared world found. Load a world and enable LAN sharing on the host, then refresh.';return}
    foreach($world in $worlds){"$($world.Name): $($world.Address) - on the other client, use Servers > Direct Connect."}
}
