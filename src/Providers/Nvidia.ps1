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
    param([Parameter(Mandatory)][string]$Psid, [Parameter(Mandatory)][string]$Pfid, [switch]$Studio)

    # Game Ready (jeux) : upCRD=0 + isWHQL=1 / Studio (création) : upCRD=1, SANS filtre isWHQL
    # (testé : avec isWHQL=1, l'API ne renvoie aucun pilote Studio)
    $query = [ordered]@{
        func = 'DriverManualLookup'; psid = $Psid; pfid = $Pfid; osID = $script:NvidiaOsId
        languageCode = 1033; beta = 0; dltype = -1; dch = 1
        qnf = 0; sort1 = 0; numberOfResults = 1
    }
    if ($Studio) { $query['upCRD'] = 1 } else { $query['upCRD'] = 0; $query['isWHQL'] = 1 }
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

function Get-NvidiaDownloadSize {
    <# Taille en Mo : d'abord depuis le texte renvoyé par l'API, sinon via l'en-tête Content-Length. #>
    param([string]$Url, [string]$SizeText)
    # L'API renvoie par exemple "1.04 GB" ou "650.12 MB"
    if ($SizeText -match '([\d]+(?:[\.,]\d+)?)\s*(GB|Go)') {
        return [math]::Round([double]($Matches[1] -replace ',', '.') * 1024, 1)
    }
    if ($SizeText -match '([\d]+(?:[\.,]\d+)?)\s*(MB|Mo)') {
        return [double]($Matches[1] -replace ',', '.')
    }
    try {
        $head = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -UserAgent $script:UserAgent -TimeoutSec 15
        $len  = [double]([string]$head.Headers['Content-Length'])
        if ($len -gt 0) { return [math]::Round($len / 1MB, 1) }
    } catch {
        Write-Log "NVIDIA : taille du fichier inconnue ($($_.Exception.Message))" 'WARN'
    }
    return 0
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

        $studio = ((Get-AppSettings).NvidiaBranch -eq 'Studio')
        $latest = Get-NvidiaLatestDriver -Psid $ids.Psid -Pfid $ids.Pfid -Studio:$studio
        if (-not $latest) { Write-Log "NVIDIA : aucun pilote renvoyé pour $($ids.Name)" 'WARN'; continue }
        Write-Log "NVIDIA : dernière version disponible $($latest.Version) ($($latest.Name))"

        if ((Compare-DriverVersion -A $latest.Version -B $current) -eq 1) {
            $sizeMB = Get-NvidiaDownloadSize -Url $latest.Url -SizeText $latest.Size
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
    Invoke-FileDownload -Url $Url -OutFile $file -Label "pilote NVIDIA $Version"

    Set-TaskProgress -Stage 'Vérification de la signature numérique du pilote NVIDIA'
    $sig = Get-AuthenticodeSignature -FilePath $file
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA Corporation') {
        Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
        throw "Signature numérique invalide ($($sig.Status)) : fichier supprimé par sécurité."
    }
    Write-Log "NVIDIA : signature valide ($($sig.SignerCertificate.Subject))"

    Write-Log 'NVIDIA : installation silencieuse en cours...'
    Set-TaskProgress -Stage "Installation du pilote NVIDIA $Version" -Detail 'l''écran peut devenir noir quelques secondes'
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
