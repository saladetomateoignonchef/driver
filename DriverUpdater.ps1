#Requires -Version 5.1
<#
.SYNOPSIS
    Driver - mise à jour des pilotes matériels avec validation par l'utilisateur.

.DESCRIPTION
    Inventorie le matériel (WMI), interroge le site NVIDIA pour la carte graphique
    et Windows Update pour les autres pilotes, puis affiche une fenêtre où
    l'utilisateur coche les mises à jour à installer.

.PARAMETER Startup
    Mode "démarrage" (utilisé par la tâche planifiée) : la recherche se fait en
    silence et la fenêtre ne s'ouvre QUE si des mises à jour sont disponibles.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\DriverUpdater.ps1
#>
[CmdletBinding()]
param([switch]$Startup)

$script:AppRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'src\Loader.ps1')
. (Join-Path $PSScriptRoot 'src\Gui.ps1')

# --- Élévation des droits : installer un pilote nécessite d'être administrateur ---
if (-not (Test-IsAdmin)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($Startup) { $argList += '-Startup' }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit
}

Initialize-AppFolder

# --- Une seule instance à la fois ---
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\DriverUpdater', [ref]$created)
if (-not $created) { Write-Log 'Une instance est déjà lancée, arrêt.' 'WARN'; exit }

try {
    if ($Startup) {
        Write-Log '===== Lancement automatique (ouverture de session) ====='
        $results = @(Find-DriverUpdate)
        if ($results.Count -eq 0) {
            Write-Log 'Aucune mise à jour : la fenêtre ne s''ouvre pas.'
            exit 0
        }
        Show-MainWindow -InitialResults $results
    } else {
        Write-Log '===== Lancement manuel ====='
        Show-MainWindow -AutoSearch
    }
}
catch {
    Write-Log "Erreur fatale : $($_.Exception.Message)" 'ERREUR'
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show("Erreur : $($_.Exception.Message)", 'Driver', 'OK', 'Error')
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
