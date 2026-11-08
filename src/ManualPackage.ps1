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
        # Certains constructeurs mettent un ZIP dans le ZIP : on les extrait aussi (1 niveau)
        foreach ($inner in @(Get-ChildItem -Path $dest -Recurse -File -Filter '*.zip')) {
            $innerDest = Join-Path $inner.DirectoryName $inner.BaseName
            Write-Log "Paquet manuel : extraction du ZIP interne $($inner.Name)"
            Expand-Archive -Path $inner.FullName -DestinationPath $innerDest -Force
        }
        Get-ChildItem -Path $dest -Recurse -File | Unblock-File
        return $dest
    }

    if ([IO.Path]::GetExtension($Path) -eq '.exe') { return (Split-Path $Path -Parent) }

    throw "Format non pris en charge : $Path (glisse un fichier .zip, un dossier ou un .exe)"
}

function Read-InfText {
    <#
        Lit un .inf quel que soit son encodage. Beaucoup de .inf sont en UTF-16
        (2 octets par caractère), parfois SANS marqueur (BOM) : lus comme du texte
        classique, "VEN_10EC" devient "V.E.N._.1.0.E.C" et plus rien ne correspond.
    #>
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    $sample = [Math]::Min($bytes.Length, 512); $zeros = 0
    for ($i = 1; $i -lt $sample; $i += 2) { if ($bytes[$i] -eq 0) { $zeros++ } }
    if ($sample -gt 0 -and $zeros -gt ($sample / 4)) { return [Text.Encoding]::Unicode.GetString($bytes) }
    return [Text.Encoding]::Default.GetString($bytes)
}

