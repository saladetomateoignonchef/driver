# =============================================================================
#  Core.ps1 - Orchestration : recherche et installation via les fournisseurs
# =============================================================================

function Find-DriverUpdate {
    <# Interroge tous les fournisseurs et renvoie la liste des mises à jour disponibles. #>
    $inventory = @(Get-DeviceInventory)
    Write-Log "Inventaire : $($inventory.Count) périphérique(s) avec pilote"

    $results    = New-Object System.Collections.Generic.List[object]
    $nvidiaDone = $false

    # 1) Fournisseur NVIDIA (prioritaire pour la carte graphique)
    try {
        foreach ($c in @(Get-NvidiaUpdate -Inventory $inventory)) { if ($c) { $results.Add($c) } }
        $nvidiaDone = $true
    } catch {
        Write-Log "NVIDIA : erreur lors de la recherche : $($_.Exception.Message)" 'ERREUR'
    }

    # 2) Windows Update (filet de sécurité pour tout le reste)
    try {
        foreach ($c in @(Get-WindowsUpdateDriverUpdate -Inventory $inventory)) {
            if (-not $c) { continue }
            # Si le site NVIDIA a répondu, on ignore le pilote graphique NVIDIA de
            # Windows Update (souvent plus ancien) pour éviter un doublon.
            if ($nvidiaDone -and $c.DriverClass -eq 'Display' -and $c.Manufacturer -match 'NVIDIA') { continue }
            $results.Add($c)
        }
    } catch {
        Write-Log "Windows Update : erreur lors de la recherche : $($_.Exception.Message)" 'ERREUR'
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

function Install-DriverUpdate {
    <# Installe les mises à jour validées par l'utilisateur. Renvoie un résultat par pilote. #>
    param(
        [Parameter(Mandatory)][object[]]$Candidate,
        [switch]$CreateRestorePoint
    )

    if ($CreateRestorePoint) { [void](New-DriverRestorePoint) }

    $nvidia = @($Candidate | Where-Object { $_.Source -eq 'NVIDIA' })
    $wu     = @($Candidate | Where-Object { $_.Source -eq 'Windows Update' })

    foreach ($c in $nvidia) {
        try {
            $r = Install-NvidiaDriver -Url $c.Key -Version $c.NewVersion
            [pscustomobject]@{ Device = $c.Device; Success = $r.Success; RebootRequired = $r.RebootRequired; Message = $r.Message }
        } catch {
            Write-Log "NVIDIA : échec de l'installation : $($_.Exception.Message)" 'ERREUR'
            [pscustomobject]@{ Device = $c.Device; Success = $false; RebootRequired = $false; Message = $_.Exception.Message }
        }
    }

    if ($wu.Count -gt 0) {
        try {
            foreach ($r in @(Install-WindowsUpdateDriver -UpdateId ($wu | ForEach-Object { $_.Key }))) {
                Write-Log "Windows Update : $($r.Title) -> $($r.Message)"
                [pscustomobject]@{ Device = $r.Title; Success = $r.Success; RebootRequired = $r.RebootRequired; Message = $r.Message }
            }
        } catch {
            Write-Log "Windows Update : échec de l'installation : $($_.Exception.Message)" 'ERREUR'
            [pscustomobject]@{ Device = 'Windows Update'; Success = $false; RebootRequired = $false; Message = $_.Exception.Message }
        }
    }
}
