# =============================================================================
#  get-driver.ps1 - Installation (ou reparation) de Driver en une commande,
#  sans navigateur. Dans PowerShell ouvert EN ADMINISTRATEUR :
#
#     irm https://raw.githubusercontent.com/saladetomateoignonchef/driver/main/get-driver.ps1 | iex
#
#  Telecharge la derniere version publiee sur GitHub (avec plan B si l'API
#  GitHub ne repond pas), puis lance Install.ps1. Les reglages et sauvegardes
#  (C:\ProgramData\DriverUpdater) sont conserves.
# =============================================================================
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ''
        Write-Host '  Il faut ouvrir PowerShell EN ADMINISTRATEUR :' -ForegroundColor Yellow
        Write-Host '  menu Demarrer > tape "powershell" > clic droit sur Windows PowerShell > Executer en tant qu''administrateur.'
        Write-Host '  Puis recolle la commande.'
        return
    }

    $repo = 'saladetomateoignonchef/driver'
    $ua   = 'Driver-Installer'
    $work = Join-Path $env:TEMP ('driver-install-' + [guid]::NewGuid().ToString('N'))
    try {
        Write-Host ''
        Write-Host '  Driver - installation' -ForegroundColor Cyan
        Write-Host '  ---------------------'
        Write-Host '  1/4 Recherche de la derniere version sur GitHub...'
        $tag = $null; $sources = @()
        for ($i = 1; $i -le 2 -and -not $tag; $i++) {
            try {
                $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -UserAgent $ua
                $tag = $release.tag_name
                $asset = @($release.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
                if ($asset) {
                    $sources += @{ Url = $asset.url; Accept = 'application/octet-stream' }
                    $sources += @{ Url = $asset.browser_download_url }
                }
            } catch {
                Write-Host "      API GitHub indisponible, nouvelle tentative..." -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
        }
        if (-not $tag) {
            # Plan B sans l'API : la page /releases/latest redirige vers /releases/tag/vX.Y.Z
            $req = [System.Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
            $req.Method = 'HEAD'; $req.AllowAutoRedirect = $false; $req.UserAgent = $ua
            $resp = $req.GetResponse(); $location = [string]$resp.Headers['Location']; $resp.Close()
            if ($location -notmatch '/releases/tag/([^/?#]+)$') { throw 'GitHub est injoignable pour le moment, reessaie plus tard.' }
            $tag = $Matches[1]
            $sources += @{ Url = "https://github.com/$repo/releases/download/$tag/driver-$tag.zip" }
        }
        $sources += @{ Url = "https://codeload.github.com/$repo/zip/refs/tags/$tag" }
        Write-Host "      Version $tag"

        Write-Host '  2/4 Telechargement...'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip = Join-Path $work 'driver.zip'
        $ok = $false
        foreach ($src in $sources) {
            try {
                $headers = @{}
                if ($src.Accept) { $headers['Accept'] = $src.Accept }
                Invoke-WebRequest -Uri $src.Url -OutFile $zip -UseBasicParsing -UserAgent $ua -Headers $headers
                $ok = $true; break
            } catch { Write-Host '      Source indisponible, essai de la suivante...' -ForegroundColor Yellow }
        }
        if (-not $ok) { throw 'Telechargement impossible : GitHub ne repond pas, reessaie plus tard.' }

        Write-Host '  3/4 Extraction...'
        Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'files') -Force
        Get-ChildItem -Path $work -Recurse -File | Unblock-File
        $installer = Get-ChildItem -Path (Join-Path $work 'files') -Recurse -Filter 'Install.ps1' | Select-Object -First 1
        if (-not $installer) { throw 'Install.ps1 introuvable dans le ZIP.' }

        Write-Host '  4/4 Installation...'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer.FullName -Silent
        if ($LASTEXITCODE -ne 0) { throw "Install.ps1 a echoue (code $LASTEXITCODE)." }

        Write-Host ''
        Write-Host "  Driver $tag est installe. Un raccourci 'Driver' est sur le Bureau." -ForegroundColor Green
        if (-not $env:CI) {
            $main = Join-Path $env:ProgramFiles 'DriverUpdater\DriverUpdater.ps1'
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$main`"")
        }
    } catch {
        Write-Host ''
        Write-Host "  Erreur : $($_.Exception.Message)" -ForegroundColor Red
        if ($env:CI) { throw }
    } finally {
        Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
