function Set-SelectedGameBranch([ValidateSet('release','pre-release')][string]$Branch){
    if(@(Get-Process HytaleClient -ErrorAction SilentlyContinue).Count){throw 'Close all game clients before changing branches. Existing saves will remain in their branch folders.'}
    $profiles=@(Read-Profiles)
    $selected=@($profiles | Where-Object { !$_.PSObject.Properties['Enabled'] -or $_.Enabled })
    if(!$selected.Count){throw 'Add and select your player accounts first.'}
    $config=Read-InstallPaths
    $standard=Join-Path $env:APPDATA "Hytale/install/$Branch/package/game/latest/Client/HytaleClient.exe"
    $candidates=@($standard)
    foreach($path in @($config.Client)+@($selected.ClientExe)){
        if($path){$candidates+=($path -replace '([\\/])(pre-release|release)([\\/])', ('${1}'+$Branch+'${3}'))}
    }
    $client=$candidates | Where-Object {$_ -and (Test-Path -LiteralPath $_)} | Select-Object -First 1
    if(!$client){throw "Install $Branch in the official launcher first, then retry switching branches."}
    $updated=@()
    foreach($profile in $selected){
        $next=$profile | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $next.Branch=$Branch;$next.ClientExe=$client
        $next.UserData=Join-Path $script:AccountRoot (([guid]$next.AccountId).ToString('D')+"\$Branch\UserData")
        $marker=Join-Path $next.UserData '.split-profile-initialized.json'
        if(!(Test-Path -LiteralPath $marker)){
            # Never import pre-release worlds into Release implicitly. Start an empty isolated folder.
            if((Test-Path -LiteralPath $next.UserData) -and @(Get-ChildItem -LiteralPath $next.UserData -Force).Count){throw "An uninitialized $Branch folder already contains data for $($next.Name). Discover that running account to prepare it safely."}
            [void][IO.Directory]::CreateDirectory($next.UserData)
            [void][IO.Directory]::CreateDirectory((Join-Path $next.UserData 'Saves'))
            [void][IO.Directory]::CreateDirectory((Join-Path $next.UserData 'Mods'))
            [pscustomobject]@{AccountId=$next.AccountId;InitializedUtc=[DateTime]::UtcNow.ToString('o');Source='New isolated branch'} | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
        }
        $updated+=,$next
    }
    # Keep one active catalog record per account, retaining unrelated disabled profiles.
    $others=@($profiles | Where-Object {$_.AccountId -notin @($selected.AccountId)})
    $backup=$script:ProfileIndex+'.before-branch-'+[DateTime]::Now.ToString('yyyyMMddHHmmssfff')+'.bak'
    Copy-Item -LiteralPath $script:ProfileIndex -Destination $backup
    Save-PublicJson @($others+$updated) $script:ProfileIndex
    $config.Client=$client;Save-InstallPaths $config
    Disable-OfficialRouting
    "Selected players now use $Branch. Existing branch saves and controller assignments were preserved. Set the same branch in official launcher Settings, then start the session."
}
