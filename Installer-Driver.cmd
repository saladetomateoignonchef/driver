@echo off
rem ===========================================================================
rem  Driver - installateur en un clic
rem  Double-clic : telecharge la derniere version publiee sur GitHub et l'installe.
rem  (la partie PowerShell est a la fin de ce fichier, apres #__PS__)
rem ===========================================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%~f0'; $s=[IO.File]::ReadAllText($f); iex $s.Substring($s.LastIndexOf('#__PS__'))"
exit /b
#__PS__
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Host.UI.RawUI.WindowTitle = 'Driver - installation'

# Droits administrateur : on se relance avec la demande Windows (UAC)
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$f`"" -Verb RunAs
    return
}

$repo = 'saladetomateoignonchef/driver'
$work = Join-Path $env:TEMP ('driver-install-' + [guid]::NewGuid().ToString('N'))
try {
    Write-Host ''
    Write-Host '  Driver - installation' -ForegroundColor Cyan
    Write-Host '  ---------------------'
    Write-Host '  1/4 Recherche de la dernière version sur GitHub...'
    $tag = $null; $sources = @()
    for ($i = 1; $i -le 2 -and -not $tag; $i++) {
        try {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -UserAgent 'Driver-Installer'
            $tag = $release.tag_name
            $asset = @($release.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
            if ($asset) { $sources += @{ Url = $asset.url; Accept = 'application/octet-stream' }; $sources += @{ Url = $asset.browser_download_url } }
        } catch {
            Write-Host "      API GitHub indisponible ($($_.Exception.Message)), nouvelle tentative..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
    }
    if (-not $tag) {
        # Plan B sans l'API : la page /releases/latest redirige vers /releases/tag/vX.Y.Z
        $req = [System.Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
        $req.Method = 'HEAD'; $req.AllowAutoRedirect = $false; $req.UserAgent = 'Driver-Installer'
        $resp = $req.GetResponse(); $location = [string]$resp.Headers['Location']; $resp.Close()
        if ($location -notmatch '/releases/tag/([^/?#]+)$') { throw "GitHub est injoignable pour le moment, réessaie plus tard." }
        $tag = $Matches[1]
        $sources += @{ Url = "https://github.com/$repo/releases/download/$tag/driver-$tag.zip" }
    }
    $sources += @{ Url = "https://codeload.github.com/$repo/zip/refs/tags/$tag" }   # archive du code, en dernier recours
    Write-Host "      Version $tag"

    Write-Host '  2/4 Téléchargement...'
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'driver.zip'
    $downloaded = $false
    foreach ($src in $sources) {
        try {
            $headers = @{}
            if ($src.Accept) { $headers['Accept'] = $src.Accept }
            Invoke-WebRequest -Uri $src.Url -OutFile $zip -UseBasicParsing -UserAgent 'Driver-Installer' -Headers $headers
            $downloaded = $true
            break
        } catch {
            Write-Host "      Source indisponible, essai de la suivante..." -ForegroundColor Yellow
        }
    }
    if (-not $downloaded) { throw "Téléchargement impossible : GitHub ne répond pas, réessaie plus tard." }

    Write-Host '  3/4 Extraction...'
    Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'files') -Force
    Get-ChildItem -Path $work -Recurse -File | Unblock-File
    $installer = Get-ChildItem -Path (Join-Path $work 'files') -Recurse -Filter 'Install.ps1' | Select-Object -First 1
    if (-not $installer) { throw 'Install.ps1 introuvable dans le ZIP.' }

    Write-Host '  4/4 Installation...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer.FullName -Silent
    if ($LASTEXITCODE -ne 0) { throw "Install.ps1 a échoué (code $LASTEXITCODE)." }

    Write-Host ''
    Write-Host "  Driver $tag est installé. Un raccourci « Driver » est sur le Bureau." -ForegroundColor Green
    $main = Join-Path $env:ProgramFiles 'DriverUpdater\DriverUpdater.ps1'
    if (-not $env:CI) { Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$main`"") }
} catch {
    Write-Host ''
    Write-Host "  Erreur : $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if ($env:CI) { if ($Error.Count -and -not (Test-Path (Join-Path $env:ProgramFiles 'DriverUpdater\DriverUpdater.ps1'))) { exit 1 } }
else { Read-Host '  Appuie sur Entrée pour fermer' }
