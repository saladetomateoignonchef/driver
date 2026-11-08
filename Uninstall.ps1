#Requires -Version 5.1
<# Désinstalle Driver : tâche planifiée, raccourci et fichiers du programme. #>
[CmdletBinding()]
param([switch]$KeepLogs)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Common.ps1')

if (-not (Test-IsAdmin)) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    exit
}

Unregister-ScheduledTask -TaskName 'DriverUpdater' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Driver.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:ProgramFiles 'DriverUpdater') -Recurse -Force -ErrorAction SilentlyContinue
if (-not $KeepLogs) { Remove-Item $script:DataDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host 'Driver a été désinstallé.' -ForegroundColor Green
