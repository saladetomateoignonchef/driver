# =============================================================================
#  SelfUpdate.ps1 - Mise à jour de Driver lui-même depuis GitHub
#
#  Chaque version est publiée sur GitHub (onglet "Releases") par GitHub Actions
#  quand un tag vX.Y.Z est créé : le ZIP n'est publié que si les tests passent.
#  L'application compare sa version ($AppVersion) à la dernière publiée, puis
#  télécharge le ZIP et relance Install.ps1, qui remplace les fichiers dans
#  C:\Program Files\DriverUpdater.
# =============================================================================

function Get-UpdateRepo {
    <# Dépôt GitHub source des mises à jour (Paramètres), au format propriétaire/projet. #>
    $repo = [string](Get-AppSettings).UpdateRepo
    if ($repo -notmatch '^[\w.-]+/[\w.-]+$') { $repo = $script:GitHubRepo }
    return $repo
}

function Get-LatestAppRelease {
    $uri = "https://api.github.com/repos/$(Get-UpdateRepo)/releases/latest"
    # -UserAgent (et non un en-tête « User-Agent ») : méthode prévue par Windows PowerShell 5.1
    $rel = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 10 -UserAgent $script:UserAgent `
        -Headers @{ 'Accept' = 'application/vnd.github+json' }
    $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
    [pscustomobject]@{
        Version  = ([string]$rel.tag_name).TrimStart('v', 'V')
        Tag      = [string]$rel.tag_name
        Notes    = [string]$rel.body
        PageUrl  = [string]$rel.html_url
        # Lien de l'API (fiable) + lien classique en secours : le lien classique
        # github.com/.../releases/download/... a déjà renvoyé des erreurs 504.
        AssetUrl = if ($asset) { [string]$asset.url } else { $null }
        AssetWebUrl = if ($asset) { [string]$asset.browser_download_url } else { $null }
    }
}

function Test-AppUpdate {
    <# Renvoie la version publiée si elle est plus récente que celle installée, sinon $null. #>
    try {
        $latest = Get-LatestAppRelease
        if ($latest.AssetUrl -and (Compare-DriverVersion -A $latest.Version -B $script:AppVersion) -eq 1) {
            Write-Log "Nouvelle version de Driver disponible : $($latest.Version) (installée : $($script:AppVersion))"
            return $latest
        }
    } catch {
        Write-Log "Vérification des versions de Driver impossible : $($_.Exception.Message)" 'WARN'
    }
    return $null
}

function Install-AppUpdate {
    param([Parameter(Mandatory)][string]$AssetUrl, [Parameter(Mandatory)][string]$Version, [string]$AssetWebUrl)

    $work = Join-Path $script:DownloadDir "driver-update-$Version"
    if (Test-Path $work) { Remove-Item -Path $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'driver.zip'

    try {
        # API GitHub : "Accept: application/octet-stream" renvoie le fichier lui-même
        Invoke-FileDownload -Url $AssetUrl -OutFile $zip -Label "Driver $Version" -Accept 'application/octet-stream'
    } catch {
        if (-not $AssetWebUrl) { throw }
        Write-Log "Téléchargement via l'API impossible, essai du lien classique : $AssetWebUrl" 'WARN'
        Invoke-FileDownload -Url $AssetWebUrl -OutFile $zip -Label "Driver $Version"
    }
    Set-TaskProgress -Stage (T 'StageAppInstall' $Version)
    Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'files') -Force
    Get-ChildItem -Path $work -Recurse -File | Unblock-File

    $installer = Get-ChildItem -Path (Join-Path $work 'files') -Recurse -Filter 'Install.ps1' -File | Select-Object -First 1
    if (-not $installer) { throw (T 'MsgNoInstaller') }

    Write-Log "Mise à jour de Driver : lancement de $($installer.FullName)"
    $p = Start-Process -FilePath 'powershell.exe' -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($installer.FullName)`"", '-Silent')
    Write-Log "Mise à jour de Driver : Install.ps1 terminé (code $($p.ExitCode))"

    [pscustomobject]@{
        Device = "Driver $Version"; Success = ($p.ExitCode -eq 0); RebootRequired = $false
        Message = if ($p.ExitCode -eq 0) { T 'MsgAppUpdated' $Version } else { T 'MsgAppUpdateFail' $p.ExitCode }
        SelfUpdate = $true
    }
}
