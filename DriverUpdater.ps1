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

function Show-TopMessage([string]$Text, [string]$Icon = 'Information') {
    <# Message toujours au premier plan (Driver se lance en mode caché : un message normal pouvait rester derrière les fenêtres). #>
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($Text, 'Driver', 'OK', $Icon, 'Button1', 'DefaultDesktopOnly')
}

# --- Chargement des modules : si des fichiers manquent (installation abîmée), on le dit clairement ---
try {
    $required = @('src\Loader.ps1', 'src\Gui.ps1', 'src\MainWindow.xaml', 'src\lang\fr.json')
    $missing  = @($required | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) })
    if ($missing.Count) { throw "Fichiers manquants : $($missing -join ', ')" }
    . (Join-Path $PSScriptRoot 'src\Loader.ps1')
    . (Join-Path $PSScriptRoot 'src\Gui.ps1')
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(
        "Driver ne peut pas démarrer : son installation est incomplète ou abîmée.`r`n`r`n$($_.Exception.Message)`r`n`r`n" +
        "Pour réparer : télécharge Installer-Driver.cmd sur https://github.com/saladetomateoignonchef/driver/releases/latest et double-clique dessus. " +
        "Tes réglages et sauvegardes sont conservés.`r`n`r`n" +
        "Driver cannot start: its installation is incomplete. Run Installer-Driver.cmd from the GitHub releases page to repair it.",
        'Driver', 'OK', 'Error')
    exit 1
}

# --- Élévation des droits : installer un pilote nécessite d'être administrateur ---
if (-not (Test-IsAdmin)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($Startup) { $argList += '-Startup' }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -ErrorAction Stop
    } catch {
        # Demande d'autorisation refusée (« Non ») : on quitte sans rien dire. Toute autre erreur est affichée.
        $native = $_.Exception.InnerException
        if (-not ($native -is [System.ComponentModel.Win32Exception] -and $native.NativeErrorCode -eq 1223) -and $_.Exception.Message -notmatch 'annul|cancel') {
            Show-TopMessage "Driver n'a pas pu se relancer en administrateur :`r`n$($_.Exception.Message)" 'Error'
        }
    }
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
        Show-TopMessage (T 'AlreadyRunning')
    }
    exit
}

$script:RestartRequested = $false
$script:MutexOwned = $true
try {
    Clear-OldFiles -Days 30          # journaux et téléchargements de plus de 30 jours
    $settings = Get-AppSettings
    # Premier lancement : analyse complète du matériel, enregistrée comme configuration de référence
    $script:ProfileCreated = Initialize-HardwareProfile

    if ($Startup) {
        Write-Log '===== Lancement automatique (ouverture de session) ====='
        if (-not (Test-CheckDue -Settings $settings)) {
            Write-Log "Vérification non due (fréquence : $($settings.CheckFrequency), dernière : $($settings.LastCheck))"
            exit 0
        }
        # Recherche basée sur la configuration enregistrée ; le nouveau matériel est signalé à part
        $watched = Get-WatchedInventory
        $newHw   = @($watched.NewHardware)
        $results = @(Find-DriverUpdate -Inventory $watched.Inventory -ExcludeHardwareId @($newHw | ForEach-Object { $_.HardwareId }))
        $settings.LastCheck = (Get-Date).ToString('s')
        Save-AppSettings -Settings $settings

        $visible = @($results | Where-Object { -not (Test-UpdateIgnored -Candidate $_ -Settings $settings) })
        if ($visible.Count -eq 0 -and $newHw.Count -eq 0) {
            Write-Log 'Aucune mise à jour (hors mises à jour ignorées) et aucun nouveau matériel : rien à afficher.'
            exit 0
        }
        if ($settings.Notifications) {
            $lines = @($visible | Select-Object -First 3 | ForEach-Object { "$($_.Device) : $($_.NewVersion)" })
            if ($newHw.Count) { $lines += (T 'NotifyNewHw' $newHw.Count) }
            $title = if ($visible.Count) { T 'NotifyTitle' $visible.Count } else { T 'NotifyNewHwTitle' }
            # Pendant l'attente de la notification (jusqu'à 1 h), Driver ne bloque pas une ouverture normale
            $mutex.ReleaseMutex(); $script:MutexOwned = $false
            $open = Show-UpdateNotification -Count $visible.Count -Summary ($lines -join "`n") -Title $title
            if (-not $open) { exit 0 }
            $script:MutexOwned = $mutex.WaitOne(0)
            if (-not $script:MutexOwned) { Write-Log 'Driver a été ouvert entre-temps : la notification se ferme.'; exit 0 }
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
    [void][System.Windows.Forms.MessageBox]::Show("$(T 'Error') : $($_.Exception.Message)", 'Driver', 'OK', 'Error')
}
finally {
    if ($script:MutexOwned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

# --- Après une mise à jour de Driver : on relance la nouvelle version installée ---
if ($script:RestartRequested) {
    $installed = Join-Path $env:ProgramFiles 'DriverUpdater\DriverUpdater.ps1'
    Write-Log "Redémarrage de Driver après mise à jour : $installed"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$installed`"")
}
