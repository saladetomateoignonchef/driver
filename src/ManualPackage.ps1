# =============================================================================
#  ManualPackage.ps1 - Installation d'un paquet de pilotes téléchargé à la main
#                      (ZIP du site Gigabyte, Realtek, Intel...) par glisser-déposer
#
#  1. Extraction du ZIP dans C:\ProgramData\DriverUpdater\downloads\manuel\...
#  2. Recherche des fichiers .inf qui correspondent au matériel du PC
#     (on cherche les identifiants VEN_xxxx&DEV_xxxx du PC dans le texte des .inf)
#  3. Installation avec pnputil (outil officiel de Windows) : Windows refuse tout
#     pilote non signé, et n'installe que si le pilote convient au périphérique.
#  4. S'il n'y a pas de .inf utilisable : lancement du setup.exe du paquet, après
#     vérification de sa signature numérique.
# =============================================================================

function Expand-DriverPackage {
    <# Renvoie le dossier à analyser (ZIP extrait, ou dossier déposé tel quel). #>
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -Path $Path -PathType Container) { return $Path }

    if ([IO.Path]::GetExtension($Path) -eq '.zip') {
        $name = [IO.Path]::GetFileNameWithoutExtension($Path)
        $dest = Join-Path $script:DownloadDir ('manuel\{0}-{1:yyyyMMdd-HHmmss}' -f $name, (Get-Date))
        Write-Log "Paquet manuel : extraction de $Path vers $dest"
        Expand-Archive -Path $Path -DestinationPath $dest -Force
        Get-ChildItem -Path $dest -Recurse -File | Unblock-File
        return $dest
    }

    if ([IO.Path]::GetExtension($Path) -eq '.exe') { return (Split-Path $Path -Parent) }

    throw "Format non pris en charge : $Path (glisse un fichier .zip, un dossier ou un .exe)"
}

function Get-InfDriverVersion {
    param([string]$InfText)
    if ($InfText -match '(?m)^\s*DriverVer\s*=\s*([^,\r\n]+?)\s*,\s*([\d\.]+)') {
        return [pscustomobject]@{ Date = $Matches[1]; Version = $Matches[2] }
    }
    return $null
}

function Find-PackageDriver {
    <# Cherche dans le dossier les .inf qui concernent un périphérique présent sur le PC. #>
    param([Parameter(Mandatory)][string]$Folder, [object[]]$Inventory)

    if (-not $Inventory) { $Inventory = @(Get-DeviceInventory) }

    # Identifiants courts du matériel présent : VEN_10EC&DEV_0897, VID_2357&PID_0604...
    $hwIds = foreach ($dev in $Inventory) {
        if ($dev.HardwareId -match '((?:VEN|VID)_[0-9A-Fa-f]{4}&(?:DEV|PID)_[0-9A-Fa-f]{4})') {
            [pscustomobject]@{ Id = $Matches[1].ToUpper(); Device = $dev }
        }
    }
    $hwIds = @($hwIds | Sort-Object Id -Unique)

    foreach ($inf in Get-ChildItem -Path $Folder -Recurse -Filter '*.inf' -File) {
        $text = Get-Content -Path $inf.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $text) { continue }

        $matched = @($hwIds | Where-Object { $text -match [regex]::Escape($_.Id) })
        if ($matched.Count -eq 0) { continue }

        $ver     = Get-InfDriverVersion -InfText $text
        $current = $matched[0].Device.DriverVersion
        $newer   = $true
        if ($ver) {
            $cmp = Compare-DriverVersion -A $ver.Version -B $current
            if ($cmp -ne $null -and $cmp -le 0) { $newer = $false }
        }

        [pscustomobject]@{
            Inf            = $inf.FullName
            InfName        = $inf.Name
            Device         = (($matched | ForEach-Object { $_.Device.Name } | Sort-Object -Unique) -join ', ')
            CurrentVersion = $current
            PackageVersion = if ($ver) { $ver.Version } else { '?' }
            IsNewer        = $newer
        }
    }
}

