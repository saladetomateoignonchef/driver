# =============================================================================
#  Providers/WindowsUpdate.ps1 - Pilotes proposés par Windows Update
#
#  Utilise l'API COM "Windows Update Agent" (Microsoft.Update.Session), la même
#  que celle utilisée par Paramètres > Windows Update > Mises à jour facultatives.
#  Elle couvre la plupart des pilotes : chipset Intel, audio et réseau Realtek,
#  Bluetooth, etc.
# =============================================================================

$script:WuServerSelection = 2   # 2 = ssWindowsUpdate (serveurs publics Microsoft)

function New-WuSearcher {
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.ServerSelection = $script:WuServerSelection
    return @{ Session = $session; Searcher = $searcher }
}

function Get-WindowsUpdateDriverUpdate {
    param([Parameter(Mandatory)][object[]]$Inventory)

    Write-Log 'Windows Update : recherche des pilotes disponibles...'
    $wu     = New-WuSearcher
    $result = $wu.Searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    Write-Log "Windows Update : $($result.Updates.Count) pilote(s) proposé(s)"

    foreach ($u in $result.Updates) {
        $device  = Find-InventoryDevice -Inventory $Inventory -HardwareId $u.DriverHardwareID
        $name    = if ($device) { $device.Name } else { $u.DriverModel }
        $current = if ($device) { $device.DriverVersion } else { '?' }

        New-UpdateCandidate -Source 'Windows Update' -Device $name -CurrentVersion $current `
            -NewVersion (Get-VersionFromText -Text $u.Title) `
            -SizeMB ([math]::Round($u.MaxDownloadSize / 1MB, 1)) `
            -Key $u.Identity.UpdateID -Title $u.Title |
            Add-Member -NotePropertyName DriverClass -NotePropertyValue $u.DriverClass -PassThru |
            Add-Member -NotePropertyName Manufacturer -NotePropertyValue $u.DriverManufacturer -PassThru
    }
}

function Install-WindowsUpdateDriver {
    param([Parameter(Mandatory)][string[]]$UpdateId)

    $wu   = New-WuSearcher
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($id in $UpdateId) {
        $found = $wu.Searcher.Search("UpdateID='$id'")
        foreach ($u in $found.Updates) {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$coll.Add($u)
        }
    }
    if ($coll.Count -eq 0) { throw 'Mises à jour introuvables (déjà installées ?)' }

    Write-Log "Windows Update : téléchargement de $($coll.Count) pilote(s)"
    $downloader = $wu.Session.CreateUpdateDownloader()
    $downloader.Updates = $coll
    [void]$downloader.Download()

    Write-Log 'Windows Update : installation...'
    $installer = $wu.Session.CreateUpdateInstaller()
    $installer.Updates = $coll
    $res = $installer.Install()

    # ResultCode : 2 = réussi, 3 = réussi avec erreurs, 4 = échec, 5 = annulé
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $r = $res.GetUpdateResult($i)
        [pscustomobject]@{
            Title          = $coll.Item($i).Title
            Success        = ($r.ResultCode -eq 2 -or $r.ResultCode -eq 3)
            RebootRequired = [bool]$r.RebootRequired
            Message        = "Code résultat $($r.ResultCode) (HRESULT $($r.HResult))"
        }
    }
}
