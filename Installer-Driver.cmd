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
    for ($i = 1; $i -le 4; $i++) {
        try {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -UserAgent 'Driver-Installer'
            break
        } catch {
            if ($i -eq 4) { throw }
            Write-Host "      GitHub ne répond pas, nouvelle tentative ($i/4)..." -ForegroundColor Yellow
            Start-Sleep -Seconds (3 * $i)
        }
    }
    $asset = @($release.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
    if (-not $asset) { throw 'Aucun fichier ZIP dans la dernière version publiée.' }
    Write-Host "      Version $($release.tag_name)"

    Write-Host '  2/4 Téléchargement...'
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'driver.zip'
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri $asset.url -OutFile $zip -UseBasicParsing -UserAgent 'Driver-Installer' -Headers @{ 'Accept' = 'application/octet-stream' }
            break
        } catch {
            if ($i -eq 3) { throw }
            Write-Host "      Nouvelle tentative ($i/3)..." -ForegroundColor Yellow
            Start-Sleep -Seconds (3 * $i)
        }
    }

    Write-Host '  3/4 Extraction...'
    Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'files') -Force
    Get-ChildItem -Path $work -Recurse -File | Unblock-File
    $installer = Get-ChildItem -Path (Join-Path $work 'files') -Recurse -Filter 'Install.ps1' | Select-Object -First 1
    if (-not $installer) { throw 'Install.ps1 introuvable dans le ZIP.' }

    Write-Host '  4/4 Installation...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer.FullName -Silent
    if ($LASTEXITCODE -ne 0) { throw "Install.ps1 a échoué (code $LASTEXITCODE)." }

    Write-Host ''
    Write-Host "  Driver $($release.tag_name) est installé. Un raccourci « Driver » est sur le Bureau." -ForegroundColor Green
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