function Get-InfSummary {
    <# Classe, version et identifiants matériels visés par un .inf (pour le diagnostic). #>
    param([string]$Path, [string]$Text)
    $class = $null
    if ($Text -match '(?m)^\s*Class\s*=\s*([^\s;]+)') { $class = $Matches[1] }
    $ver = Get-InfDriverVersion -InfText $Text
    $ids = @([regex]::Matches($Text, '(?i)(?:VEN|VID)_[0-9A-F]{4}&(?:DEV|PID)_[0-9A-F]{4}') |
        ForEach-Object { $_.Value.ToUpper() } | Sort-Object -Unique)
    [pscustomobject]@{
        InfName = Split-Path $Path -Leaf
        Class   = $class
        Version = if ($ver) { $ver.Version } else { '?' }
        Ids     = $ids
    }
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
        $text = Read-InfText -Path $inf.FullName
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

    $folder    = Expand-DriverPackage -Path $Path
    $inventory = @(Get-DeviceInventory)
    $drivers   = @(Find-PackageDriver -Folder $folder -Inventory $inventory)

    # --- Diagnostic : ce que contient le paquet et ce qu'il vise ---
    $files = @(Get-ChildItem -Path $folder -Recurse -File)
    $infs  = @($files | Where-Object { $_.Extension -eq '.inf' })
    $exes  = @($files | Where-Object { $_.Extension -eq '.exe' })
    # BIOS : Gigabyte = extension .F + version (H510MHV2.F5b), autres = .CAP / .ROM ; ou ZIP "mb_bios_..."
    $bios  = @($files | Where-Object { $_.Extension -match '^\.(F\d+[a-z]?|CAP|ROM)$' } | ForEach-Object { $_.Name })
    if ($bios.Count -eq 0 -and (Split-Path $Path -Leaf) -match '(?i)bios') { $bios = @(Split-Path $Path -Leaf) }
    $infSummary = @($infs | ForEach-Object { Get-InfSummary -Path $_.FullName -Text (Read-InfText -Path $_.FullName) })

    # Périphériques du PC du même type que ceux visés par le paquet (ex. MEDIA = audio)
    $classes   = @($infSummary | ForEach-Object { $_.Class } | Where-Object { $_ } | Sort-Object -Unique)
    $pcDevices = @($inventory | Where-Object { $classes -contains $_.Class -and $_.HardwareId -match '(?:VEN|VID)_[0-9A-Fa-f]{4}&(?:DEV|PID)_[0-9A-Fa-f]{4}' } |
        ForEach-Object {
            [void]($_.HardwareId -match '((?:VEN|VID)_[0-9A-Fa-f]{4}&(?:DEV|PID)_[0-9A-Fa-f]{4})')
            '{0} ({1}, version {2})' -f $_.Name, $Matches[1].ToUpper(), $_.DriverVersion
        } | Sort-Object -Unique)
    $setup   = if ([IO.Path]::GetExtension($Path) -eq '.exe') { $Path } else { Find-PackageSetup -Folder $folder }

    $signer = $null; $signed = $false
    if ($setup) {
        $sig    = Get-AuthenticodeSignature -FilePath $setup
        $signed = ($sig.Status -eq 'Valid')
        if ($sig.SignerCertificate) { $signer = $sig.SignerCertificate.GetNameInfo('SimpleName', $false) }
    }

    Write-Log ("Paquet manuel : {0} fichier(s), {1} .inf, {2} .exe ; {3} .inf correspondant(s) au PC ; installateur : {4} (signé : {5}, {6})" -f `
        $files.Count, $infs.Count, $exes.Count, $drivers.Count, $setup, $signed, $signer)
    foreach ($i in $infSummary) {
        Write-Log ("  {0} : classe {1}, version {2}, vise {3}" -f $i.InfName, $i.Class, $i.Version, (($i.Ids | Select-Object -First 8) -join ' '))
    }
    [pscustomobject]@{
        Source      = $Path
        Folder      = $folder
        FileCount   = $files.Count
        InfCount    = $infs.Count
        ExeCount    = $exes.Count
        BiosFiles   = $bios
        InfSummary  = $infSummary
        PcDevices   = $pcDevices
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
        Set-TaskProgress -Stage "Installation de $($d.InfName)" -Detail "$($d.Device) : $($d.CurrentVersion) -> $($d.PackageVersion)"
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
        Add-HistoryEntry -Type 'Paquet' -Device $d.Device -Source $d.InfName -OldVersion $d.CurrentVersion `
            -NewVersion $d.PackageVersion -Success ($code -in @(0, 3010, 259)) -Message $msg
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

    if ($CreateRestorePoint) {
        Set-TaskProgress -Stage 'Création du point de restauration'
        [void](New-DriverRestorePoint)
    }

    $toInstall = @($Analysis.Drivers | Where-Object { $_.IsNewer })
    if ($toInstall.Count -gt 0) {
        # Sauvegarde des pilotes actuels des périphériques concernés
        $names = @($toInstall | ForEach-Object { $_.Device -split ', ' })
        Backup-BeforeInstall -DeviceName $names -Inventory @(Get-DeviceInventory)
        $results = @(Install-InfDriver -Driver $toInstall)
        Clear-TaskProgress
        return $results
    }

    if ($Analysis.Setup -and $Analysis.SetupSigned) {
        Write-Log "Paquet manuel : lancement de $($Analysis.Setup)"
        Set-TaskProgress -Stage "Installateur du constructeur en cours : $(Split-Path $Analysis.Setup -Leaf)" -Detail 'suis ses étapes dans sa fenêtre'
        $p = Start-Process -FilePath $Analysis.Setup -WorkingDirectory (Split-Path $Analysis.Setup -Parent) -Wait -PassThru
        Clear-TaskProgress
        Add-HistoryEntry -Type 'Paquet' -Device (Split-Path $Analysis.Source -Leaf) -Source 'setup.exe' `
            -Success ($p.ExitCode -in @(0, 3010)) -Message "Installateur terminé (code $($p.ExitCode))"
        return [pscustomobject]@{
            Device         = Split-Path $Analysis.Source -Leaf
            Success        = ($p.ExitCode -in @(0, 3010))
            RebootRequired = $true
            Message        = "Installateur terminé (code $($p.ExitCode))"
        }
    }

    throw 'Rien à installer dans ce paquet.'
}
