#Requires -Version 5.1
<#
.SYNOPSIS
    Installe Driver : copie dans Program Files, tâche planifiée à l'ouverture de
    session, raccourci sur le Bureau.

.NOTES
    Pourquoi Program Files ? Le script s'exécute avec les droits administrateur au
    démarrage. S'il restait dans un dossier modifiable par un utilisateur standard,
    n'importe qui pourrait le modifier pour exécuter du code en tant qu'admin
    (élévation de privilèges). Program Files n'est modifiable que par les admins.
#>
[CmdletBinding()]
param([switch]$Silent)   # -Silent : utilisé par la mise à jour automatique de Driver

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Common.ps1')

if (-not (Test-IsAdmin)) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    exit
}

$target   = Join-Path $env:ProgramFiles 'DriverUpdater'
$taskName = 'DriverUpdater'
$user     = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "1/5 Copie des fichiers dans $target" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $target -Force | Out-Null
if (Test-Path (Join-Path $target 'src')) { Remove-Item (Join-Path $target 'src') -Recurse -Force }
Copy-Item -Path (Join-Path $PSScriptRoot 'DriverUpdater.ps1') -Destination $target -Force
Copy-Item -Path (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $target -Force
Copy-Item -Path (Join-Path $PSScriptRoot 'src') -Destination $target -Recurse -Force
Get-ChildItem -Path $target -Recurse -File | Unblock-File   # retire le marquage "téléchargé depuis Internet"

Write-Host '2/5 Création du dossier de données (journaux)' -ForegroundColor Cyan
Initialize-AppFolder

Write-Host "3/5 Création de la tâche planifiée '$taskName' pour $user" -ForegroundColor Cyan
$mainScript = Join-Path $target 'DriverUpdater.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$mainScript`" -Startup"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT2M'    # attend 2 minutes après l'ouverture de session (le temps d'avoir Internet)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description 'Driver : recherche des mises à jour de pilotes à l''ouverture de session' -Force | Out-Null

Write-Host '4/5 Création du raccourci sur le Bureau' -ForegroundColor Cyan
# GetFolderPath donne le VRAI chemin du Bureau (il peut être déplacé, ex. OneDrive)
$desktop = [Environment]::GetFolderPath('Desktop')
$wsh  = New-Object -ComObject WScript.Shell
$lnk  = $wsh.CreateShortcut((Join-Path $desktop 'Driver.lnk'))
$lnk.TargetPath  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnk.Arguments   = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$mainScript`""
$lnk.Description = 'Mise à jour des pilotes'
$lnk.IconLocation = (Join-Path $target 'src\driver.ico') + ',0'
$lnk.Save()

Write-Host '5/5 Activation de la protection système (points de restauration) sur C:' -ForegroundColor Cyan
try { Enable-ComputerRestore -Drive "$env:SystemDrive\" } catch { Write-Warning "Impossible d'activer la protection système : $($_.Exception.Message)" }

Write-Host "`nInstallation terminée." -ForegroundColor Green
Write-Host "Raccourci : $desktop\Driver.lnk"
Write-Host "Journaux  : $($script:LogDir)"
exit 0
