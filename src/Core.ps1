# =============================================================================
#  Core.ps1 - Orchestration : recherche et installation via les fournisseurs
# =============================================================================

function Find-DriverUpdate {
    <# Interroge tous les fournisseurs et renvoie la liste des mises à jour disponibles. #>
    param([object[]]$Inventory, [string[]]$ExcludeHardwareId)
    if (-not $Inventory) {
        # Recherche basée sur la configuration enregistrée (le nouveau matériel non validé est exclu)
        $watched = Get-WatchedInventory
        $Inventory = $watched.Inventory
        $ExcludeHardwareId = @($watched.NewHardware | ForEach-Object { $_.HardwareId })
    }
    $inventory = @($Inventory)
    Write-Log "Inventaire : $($inventory.Count) périphérique(s) avec pilote"

    $results    = New-Object System.Collections.Generic.List[object]
    $nvidiaDone = $false

    $settings = Get-AppSettings

    # 1) Fournisseur NVIDIA (prioritaire pour la carte graphique)
    if (-not $settings.ProviderNvidia) {
        Write-Log 'NVIDIA : fournisseur désactivé dans les paramètres'
    } else {
    Set-TaskProgress -Stage (T 'StageNvidia')
    try {
        foreach ($c in @(Get-NvidiaUpdate -Inventory $inventory)) { if ($c) { $results.Add($c) } }
        $nvidiaDone = $true
    } catch {
        Write-Log "NVIDIA : erreur lors de la recherche : $($_.Exception.Message)" 'ERREUR'
    }
    }

    # 2) Windows Update (filet de sécurité pour tout le reste, dont AMD et Intel)
    if (-not $settings.ProviderWindowsUpdate) {
        Write-Log 'Windows Update : fournisseur désactivé dans les paramètres'
    } else {
    Set-TaskProgress -Stage (T 'StageWindowsUpdate') -Detail (T 'StageWindowsUpdateDetail')
    try {
        foreach ($c in @(Get-WindowsUpdateDriverUpdate -Inventory $inventory)) {
            if (-not $c) { continue }
            # Si le site NVIDIA a répondu, on ignore le pilote graphique NVIDIA de
            # Windows Update (souvent plus ancien) pour éviter un doublon.
            if ($nvidiaDone -and $c.DriverClass -eq 'Display' -and $c.Manufacturer -match 'NVIDIA') { continue }
            # Matériel ajouté mais pas encore enregistré dans la configuration : ignoré
            if ($c.HardwareId -and @($ExcludeHardwareId | Where-Object { $_ -like "$($c.HardwareId)*" }).Count) { continue }
            $results.Add($c)
        }
    } catch {
        Write-Log "Windows Update : erreur lors de la recherche : $($_.Exception.Message)" 'ERREUR'
    }
    }

    Write-Log "Recherche terminée : $($results.Count) mise(s) à jour disponible(s)"
    return $results.ToArray()
}

function New-DriverRestorePoint {
    try {
        Checkpoint-Computer -Description 'Driver - avant mise a jour des pilotes' `
            -RestorePointType 'DEVICE_DRIVER_INSTALL' -ErrorAction Stop -WarningAction SilentlyContinue
        Write-Log 'Point de restauration créé'
        return $true
    } catch {
        Write-Log "Point de restauration impossible : $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Backup-BeforeInstall {
    <# Sauvegarde le pilote actuel des périphériques concernés (selon la limite des paramètres). #>
    param([string[]]$DeviceName, [object[]]$Inventory)
    $keep = [int](Get-AppSettings).BackupKeep
    foreach ($name in @($DeviceName | Where-Object { $_ } | Select-Object -Unique)) {
        $dev = $Inventory | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $dev) { Write-Log "Sauvegarde : périphérique '$name' introuvable dans l'inventaire" 'WARN'; continue }
        try { [void](Backup-DeviceDriver -Device $dev -Keep $keep) }
        catch { Write-Log "Sauvegarde de $name impossible : $($_.Exception.Message)" 'WARN' }
    }
}

function Install-DriverUpdate {
    <#
        Installe les mises à jour validées par l'utilisateur. Pour chaque pilote :
        sauvegarde de la version actuelle -> installation -> historique.
        Renvoie un résultat par pilote.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Candidate,
        [switch]$CreateRestorePoint
    )

    if ($CreateRestorePoint) {
        Set-TaskProgress -Stage (T 'StageRestorePoint')
        [void](New-DriverRestorePoint)
    }
    $inventory = @(Get-DeviceInventory)
    Backup-BeforeInstall -DeviceName ($Candidate | ForEach-Object { $_.Device }) -Inventory $inventory

    $nvidia = @($Candidate | Where-Object { $_.Source -eq 'NVIDIA' })
    $wu     = @($Candidate | Where-Object { $_.Source -eq 'Windows Update' })

    foreach ($c in $nvidia) {
        try {
            $r = Install-NvidiaDriver -Url $c.Key -Version $c.NewVersion
            $res = [pscustomobject]@{ Device = $c.Device; Success = $r.Success; RebootRequired = $r.RebootRequired; Message = $r.Message }
        } catch {
            Write-Log "NVIDIA : échec de l'installation : $($_.Exception.Message)" 'ERREUR'
            $res = [pscustomobject]@{ Device = $c.Device; Success = $false; RebootRequired = $false; Message = $_.Exception.Message }
        }
        Add-HistoryEntry -Type 'Installation' -Device $c.Device -Source 'NVIDIA' -OldVersion $c.CurrentVersion `
            -NewVersion $c.NewVersion -Success $res.Success -Message $res.Message
        $res
    }

    if ($wu.Count -gt 0) {
        Set-TaskProgress -Stage (T 'StageWuInstall' $wu.Count)
        try {
            foreach ($r in @(Install-WindowsUpdateDriver -UpdateId ($wu | ForEach-Object { $_.Key }))) {
                Write-Log "Windows Update : $($r.Title) -> $($r.Message)"
                $c = $wu | Where-Object { $_.Title -eq $r.Title } | Select-Object -First 1
                $device = if ($c) { $c.Device } else { $r.Title }
                Add-HistoryEntry -Type 'Installation' -Device $device -Source 'Windows Update' -OldVersion $c.CurrentVersion `
                    -NewVersion $c.NewVersion -Success $r.Success -Message $r.Message
                [pscustomobject]@{ Device = $device; Success = $r.Success; RebootRequired = $r.RebootRequired; Message = $r.Message }
            }
        } catch {
            Write-Log "Windows Update : échec de l'installation : $($_.Exception.Message)" 'ERREUR'
            foreach ($c in $wu) {
                Add-HistoryEntry -Type 'Installation' -Device $c.Device -Source 'Windows Update' -OldVersion $c.CurrentVersion `
                    -NewVersion $c.NewVersion -Success $false -Message $_.Exception.Message
            }
            [pscustomobject]@{ Device = 'Windows Update'; Success = $false; RebootRequired = $false; Message = $_.Exception.Message }
        }
    }
    Clear-TaskProgress
}
