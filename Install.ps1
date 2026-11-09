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
param(
    [switch]$Silent,   # -Silent : utilisé par la mise à jour automatique de Driver
    [switch]$NoTask    # -NoTask : pas de tâche planifiée (aucune recherche automatique à l'ouverture de session)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Common.ps1')

if (-not (Test-IsAdmin)) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    exit
}

$target   = Join-Path $env:ProgramFiles 'DriverUpdater'
$taskName = 'DriverUpdater'
$user     = "$env:USERDOMAIN\$env:USERNAME"

function Copy-AppFile {
    <#
        Copie fichier par fichier, sans supprimer le dossier d'abord : pendant une mise à jour
        automatique, Driver est ouvert et Windows peut garder certains fichiers verrouillés
        (ex. l'icône). Un fichier verrouillé identique à la nouvelle version est ignoré ;
        sinon on réessaie 3 fois avant de signaler l'erreur.
    #>
    param([string]$Source, [string]$Destination)
    $dir = Split-Path $Destination -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    for ($i = 1; $i -le 3; $i++) {
        try { Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop; return $null }
        catch {
            if ((Test-Path $Destination) -and ((Get-FileHash $Source).Hash -eq (Get-FileHash $Destination).Hash)) { return $null }
            if ($i -lt 3) { Start-Sleep -Seconds 1 } else { return "$Destination : $($_.Exception.Message)" }
        }
    }
}

Write-Host "1/5 Copie des fichiers dans $target" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $target -Force | Out-Null
$copyErrors = New-Object System.Collections.Generic.List[string]
$sources = @(
    Get-Item (Join-Path $PSScriptRoot 'DriverUpdater.ps1'), (Join-Path $PSScriptRoot 'Uninstall.ps1')
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'src') -Recurse -File
)
$expected = @{}
foreach ($file in $sources) {
    $relative = $file.FullName.Substring($PSScriptRoot.TrimEnd('\').Length + 1)
    $dest = Join-Path $target $relative
    $expected[$dest.ToLower()] = $true
    $err = Copy-AppFile -Source $file.FullName -Destination $dest
    if ($err) { $copyErrors.Add($err) }
}
# Fichiers d'anciennes versions devenus inutiles (au mieux : un fichier verrouillé reste en place)
Get-ChildItem -Path (Join-Path $target 'src') -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { -not $expected[$_.FullName.ToLower()] } |
    Remove-Item -Force -ErrorAction SilentlyContinue
if ($copyErrors.Count) {
    $msg = "Copie impossible de $($copyErrors.Count) fichier(s) :`n" + ($copyErrors -join "`n")
    try { Write-Log "Installation : $msg" 'ERREUR' } catch { }
    throw $msg
}
Get-ChildItem -Path $target -Recurse -File | Unblock-File   # retire le marquage "téléchargé depuis Internet\"

Write-Host '2/5 Création du dossier de données (journaux)' -ForegroundColor Cyan
Initialize-AppFolder

# Choix « sans tâche » : demandé maintenant (-NoTask) ou mémorisé lors d'une installation précédente,
# pour qu'une mise à jour automatique ne recrée pas la tâche.
$appSettings = Get-AppSettings
if ($NoTask -and -not $appSettings.NoStartupTask) {
    $appSettings.NoStartupTask = $true
    try { Save-AppSettings -Settings $appSettings } catch { Write-Warning "Choix -NoTask non mémorisé : $($_.Exception.Message)" }
}
if ($appSettings.NoStartupTask) {
    Write-Host "3/5 Tâche planifiée : non créée (option -NoTask). La recherche se fait en ouvrant Driver." -ForegroundColor Cyan
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
} else {
Write-Host "3/5 Création de la tâche planifiée '$taskName' pour $user" -ForegroundColor Cyan
$mainScript = Join-Path $target 'DriverUpdater.ps1'
Register-DriverStartupTask -MainScript $mainScript   # garde la tâche désactivée si l'utilisateur l'a choisi
}

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
