# Public account catalog and session validation. Authentication remains in the launcher.
function Get-SelectedProfiles {
    @(Read-Profiles | Where-Object { !$_.PSObject.Properties['Enabled'] -or $_.Enabled } | Sort-Object ScreenSlot)
}
function Assert-PlayerConfiguration($Profiles,[switch]$RequireControllers) {
    if($Profiles.Count -lt 1 -or $Profiles.Count -gt 4){throw 'Select between 1 and 4 accounts.'}
    foreach($field in @('AccountId','ScreenSlot','UserData')){
        if(@($Profiles | Select-Object -ExpandProperty $field -Unique).Count -ne $Profiles.Count){throw "Each player needs a different $field."}
    }
    if(@($Profiles | Select-Object -ExpandProperty Branch -Unique).Count -ne 1){throw 'Use the same game branch for all selected accounts.'}
    foreach($p in $Profiles){
        $expected=Join-Path $script:AccountRoot (([guid]$p.AccountId).ToString('D')+'\'+$p.Branch+'\UserData')
        if([IO.Path]::GetFullPath($p.UserData).TrimEnd('\') -ne [IO.Path]::GetFullPath($expected).TrimEnd('\')){throw "Unexpected private folder for $($p.Name)."}
        if(!(Test-Path -LiteralPath (Join-Path $p.UserData '.split-profile-initialized.json'))){throw "Private folder for $($p.Name) is not initialized. Discover the account from its running client first."}
        if($RequireControllers -and $p.Controller -ne 'KBM' -and $p.Controller -notmatch '^[0-9a-fA-F]{16}$'){throw "Assign a controller or Keyboard & Mouse to $($p.Name)."}
    }
    if($RequireControllers){
        $kbm=@($Profiles | Where-Object {$_.Controller -eq 'KBM'})
        if($kbm.Count -gt 1){throw 'Only one player can be assigned Keyboard & Mouse.'}
        $pads=@($Profiles | Where-Object {$_.Controller -ne 'KBM'} | Select-Object -ExpandProperty Controller)
        if(@($pads | Select-Object -Unique).Count -ne $pads.Count){throw 'A controller can belong to only one selected account.'}
    }
}
function Import-RunningAccounts {
    $profiles=@(Read-Profiles)
    foreach($launch in @(Get-AccountLaunches)){
        if(@($profiles | Where-Object {$_.AccountId -eq $launch.AccountId -and $_.Branch -eq $launch.Branch}).Count){continue}
        $p=[pscustomobject]@{AccountId=$launch.AccountId;Name=$launch.Name;Branch=$launch.Branch;Controller='';UserData=(Join-Path $script:AccountRoot ($launch.AccountId+'\'+$launch.Branch+'\UserData'));ScreenSlot=($profiles.Count+1);TouchpadMouseEnabled=$true;TouchpadSensitivity=1.0;EscapeButtonMode=2;Enabled=($profiles.Count -lt 4);Color='Electric Cyan';ClientExe=$launch.Exe}
        Initialize-AccountData $launch $p
        $profiles+=,$p
        Write-Output "Discovered $($p.Name). Private data prepared; relaunch this account after Auto prepares routing."
    }
    Save-PublicJson $profiles $script:ProfileIndex
}
function Write-RoutingConfiguration {
    $profiles=@(Get-SelectedProfiles);Assert-PlayerConfiguration $profiles
    $exe=Join-Path $env:APPDATA ('Hytale\install\'+$profiles[0].Branch+'\package\game\latest\Client\HytaleClient.exe')
    if($profiles[0].PSObject.Properties['ClientExe'] -and (Test-Path -LiteralPath $profiles[0].ClientExe)){$exe=$profiles[0].ClientExe}
    if(!(Test-Path -LiteralPath $exe)){throw 'Game installation not found. Discover the account again from its running client.'}
    $lines=@('[Session]','Enabled=1',('Executable='+$exe),'[Accounts]')
    foreach($p in $profiles){$lines+=([guid]$p.AccountId).ToString('D')+'='+$p.UserData}
    $routing=Join-Path $script:BundleRoot 'launcher-routing.ini'
    $lines | Set-Content -LiteralPath ($routing+'.tmp') -Encoding Unicode
    Move-Item -LiteralPath ($routing+'.tmp') -Destination $routing -Force
    'Private account routing prepared.'
}
function Invoke-InputHost([string[]]$Arguments){
    if(!(Test-Path -LiteralPath (Join-Path $script:BundleRoot 'HytaleInputHost.exe'))){throw 'Input helper is missing or quarantined. Check Windows Security Protection history. No input operation was performed.'}
    $result=& (Join-Path $script:BundleRoot 'HytaleInputHost.exe') @Arguments 2>&1
    if($LASTEXITCODE){throw ($result -join ' ')}
    $result
}
function Get-AdapterSnapshot([int]$GameId){
    $map=$null;$view=$null
    try{
        $map=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting("Local\HytaleInput-v5-$GameId",[IO.MemoryMappedFiles.MemoryMappedFileRights]::Read)
        $view=$map.CreateViewAccessor(0,0,[IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read)
        if($view.ReadUInt32(0) -ne 0x48594905){throw 'Unknown input adapter protocol.'}
        $process=Get-Process -Id $GameId -ErrorAction Stop
        if($view.ReadUInt64(8) -ne [uint64]$process.StartTime.ToUniversalTime().ToFileTimeUtc()){throw 'Stale input adapter status.'}
        [pscustomobject]@{Pid=$GameId;Identity=$view.ReadUInt64(16).ToString('x16');Command=$view.ReadInt32(24);Phase=$view.ReadInt32(28);Selected=$view.ReadInt32(36);Passed=$view.ReadInt32(56);Dropped=$view.ReadInt32(60)}
    }finally{if($view){$view.Dispose()};if($map){$map.Dispose()}}
}
function Attach-SelectedAccounts {
    $profiles=@(Get-SelectedProfiles);Assert-PlayerConfiguration $profiles -RequireControllers
    $launches=@(Get-AccountLaunches);$session=@()
    # Validate every client before changing input in any client.
    foreach($p in $profiles){
        $matches=@($launches | Where-Object {$_.AccountId -eq $p.AccountId -and $_.Branch -eq $p.Branch})
        if($matches.Count -ne 1){
            $anyMatch=@($launches | Where-Object {$_.AccountId -eq $p.AccountId})
            if($anyMatch.Count -eq 1 -and $anyMatch[0].Branch -ne $p.Branch){
                throw "$($p.Name) is running on '$($anyMatch[0].Branch)', but the profile is set to '$($p.Branch)'."
            }
            throw "Need exactly one running client for $($p.Name)."
        }
        $l=$matches[0]
        if([IO.Path]::GetFullPath($l.SourceDir).TrimEnd('\') -ne [IO.Path]::GetFullPath($p.UserData).TrimEnd('\')){throw "$($p.Name) is using the shared folder. Close that client, click Auto, wait for routing ready, then launch it again."}
        if(!$l.Process.MainWindowHandle){throw "$($p.Name)'s window is not ready."}
        $sens=if($p.PSObject.Properties['TouchpadSensitivity'] -and $p.TouchpadSensitivity -gt 0){[double]$p.TouchpadSensitivity}else{1.0}
        $session+=,[pscustomobject]@{Pid=$l.Pid;StartTicks=$l.StartTicks;AccountId=$p.AccountId;Name=$p.Name;UserData=$p.UserData;Controller=$p.Controller;ScreenSlot=$p.ScreenSlot;TouchpadMouseEnabled=$p.TouchpadMouseEnabled;TouchpadSensitivity=$sens;EscapeButtonMode=$p.EscapeButtonMode}
    }
    # Native attach updates an existing active mapping; a stopped mapping fails explicitly.
    $attached=@()
    try {
        foreach($p in $session){
            if($p.Controller -eq 'KBM'){
                $attachArgs = @('attach',[string]$p.Pid,'kbm','0','0')
                Invoke-InputHost $attachArgs | Out-Null
                $attached+=,$p
                $status=Get-AdapterSnapshot $p.Pid
                if($status.Phase -ne 2){throw "$($p.Name): Keyboard & Mouse isolation is not ready."}
                Write-Output "$($p.Name): Keyboard & Mouse active (controllers barred)."
                continue
            }
            $attachArgs = @('attach',[string]$p.Pid,$p.Controller,[string][int][bool]$p.TouchpadMouseEnabled,[string][int]$p.EscapeButtonMode)
            Invoke-InputHost $attachArgs | Out-Null
            $attached+=,$p
            $status=Get-AdapterSnapshot $p.Pid
            if($status.Phase -ne 2 -or $status.Identity -ne $p.Controller -or !$status.Selected){throw "$($p.Name): assigned controller is not ready."}
            "$($p.Name): controller attached."
        }
    } catch {
        foreach($p in $attached){try{Invoke-InputHost @('pause',[string]$p.Pid) | Out-Null}catch{}}
        throw
    }
    Save-PublicJson $session $script:SessionIndex
}
function Get-LayoutCell([int]$Count,[int]$Index,$Bounds,[string]$Layout,$Fit16x9=$false){
    $fit = if($Fit16x9 -is [bool]){ $Fit16x9 } elseif($Fit16x9 -is [string]){ $Fit16x9 -notin @('False','false','0','','System.String') } else { [bool]$Fit16x9 }
    if($Count -lt 1 -or $Count -gt 4 -or $Index -lt 0 -or $Index -ge $Count){throw 'Invalid player layout.'}
    $cols=1;$rows=1
    if($Count -eq 2){if($Layout -eq 'Vertical'){$cols=2}else{$rows=2}}
    if($Count -ge 3){$cols=2;$rows=2}
    $column=$Index % $cols;$row=[math]::Floor($Index/$cols)
    $x=$Bounds.X+[math]::Floor($column*$Bounds.Width/$cols);$y=$Bounds.Y+[math]::Floor($row*$Bounds.Height/$rows)
    $w=[math]::Floor(($column+1)*$Bounds.Width/$cols)-[math]::Floor($column*$Bounds.Width/$cols)
    $h=[math]::Floor(($row+1)*$Bounds.Height/$rows)-[math]::Floor($row*$Bounds.Height/$rows)
    if($fit){$scale=[math]::Floor([math]::Min($w/16,$h/9));$fw=16*$scale;$fh=9*$scale;$x+=[math]::Floor(($w-$fw)/2);$y+=[math]::Floor(($h-$fh)/2);$w=$fw;$h=$fh}
    [pscustomobject]@{X=[int]$x;Y=[int]$y;Width=[int]$w;Height=[int]$h}
}
