param([string]$AppDirectory = (Join-Path $PSScriptRoot '../outputs/HytaleTogether-0.3.0-preview'))
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll ("/win32icon:" + (Join-Path $AppDirectory 'assets/hytale-together.ico')) ("/out:" + (Join-Path $AppDirectory 'Hytale Together.exe')) (Join-Path $PSScriptRoot 'HytaleTogetherLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
