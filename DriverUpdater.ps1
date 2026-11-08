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
if (-not $created) {
    Write-Log 'Une instance est déjà lancée, arrêt.' 'WARN'
    if (-not $Startup) {
        # Lancement manuel : on prévient l'utilisateur au lieu de quitter sans rien dire
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show(
            "Driver est déjà en cours d'exécution (une vérification tourne peut-être en arrière-plan).`r`nRéessaie dans 2 minutes.",
            'Driver', 'OK', 'Information')
    }
    exit
}

$script:RestartRequested = $false
try {
    Clear-OldFiles -Days 30          # journaux et téléchargements de plus de 30 jours
    $settings = Get-AppSettings

    if ($Startup) {
        Write-Log '===== Lancement automatique (ouverture de session) ====='
        if (-not (Test-CheckDue -Settings $settings)) {
            Write-Log "Vérification non due (fréquence : $($settings.CheckFrequency), dernière : $($settings.LastCheck))"
            exit 0
        }
        $results = @(Find-DriverUpdate)
        $settings.LastCheck = (Get-Date).ToString('s')
        Save-AppSettings -Settings $settings

        $visible = @($results | Where-Object { -not (Test-UpdateIgnored -Candidate $_ -Settings $settings) })
        if ($visible.Count -eq 0) {
            Write-Log 'Aucune mise à jour (hors mises à jour ignorées) : rien à afficher.'
            exit 0
        }
        if ($settings.Notifications) {
            $summary = ($visible | Select-Object -First 3 | ForEach-Object { "$($_.Device) : $($_.NewVersion)" }) -join "`n"
            if (-not (Show-UpdateNotification -Count $visible.Count -Summary $summary)) { exit 0 }
        }
        Show-MainWindow -InitialResults $results
    } else {
        Write-Log "===== Lancement manuel (Driver $($script:AppVersion)) ====="
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

# --- Après une mise à jour de Driver : on relance la nouvelle version installée ---
if ($script:RestartRequested) {
    $installed = Join-Path $env:ProgramFiles 'DriverUpdater\DriverUpdater.ps1'
    Write-Log "Redémarrage de Driver après mise à jour : $installed"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$installed`"")
}
