param([int]$LauncherPid,[string]$AccountId,[string]$Branch='',[switch]$AllowPlay)
$ErrorActionPreference='Stop'
try {
 Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
 Add-Type -Path (Join-Path $PSScriptRoot 'LauncherAutomation.cs') -ReferencedAssemblies @('System.Core','UIAutomationClient','UIAutomationTypes','WindowsBase')
 $profileFile=Join-Path $PSScriptRoot 'profiles.json'
 if(-not (Test-Path -LiteralPath $profileFile)){throw 'No saved accounts file (profiles.json) found.'}
 $raw=Get-Content -Raw -LiteralPath $profileFile
 $decoded=$raw | ConvertFrom-Json
 $profiles=@(foreach($x in $decoded){$x})
 $cleanId=$AccountId.Trim().Trim('"').Trim("'")
 $p=@($profiles | Where-Object {
  $matchId=($_.AccountId -eq $cleanId)
  if(!$matchId){
   try { $matchId=([guid]$_.AccountId).Equals([guid]$cleanId) } catch {}
  }
  $matchId -and (!$Branch -or $_.Branch -eq $Branch)
 })
 if($p.Count -ne 1){
  if($p.Count -eq 0){throw "Expected saved account with ID '$cleanId', but none was found."}
  throw "Expected exactly one saved account with ID '$cleanId', but found $($p.Count)."
 }
 $names=@($profiles | ForEach-Object { [string]$_.Name })
 [LauncherAutomation]::Step($LauncherPid,$p[0].Name,$p[0].Branch,[string[]]$names,$AllowPlay.IsPresent)
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