function Find-PackageSetup {
    <# Renvoie l'installateur principal du paquet (setup.exe le moins profond, sinon le seul .exe). #>
    param([Parameter(Mandatory)][string]$Folder)
    $setup = Get-ChildItem -Path $Folder -Recurse -File -Include 'setup.exe', 'install.exe', 'AsusSetup.exe' |
        Sort-Object { $_.FullName.Split('\').Count } | Select-Object -First 1
    if (-not $setup) {
        $exes = @(Get-ChildItem -Path $Folder -Recurse -File -Filter '*.exe')
        if ($exes.Count -eq 1) { $setup = $exes[0] }
    }
    if ($setup) { return $setup.FullName }
    return $null
}

function Get-DriverPackageAnalysis {
    <# Analyse complète d'un ZIP / dossier / exe déposé dans la fenêtre. #>
    param([Parameter(Mandatory)][string]$Path)

    $folder  = Expand-DriverPackage -Path $Path
    $drivers = @(Find-PackageDriver -Folder $folder)
    $setup   = if ([IO.Path]::GetExtension($Path) -eq '.exe') { $Path } else { Find-PackageSetup -Folder $folder }

    $signer = $null; $signed = $false
    if ($setup) {
        $sig    = Get-AuthenticodeSignature -FilePath $setup
        $signed = ($sig.Status -eq 'Valid')
        if ($sig.SignerCertificate) { $signer = $sig.SignerCertificate.GetNameInfo('SimpleName', $false) }
    }

    Write-Log ("Paquet manuel : {0} pilote(s) .inf correspondant(s), installateur : {1} (signé : {2}, {3})" -f $drivers.Count, $setup, $signed, $signer)
    [pscustomobject]@{
        Source      = $Path
        Folder      = $folder
        Drivers     = $drivers
        Setup       = $setup
        SetupSigned = $signed
        SetupSigner = $signer
    }
}

function Install-InfDriver {
    <# Installe des .inf avec pnputil. Codes : 0 = OK, 3010 = OK + redémarrage, 259 = aucun périphérique mis à jour. #>
    param([Parameter(Mandatory)][object[]]$Driver)

    $pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
    foreach ($d in $Driver) {
        Write-Log "pnputil : installation de $($d.Inf)"
        $out  = & $pnputil /add-driver "$($d.Inf)" /install 2>&1 | Out-String
        $code = $LASTEXITCODE
        Write-Log "pnputil : code $code`r`n$out"

        $msg = switch ($code) {
            0       { "Installé ($($d.PackageVersion))" }
            3010    { "Installé ($($d.PackageVersion)), redémarrage nécessaire" }
            259     { 'Ajouté, mais Windows a gardé le pilote actuel (déjà équivalent ou plus récent)' }
            default { "Échec, code pnputil $code (voir journal)" }
        }
        [pscustomobject]@{
            Device         = "$($d.Device) [$($d.InfName)]"
            Success        = ($code -in @(0, 3010, 259))
            RebootRequired = ($code -eq 3010)
            Message        = $msg
        }
    }
}

function Install-DriverPackage {
    <# Installe un paquet analysé : les .inf plus récents, sinon le setup.exe (signé uniquement). #>
    param([Parameter(Mandatory)][object]$Analysis, [switch]$CreateRestorePoint)

    if ($CreateRestorePoint) { [void](New-DriverRestorePoint) }

    $toInstall = @($Analysis.Drivers | Where-Object { $_.IsNewer })
    if ($toInstall.Count -gt 0) {
        return Install-InfDriver -Driver $toInstall
    }

    if ($Analysis.Setup -and $Analysis.SetupSigned) {
        Write-Log "Paquet manuel : lancement de $($Analysis.Setup)"
        $p = Start-Process -FilePath $Analysis.Setup -WorkingDirectory (Split-Path $Analysis.Setup -Parent) -Wait -PassThru
        return [pscustomobject]@{
            Device         = Split-Path $Analysis.Source -Leaf
            Success        = ($p.ExitCode -in @(0, 3010))
            RebootRequired = $true
            Message        = "Installateur terminé (code $($p.ExitCode))"
        }
    }

    throw 'Rien à installer dans ce paquet.'
}
