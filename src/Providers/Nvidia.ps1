# =============================================================================
#  Providers/Nvidia.ps1 - Interrogation du site NVIDIA (pilotes GeForce)
#
#  Fonctionnement (même principe que le formulaire de nvidia.fr/drivers) :
#   1. lookupValueSearch.aspx?TypeID=3 : liste XML des cartes graphiques
#      -> on y trouve, pour le nom de la carte, son pfid (produit) et psid (série)
#   2. AjaxDriverService.php?func=DriverManualLookup : renvoie en JSON le dernier
#      pilote pour ce couple psid/pfid + l'OS (osID 57 = Windows 10/11 64 bits)
#  Attention : ces API ne sont pas documentées officiellement par NVIDIA.
# =============================================================================

$script:NvidiaLookupUrl = 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3'
$script:NvidiaDriverUrl = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php'
$script:NvidiaOsId      = 57      # Windows 10 / 11 64 bits
$script:NvidiaVendorId  = '10DE'  # identifiant PCI de NVIDIA

function Find-NvidiaProductId {
    param([Parameter(Mandatory)][string]$GpuName)

    $wanted = ($GpuName -replace '^NVIDIA\s+', '').Trim()
    $xml = Invoke-RestMethod -Uri $script:NvidiaLookupUrl -UseBasicParsing -UserAgent $script:UserAgent -TimeoutSec 30
    if ($xml -is [string]) { $xml = [xml]$xml }

    $match = $xml.LookupValueSearch.LookupValues.LookupValue |
        Where-Object { ($_.Name -replace '^NVIDIA\s+', '').Trim() -eq $wanted } |
        Select-Object -First 1

    if (-not $match) { return $null }
    [pscustomobject]@{ Name = $match.Name; Psid = $match.ParentID; Pfid = $match.Value }
}

function Get-NvidiaLatestDriver {
    param([Parameter(Mandatory)][string]$Psid, [Parameter(Mandatory)][string]$Pfid)

    $query = [ordered]@{
        func = 'DriverManualLookup'; psid = $Psid; pfid = $Pfid; osID = $script:NvidiaOsId
        languageCode = 1033; beta = 0; isWHQL = 1; dltype = -1; dch = 1; upCRD = 0
        qnf = 0; sort1 = 0; numberOfResults = 1
    }
    $qs  = ($query.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join '&'
    $uri = '{0}?{1}' -f $script:NvidiaDriverUrl, $qs

    $resp = Invoke-RestMethod -Uri $uri -UseBasicParsing -UserAgent $script:UserAgent -TimeoutSec 30
    if ($resp -is [string]) { $resp = $resp | ConvertFrom-Json }
    if ([string]$resp.Success -ne '1' -or -not $resp.IDS) { return $null }

    $info = @($resp.IDS)[0].downloadInfo
    [pscustomobject]@{
        Version = [string]$info.Version
        Url     = [string]$info.DownloadURL
        Name    = [uri]::UnescapeDataString([string]$info.Name)
        Date    = [string]$info.ReleaseDateTime
        Size    = [string]$info.DownloadURLFileSize
    }
}

function Get-NvidiaUpdate {
    <# Renvoie un "candidat" pour chaque carte NVIDIA dont le pilote est dépassé. #>
    param([Parameter(Mandatory)][object[]]$Inventory)

    $gpus = $Inventory | Where-Object { $_.Class -eq 'DISPLAY' -and $_.VendorId -eq $script:NvidiaVendorId }
    foreach ($gpu in $gpus) {
        $current = ConvertTo-NvidiaVersion -WindowsVersion $gpu.DriverVersion
        Write-Log "NVIDIA : $($gpu.Name) détectée, pilote installé $current ($($gpu.DriverVersion))"

        $ids = Find-NvidiaProductId -GpuName $gpu.Name
        if (-not $ids) { Write-Log "NVIDIA : modèle '$($gpu.Name)' introuvable sur le site" 'WARN'; continue }

        $latest = Get-NvidiaLatestDriver -Psid $ids.Psid -Pfid $ids.Pfid
        if (-not $latest) { Write-Log "NVIDIA : aucun pilote renvoyé pour $($ids.Name)" 'WARN'; continue }
        Write-Log "NVIDIA : dernière version disponible $($latest.Version)"

        if ((Compare-DriverVersion -A $latest.Version -B $current) -eq 1) {
            $sizeMB = 0
            if ($latest.Size -match '([\d\.]+)\s*MB') { $sizeMB = [double]$Matches[1] }
            New-UpdateCandidate -Source 'NVIDIA' -Device $gpu.Name -CurrentVersion $current `
                -NewVersion $latest.Version -SizeMB $sizeMB -Key $latest.Url -Title $latest.Name
        }
    }
}

function Install-NvidiaDriver {
    <#
        Télécharge le pilote, vérifie sa signature numérique (doit être signé par
        NVIDIA Corporation), lance l'installation silencieuse puis vérifie que la
        nouvelle version est bien installée.
    #>
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Version)

    $file = Join-Path $script:DownloadDir ('nvidia-{0}.exe' -f $Version)
    Write-Log "NVIDIA : téléchargement de $Url"
    $ProgressPreference = 'SilentlyContinue'   # sinon Invoke-WebRequest est très lent en 5.1
    Invoke-WebRequest -Uri $Url -OutFile $file -UseBasicParsing -UserAgent $script:UserAgent

    $sig = Get-AuthenticodeSignature -FilePath $file
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA Corporation') {
        Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
        throw "Signature numérique invalide ($($sig.Status)) : fichier supprimé par sécurité."
    }
    Write-Log "NVIDIA : signature valide ($($sig.SignerCertificate.Subject))"

    Write-Log 'NVIDIA : installation silencieuse en cours...'
    $proc = Start-Process -FilePath $file -ArgumentList '-s', '-noreboot', '-noeula' -Wait -PassThru
    Write-Log "NVIDIA : installateur terminé, code de sortie $($proc.ExitCode)"

    # Vérification après installation : on relit la version réellement installée
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -match "VEN_$($script:NvidiaVendorId)" } | Select-Object -First 1
    $installed = $null
    if ($gpu) { $installed = ConvertTo-NvidiaVersion -WindowsVersion $gpu.DriverVersion }

    Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Success        = ($installed -eq $Version)
        RebootRequired = $true
        Message        = "Version installée : $installed (attendue : $Version, code $($proc.ExitCode))"
    }
}
