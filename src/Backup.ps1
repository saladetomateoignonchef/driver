# =============================================================================
#  Backup.ps1 - Sauvegarde du pilote actuel avant installation + retour arrière
#
#  - Sauvegarde : "pnputil /export-driver oemXX.inf <dossier>" copie le paquet du
#    pilote installé (depuis le magasin de pilotes de Windows).
#  - Limite : on ne garde que les N dernières sauvegardes PAR pilote (paramètre
#    BackupKeep, 2 par défaut) ; les plus anciennes sont supprimées.
#  - Retour arrière : Windows refuse normalement d'installer une version plus
#    ancienne. On utilise donc l'API UpdateDriverForPlugAndPlayDevices avec
#    l'option INSTALLFLAG_FORCE, qui force le pilote choisi sur le périphérique.
# =============================================================================

function Get-SafeName([string]$Text) {
    $safe = ($Text -replace '[\\/:*?"<>|]', '_' -replace '\s+', ' ').Trim()
    if ($safe.Length -gt 60) { $safe = $safe.Substring(0, 60).Trim() }
    return $safe
}

function Get-HardwareIdVariant {
    <#
        Du plus précis au plus général, les identifiants qu'un .inf peut utiliser :
        PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA&REV_A1
        PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA
        PCI\VEN_10DE&DEV_2504&REV_A1
        PCI\VEN_10DE&DEV_2504
    #>
    param([Parameter(Mandatory)][string]$HardwareId)
    $parts = $HardwareId -split '&'
    $list  = New-Object System.Collections.Generic.List[string]
    for ($k = $parts.Count; $k -ge 2; $k--) { $list.Add(($parts[0..($k - 1)] -join '&')) }
    $noSubsys = @($parts | Where-Object { $_ -notmatch '^SUBSYS_' })
    if ($noSubsys.Count -ne $parts.Count -and $noSubsys.Count -ge 2) {
        for ($k = $noSubsys.Count; $k -ge 2; $k--) { $list.Add(($noSubsys[0..($k - 1)] -join '&')) }
    }
    if ($parts.Count -eq 1) { $list.Add($HardwareId) }
    # Tri : le plus de critères d'abord ; à égalité, celui avec SUBSYS (spécifique à la carte) d'abord
    return @($list | Select-Object -Unique | Sort-Object -Property `
        @{ Expression = { ($_ -split '&').Count }; Descending = $true },
        @{ Expression = { $_ -match 'SUBSYS_' }; Descending = $true })
}

function Backup-DeviceDriver {
    <# Sauvegarde le pilote actuellement installé pour ce périphérique (objet de l'inventaire). #>
    param([Parameter(Mandatory)][object]$Device, [int]$Keep = 2)

    if (-not ($Device.InfName -match '^oem\d+\.inf$')) {
        Write-Log "Sauvegarde : $($Device.Name) utilise un pilote intégré à Windows ($($Device.InfName)), rien à sauvegarder"
        return $null
    }
    $folder = Join-Path $script:BackupDir (Get-SafeName $Device.Name)

    # Déjà sauvegardé dans cette version ? Inutile de recommencer.
    $existing = @(Get-DriverBackup | Where-Object { $_.Device -eq $Device.Name -and $_.Version -eq $Device.DriverVersion })
    if ($existing.Count -gt 0) {
        Write-Log "Sauvegarde : $($Device.Name) $($Device.DriverVersion) déjà sauvegardé"
        return $existing[0]
    }

    $dest = Join-Path $folder ('{0}_{1:yyyyMMdd-HHmmss}' -f (Get-SafeName $Device.DriverVersion), (Get-Date))
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Set-TaskProgress -Stage (T 'StageBackup' $Device.Name) -Detail (T 'StageVersion' $Device.DriverVersion)
    Write-Log "Sauvegarde : export de $($Device.InfName) ($($Device.Name) $($Device.DriverVersion))"

    $pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
    $out  = & $pnputil /export-driver $Device.InfName $dest 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Log "Sauvegarde impossible (code $code) : $out" 'WARN'
        Remove-Item -Path $dest -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    }

    $sizeMB = [math]::Round(((Get-ChildItem -Path $dest -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
    $meta = [pscustomobject]@{
        Device     = $Device.Name
        HardwareId = $Device.HardwareId
        Version    = $Device.DriverVersion
        InfName    = $Device.InfName
        Date       = (Get-Date).ToString('s')
        SizeMB     = $sizeMB
    }
    $meta | ConvertTo-Json | Set-Content -Path (Join-Path $dest 'backup.json') -Encoding UTF8
    Write-Log "Sauvegarde : $($Device.Name) $($Device.DriverVersion) sauvegardé ($sizeMB Mo)"

    Limit-DeviceBackup -Folder $folder -Keep $Keep
    return $meta
}

function Limit-DeviceBackup {
    <# Ne garde que les $Keep sauvegardes les plus récentes de ce pilote. #>
    param([Parameter(Mandatory)][string]$Folder, [int]$Keep = 2)
    if ($Keep -lt 1) { $Keep = 1 }
    $old = @(Get-ChildItem -Path $Folder -Directory -ErrorAction SilentlyContinue |
        Sort-Object CreationTime -Descending | Select-Object -Skip $Keep)
    foreach ($dir in $old) {
        Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Sauvegarde : ancienne sauvegarde supprimée (limite de $Keep) : $($dir.FullName)"
    }
}

function Limit-AllBackups {
    <# Applique la limite à tous les pilotes (après un changement de paramètre). #>
    param([int]$Keep = 2)
    foreach ($folder in @(Get-ChildItem -Path $script:BackupDir -Directory -ErrorAction SilentlyContinue)) {
        Limit-DeviceBackup -Folder $folder.FullName -Keep $Keep
    }
}

function Get-DriverBackup {
    <# Liste des sauvegardes, la plus récente d'abord. #>
    foreach ($file in @(Get-ChildItem -Path $script:BackupDir -Recurse -Filter 'backup.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $m = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            [pscustomobject]@{
                Path       = $file.DirectoryName
                Device     = $m.Device
                HardwareId = $m.HardwareId
                Version    = $m.Version
                Date       = [datetime]$m.Date
                SizeMB     = [double]$m.SizeMB
            }
        } catch { }
    }
}

function Get-BackupTotalSizeMB {
    $sum = (Get-ChildItem -Path $script:BackupDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if (-not $sum) { return 0 }
    return [math]::Round($sum / 1MB)
}

function Remove-DriverBackup {
    param([Parameter(Mandatory)][string]$Path)
    # Sécurité : on ne supprime que dans le dossier des sauvegardes
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith([IO.Path]::GetFullPath($script:BackupDir), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Chemin refusé : $Path"
    }
    Remove-Item -Path $full -Recurse -Force
    $parent = Split-Path $full -Parent
    if (-not (Get-ChildItem -Path $parent -Force -ErrorAction SilentlyContinue)) { Remove-Item -Path $parent -Force -ErrorAction SilentlyContinue }
    Write-Log "Sauvegarde supprimée : $full"
}

function Clear-AllBackups {
    Get-ChildItem -Path $script:BackupDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log 'Toutes les sauvegardes de pilotes ont été supprimées'
}

function Initialize-NewDevApi {
    if ('DriverNewDev' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DriverNewDev {
    public const uint INSTALLFLAG_FORCE = 0x00000001;
    [DllImport("newdev.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool UpdateDriverForPlugAndPlayDevices(IntPtr hwndParent, string hardwareId,
        string fullInfPath, uint installFlags, out bool rebootRequired);
}
'@
}

function Restore-DriverBackup {
    <# Réinstalle (de force) la version sauvegardée sur le périphérique. #>
    param([Parameter(Mandatory)][string]$Path, [switch]$CreateRestorePoint)

    $meta = Get-Content -Path (Join-Path $Path 'backup.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Log "Retour arrière : $($meta.Device) vers la version $($meta.Version)"
    if ($CreateRestorePoint) { [void](New-DriverRestorePoint) }
    Set-TaskProgress -Stage (T 'StageRestore' $meta.Device) -Detail (T 'StageVersion' $meta.Version)

    # Trouver le .inf de la sauvegarde qui cite un identifiant du périphérique
    $variants = Get-HardwareIdVariant -HardwareId $meta.HardwareId
    $infFile = $null; $hwid = $null
    foreach ($inf in @(Get-ChildItem -Path $Path -Recurse -Filter '*.inf' -File)) {
        $text = Read-InfText -Path $inf.FullName
        foreach ($v in $variants) {
            if ($text.IndexOf($v, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $infFile = $inf.FullName; $hwid = $v; break }
        }
        if ($infFile) { break }
    }

    $current = (Get-DeviceInventory | Where-Object { $_.Name -eq $meta.Device } | Select-Object -First 1).DriverVersion
    if (-not $infFile) {
        $result = [pscustomobject]@{ Device = $meta.Device; Success = $false; RebootRequired = $false
                                     Message = (T 'MsgRestoreNoInf' $meta.HardwareId) }
    } else {
        Initialize-NewDevApi
        $reboot = $false
        Write-Log "Retour arrière : installation forcée de $infFile pour $hwid"
        $ok = [DriverNewDev]::UpdateDriverForPlugAndPlayDevices([IntPtr]::Zero, $hwid, $infFile, [DriverNewDev]::INSTALLFLAG_FORCE, [ref]$reboot)
        if ($ok) {
            $result = [pscustomobject]@{ Device = $meta.Device; Success = $true; RebootRequired = [bool]$reboot
                                         Message = (T 'MsgRestoreOk' $meta.Version) }
        } else {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $result = [pscustomobject]@{ Device = $meta.Device; Success = $false; RebootRequired = $false
                                         Message = (T 'MsgRestoreFail' ('0x{0:X8}' -f $err)) }
        }
    }
    Write-Log "Retour arrière : $($result.Message)"
    Add-HistoryEntry -Type 'Retour arrière' -Device $meta.Device -Source 'Sauvegarde' -OldVersion $current `
        -NewVersion $meta.Version -Success $result.Success -Message $result.Message
    return $result
}
