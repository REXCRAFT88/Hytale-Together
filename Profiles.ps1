# Account identity and data separation. Official launcher authentication stays untouched.
# profiles.json and sessions.json contain no session/identity tokens.
$script:ProfileIndex=Join-Path $PSScriptRoot 'profiles.json'
$script:SessionIndex=Join-Path $PSScriptRoot 'sessions.json'
$script:AccountRoot=Join-Path $env:APPDATA 'Hytale\SplitScreen\Accounts'
if(-not ('HytaleLaunchArgs' -as [type])){
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class HytaleLaunchArgs {
 [DllImport("shell32.dll",SetLastError=true)] static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string text,out int count);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr pointer);
 public static string[] Split(string text) { int count; var p=CommandLineToArgvW(text,out count); if(p==IntPtr.Zero)throw new InvalidOperationException("Cannot parse game launch arguments"); try { var r=new string[count]; for(int i=0;i<count;i++) r[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(p,i*IntPtr.Size)); return r; } finally{LocalFree(p);} }
 public static string Quote(string value) {
  var b=new StringBuilder("\"");int slashes=0;
  foreach(char c in value){if(c=='\\'){slashes++;continue;}if(c=='"'){b.Append('\\',slashes*2+1);b.Append(c);}else{b.Append('\\',slashes);b.Append(c);}slashes=0;}
  b.Append('\\',slashes*2);b.Append('"');return b.ToString();
 }
 public static string Join(string[] args){var values=new List<string>();foreach(var arg in args)values.Add(Quote(arg));return string.Join(" ",values);}
}
'@
}
function Get-Option([string[]]$Values,[string]$Name){
    for($i=1;$i -lt $Values.Count;$i++){
        if($Values[$i] -eq "--$Name" -and $i+1 -lt $Values.Count){return $Values[$i+1]}
        if($Values[$i].StartsWith("--$Name=")){return $Values[$i].Substring($Name.Length+3)}
    }
    return $null
}
function Get-AccountLaunches {
    $result=@()
    foreach($row in (Get-CimInstance Win32_Process -Filter "Name='HytaleClient.exe'" -OperationTimeoutSec 3)){
        $proc=Get-Process -Id $row.ProcessId -ErrorAction Stop
        $values=[HytaleLaunchArgs]::Split($row.CommandLine)
        $id=Get-Option -Values $values -Name 'uuid'
        $mode=Get-Option -Values $values -Name 'auth-mode'
        if(!$id -or $mode -ne 'authenticated'){throw 'Both games must be signed into their real Hytale accounts.'}
        $id=([guid]$id).ToString('D')
        $name=Get-Option -Values $values -Name 'name'
        $userDir=Get-Option -Values $values -Name 'user-dir'
        $appDir=Get-Option -Values $values -Name 'app-dir'
        if(!$userDir -or !$appDir -or !$name){throw 'The running client is missing account or directory launch options.'}
        $branch=if($appDir -match '[\\/]pre-release[\\/]'){'pre-release'}else{'release'}
        $result+=[pscustomobject]@{Pid=$proc.Id;StartTicks=$proc.StartTime.ToUniversalTime().Ticks.ToString();Process=$proc;Values=$values;AccountId=$id;Name=$name;SourceDir=[IO.Path]::GetFullPath($userDir);AppDir=$appDir;Exe=$proc.Path;Branch=$branch}
    }
    return @($result | Sort-Object { [long]$_.StartTicks })
}
function Read-Profiles {
    if(Test-Path -LiteralPath $script:ProfileIndex){
        $decoded=Get-Content -Raw -LiteralPath $script:ProfileIndex | ConvertFrom-Json
        foreach($profile in $decoded){Write-Output $profile}
        return
    }
    return @()
}
function Save-PublicJson($Value,[string]$Path){
    $json=ConvertTo-Json -InputObject @($Value) -Depth 8
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
    if([IO.File]::Exists($Path)){
        $backup=$Path+'.'+[guid]::NewGuid().ToString('N')+'.bak'
        [IO.File]::Replace($temporary,$Path,$backup)
        [IO.File]::Delete($backup)
    }else{[IO.File]::Move($temporary,$Path)}
}
function Initialize-AccountData($Launch,$Profile){
    $target=[IO.Path]::GetFullPath($Profile.UserData)
    $root=[IO.Path]::GetFullPath($script:AccountRoot).TrimEnd('\')+'\'
    if(!$target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Profile directory is outside the dedicated account root.'}
    $marker=Join-Path $target '.split-profile-initialized.json'
    if(Test-Path -LiteralPath $marker){return}
    if($target -eq $Launch.SourceDir){throw 'Uninitialized account data cannot be used as its own copy source.'}
    New-Item -ItemType Directory -Force $target | Out-Null
    foreach($folder in @('Saves','Mods')){
        $source=Join-Path $Launch.SourceDir $folder
        $destination=Join-Path $target $folder
        if(Test-Path -LiteralPath $source){
            if((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Refusing linked source $folder; independent copies are required."}
            $links=@(Get-ChildItem -LiteralPath $source -Recurse -Attributes ReparsePoint -ErrorAction Stop)
            if($links.Count){throw "The $folder folder contains links. Resolve them before importing isolated data."}
            New-Item -ItemType Directory -Force $destination | Out-Null
            foreach($item in (Get-ChildItem -LiteralPath $source -Force)){Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force}
        }else{New-Item -ItemType Directory -Force $destination | Out-Null}
    }
    foreach($file in @('Settings.json','MaskPresets.json','PalettePresets.json','RecentlyPlayedServers.json')){
        $source=Join-Path $Launch.SourceDir $file
        if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $target $file) -Force}
    }
    [pscustomobject]@{AccountId=$Profile.AccountId;Source=$Launch.SourceDir;InitializedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
}
function Disable-OfficialRouting {
    $routing=Join-Path $PSScriptRoot 'launcher-routing.ini'
    if(Test-Path -LiteralPath $routing){
        $text=Get-Content -Raw -LiteralPath $routing
        $text.Replace('Enabled=1','Enabled=0') | Set-Content -LiteralPath $routing -Encoding Unicode
    }
}
function Get-SessionClients {
    if(!(Test-Path -LiteralPath $script:SessionIndex)){return @()}
    $result=@()
    $decoded=Get-Content -Raw -LiteralPath $script:SessionIndex | ConvertFrom-Json
    foreach($entry in ($decoded | Sort-Object ScreenSlot)){
        $p=Get-Process -Id $entry.Pid -ErrorAction SilentlyContinue
        if($p -and $p.ProcessName -eq 'HytaleClient' -and $p.StartTime.ToUniversalTime().Ticks.ToString() -eq $entry.StartTicks){$result+=$p}
    }
    return $result
}
