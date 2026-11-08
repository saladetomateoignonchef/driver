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

function Get-LatestTagFromWeb {
    <#
        Plan B sans l'API : github.com/<dépôt>/releases/latest redirige vers
        .../releases/tag/vX.Y.Z ; on lit simplement l'adresse de redirection.
    #>
    param([string]$Repo)
    $req = [System.Net.HttpWebRequest]::Create("https://github.com/$Repo/releases/latest")
    $req.Method            = 'HEAD'
    $req.AllowAutoRedirect = $false
    $req.UserAgent         = $script:UserAgent
    $req.Timeout           = 15000
    $resp = $req.GetResponse()
    try { $location = [string]$resp.Headers['Location'] } finally { $resp.Close() }
    if ($location -match '/releases/tag/([^/?#]+)$') { return $Matches[1] }
    throw "Redirection inattendue : $location"
}

function Get-LatestAppRelease {
    <#
        Dernière version publiée. Trois liens de téléchargement, essayés dans l'ordre :
        AssetUrl (API GitHub), AssetWebUrl (lien classique), ArchiveUrl (archive du code).
        Si l'API GitHub ne répond pas (503/504 passagers), plan B par la page web.
    #>
    $repo = Get-UpdateRepo
    $rel  = $null
    for ($i = 1; $i -le 2; $i++) {
        try {
            # -UserAgent (et non un en-tête « User-Agent ») : méthode prévue par Windows PowerShell 5.1
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -TimeoutSec 10 `
                -UserAgent $script:UserAgent -Headers @{ 'Accept' = 'application/vnd.github+json' }
            break
        } catch {
            Write-Log "API GitHub : tentative $i/2 échouée ($($_.Exception.Message))" 'WARN'
            if ($i -lt 2) { Start-Sleep -Seconds 2 }
        }
    }

    if ($rel) {
        $tag   = [string]$rel.tag_name
        $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
        $api   = if ($asset) { [string]$asset.url } else { $null }
        $web   = if ($asset) { [string]$asset.browser_download_url } else { $null }
        $notes = [string]$rel.body; $page = [string]$rel.html_url
    } else {
        $tag = Get-LatestTagFromWeb -Repo $repo       # lève une erreur si GitHub est vraiment injoignable
        Write-Log "Dernière version trouvée par la page web (plan B) : $tag" 'WARN'
        $api = $null
        $web = "https://github.com/$repo/releases/download/$tag/driver-$tag.zip"
        $notes = ''; $page = "https://github.com/$repo/releases/tag/$tag"
    }
    $archive = "https://codeload.github.com/$repo/zip/refs/tags/$tag"
    $primary = if ($api) { $api } else { $web }
    [pscustomobject]@{
        Version     = $tag.TrimStart('v', 'V')
        Tag         = $tag
        Notes       = $notes
        PageUrl     = $page
        AssetUrl    = $primary
        AssetWebUrl = $web
        ArchiveUrl  = $archive
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
    param([Parameter(Mandatory)][string]$AssetUrl, [Parameter(Mandatory)][string]$Version, [string]$AssetWebUrl, [string]$ArchiveUrl)

    $work = Join-Path $script:DownloadDir "driver-update-$Version"
    if (Test-Path $work) { Remove-Item -Path $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'driver.zip'

    # Plusieurs sources, essayées dans l'ordre (GitHub a parfois des pannes passagères)
    $sources = @(@($AssetUrl, $AssetWebUrl, $ArchiveUrl) | Where-Object { $_ } | Select-Object -Unique)
    $ok = $false
    foreach ($url in $sources) {
        try {
            $accept = if ($url -like 'https://api.github.com/*') { 'application/octet-stream' } else { $null }
            Invoke-FileDownload -Url $url -OutFile $zip -Label "Driver $Version" -Accept $accept -Attempts 2
            $ok = $true
            break
        } catch {
            Write-Log "Téléchargement de Driver impossible depuis $url : $($_.Exception.Message)" 'WARN'
        }
    }
    if (-not $ok) { throw (T 'GitHubUnreachable' 'download') }
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
