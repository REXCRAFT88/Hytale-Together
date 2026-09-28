param([Parameter(Mandatory=$true)][string]$ClientDirectory)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$client=(Resolve-Path -LiteralPath $ClientDirectory).Path
if(!(Test-Path (Join-Path $client 'HytaleClient.exe'))){throw 'Point ClientDirectory at your installed Hytale Client folder.'}
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'Install Visual Studio 2022 C++ Build Tools and the Windows SDK.'}
$toolset=Get-ChildItem (Join-Path $vs 'VC\Tools\MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1
$dumpbin=Join-Path $toolset.FullName 'bin\Hostx64\x64\dumpbin.exe'
$lib=Join-Path $toolset.FullName 'bin\Hostx64\x64\lib.exe'
$cmake=Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
Copy-Item (Join-Path $client 'SDL3.dll') (Join-Path $root 'SDL3.dll') -Force
$exports=& $dumpbin /nologo /exports (Join-Path $root 'SDL3.dll')
if($LASTEXITCODE){throw 'Cannot read SDL exports.'}
$names=@($exports | ForEach-Object {if($_ -match '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(SDL_\w+)'){$Matches[1]}})
if($names.Count -lt 100){throw 'SDL export validation failed.'}
@('LIBRARY SDL3.dll','EXPORTS')+$names | Set-Content (Join-Path $root 'SDL3.def') -Encoding ASCII
& $lib /nologo "/def:$root\SDL3.def" /machine:x64 "/out:$root\SDL3.lib"
if($LASTEXITCODE){throw 'Import library generation failed.'}
& $cmake -S $root -B (Join-Path $root 'build') -G 'Visual Studio 17 2022' -A x64
if($LASTEXITCODE){throw 'CMake configure failed.'}
& $cmake --build (Join-Path $root 'build') --config Release
if($LASTEXITCODE){throw 'Build failed.'}
'Native artifacts are in build\Release. No installed game or working helper was overwritten.'
