# =============================================================================
#  Common.ps1 - Fonctions communes : dossiers, journalisation, droits, versions
# =============================================================================

$script:AppName      = 'DriverUpdater'
$script:AppVersion   = '2.3.1'                              # une nouvelle valeur poussée sur main = nouvelle version publiée
$script:GitHubRepo   = 'saladetomateoignonchef/driver'      # source par défaut (modifiable dans Paramètres)
$script:DataDir      = Join-Path $env:ProgramData 'DriverUpdater'
$script:LogDir       = Join-Path $script:DataDir 'logs'
$script:DownloadDir  = Join-Path $script:DataDir 'downloads'
$script:BackupDir    = Join-Path $script:DataDir 'backups'
$script:SettingsFile = Join-Path $script:DataDir 'settings.json'
$script:HistoryFile  = Join-Path $script:DataDir 'history.json'
$script:ProgressFile = Join-Path $script:DataDir 'progress.json'
$script:UserAgent    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) DriverUpdater/$($script:AppVersion)"

# Windows PowerShell 5.1 : on force TLS 1.2 pour les sites constructeurs
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Initialize-AppFolder {
    foreach ($dir in @($script:DataDir, $script:LogDir, $script:DownloadDir, $script:BackupDir)) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    # Les fichiers téléchargés y sont exécutés en administrateur : un utilisateur
    # standard ne doit pas pouvoir y déposer ou modifier un fichier entre-temps.
    if (Test-IsAdmin) {
        # 1) Droits posés UNIQUEMENT sur le dossier racine (pas de /T : appliquer des droits de
        #    dossier "(OI)(CI)" aux fichiers les laissait sans aucun droit, même pour l'admin).
        & icacls.exe $script:DataDir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /C /Q 2>&1 | Out-Null
        # 2) Tout le contenu hérite de ces droits (répare aussi les fichiers abîmés par les versions 2.0 à 2.2)
        & icacls.exe (Join-Path $script:DataDir '*') /reset /T /C /Q 2>&1 | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERREUR')][string]$Level = 'INFO'
    )
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    $file = Join-Path $script:LogDir ('{0:yyyy-MM-dd}.log' -f (Get-Date))
    try { Add-Content -Path $file -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
    Write-Verbose $line
}

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-NvidiaVersion {
    <#
        Convertit la version Windows d'un pilote NVIDIA en version "commerciale".
        Exemple : 32.0.16.1088  ->  610.88  (on garde les 5 derniers chiffres)
    #>
    param([Parameter(Mandatory)][string]$WindowsVersion)
    $digits = $WindowsVersion -replace '\D', ''
    if ($digits.Length -lt 5) { return $null }
    $last5 = $digits.Substring($digits.Length - 5)
    return '{0}.{1}' -f $last5.Substring(0, 3), $last5.Substring(3, 2)
}

function Get-VersionFromText {
    <#
        Extrait le numéro de version en fin de titre Windows Update.
        Exemple : "Intel - System - 10.1.31.2"  ->  10.1.31.2
    #>
    param([string]$Text)
    if (-not $Text) { return $null }
    $found = [regex]::Matches($Text, '\d+(?:\.\d+){2,3}')
    if ($found.Count -gt 0) { return $found[$found.Count - 1].Value }
    return $null
}

function Compare-DriverVersion {
    <# Renvoie -1 si A < B, 0 si égal, 1 si A > B. $null si non comparable. #>
    param([string]$A, [string]$B)
    $va = $null; $vb = $null
    if ([version]::TryParse($A, [ref]$va) -and [version]::TryParse($B, [ref]$vb)) {
        return $va.CompareTo($vb)
    }
    return $null
}

function New-UpdateCandidate {
    <# Objet standard décrivant une mise à jour proposée, quel que soit le fournisseur. #>
    param(
        [string]$Source, [string]$Device, [string]$CurrentVersion,
        [string]$NewVersion, [double]$SizeMB, [string]$Key, [string]$Title
    )
    [pscustomobject]@{
        Source         = $Source          # 'NVIDIA' ou 'Windows Update'
        Device         = $Device          # nom du périphérique
        CurrentVersion = $CurrentVersion
        NewVersion     = $NewVersion
        SizeMB         = $SizeMB
        Key            = $Key             # URL (NVIDIA) ou UpdateID (Windows Update)
        Title          = $Title
    }
}

# =============================================================================
#  Paramètres (C:\ProgramData\DriverUpdater\settings.json)
# =============================================================================

function Get-DefaultSettings {
    [pscustomobject]@{
        CheckFrequency  = 'Startup'     # Startup | Daily | Weekly | Never
        Notifications   = $true         # notification au démarrage au lieu d'ouvrir la fenêtre
        NvidiaBranch    = 'GameReady'   # GameReady | Studio
        Theme           = 'Light'       # Light | Dark
        BackupKeep      = 2             # nombre de sauvegardes gardées par pilote
        AutoUpdateCheck = $true         # vérifier les nouvelles versions de Driver
        IgnoredUpdates  = @()           # { Device, NewVersion, Date }
        Language        = 'fr'          # fr | en
        Zoom            = 100           # taille du texte : 100 | 115 | 130 (%)
        UpdateRepo      = $script:GitHubRepo   # dépôt GitHub d'où viennent les mises à jour de Driver
        ProviderNvidia  = $true         # interroger le site NVIDIA
        ProviderWindowsUpdate = $true   # interroger Windows Update
        LastCheck       = $null         # date de la dernière vérification automatique
    }
}

function Get-AppSettings {
    $settings = Get-DefaultSettings
    if (Test-Path -Path $script:SettingsFile) {
        try {
            $saved = Get-Content -Path $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $saved.PSObject.Properties) {
                if ($settings.PSObject.Properties[$p.Name]) { $settings.($p.Name) = $p.Value }
            }
        } catch {
            Write-Log "Paramètres illisibles, valeurs par défaut utilisées : $($_.Exception.Message)" 'WARN'
        }
    }
    $settings.IgnoredUpdates = @($settings.IgnoredUpdates | Where-Object { $_ })
    return $settings
}

function Save-AppSettings {
    param([Parameter(Mandatory)][object]$Settings)
    # -ErrorAction Stop : un échec d'écriture doit être signalé, pas ignoré en silence
    $Settings | ConvertTo-Json -Depth 4 | Set-Content -Path $script:SettingsFile -Encoding UTF8 -ErrorAction Stop
}

function Test-CheckDue {
    <# La vérification automatique doit-elle avoir lieu maintenant (selon la fréquence choisie) ? #>
    param([Parameter(Mandatory)][object]$Settings, [datetime]$Now = (Get-Date))
    $last = $null
    if ($Settings.LastCheck) { try { $last = [datetime]$Settings.LastCheck } catch { $last = $null } }
    switch ($Settings.CheckFrequency) {
        'Never'  { return $false }
        'Daily'  { return (-not $last) -or (($Now - $last).TotalHours -ge 20) }
        'Weekly' { return (-not $last) -or (($Now - $last).TotalDays -ge 6.5) }
        default  { return $true }
    }
}

function Test-UpdateIgnored {
    <# Une mise à jour est ignorée pour CETTE version : une version plus récente sera de nouveau proposée. #>
    param([Parameter(Mandatory)][object]$Candidate, [Parameter(Mandatory)][object]$Settings)
    return @($Settings.IgnoredUpdates | Where-Object {
        $_.Device -eq $Candidate.Device -and $_.NewVersion -eq $Candidate.NewVersion
    }).Count -gt 0
}

function Add-IgnoredUpdate {
    param([Parameter(Mandatory)][object]$Candidate, [Parameter(Mandatory)][object]$Settings)
    if (Test-UpdateIgnored -Candidate $Candidate -Settings $Settings) { return }
    $Settings.IgnoredUpdates = @($Settings.IgnoredUpdates) + @([pscustomobject]@{
        Device = $Candidate.Device; NewVersion = $Candidate.NewVersion; Date = (Get-Date).ToString('s')
    })
    Save-AppSettings -Settings $Settings
    Write-Log "Mise à jour ignorée : $($Candidate.Device) $($Candidate.NewVersion)"
}

function Remove-IgnoredUpdate {
    param([Parameter(Mandatory)][string]$Device, [string]$NewVersion, [Parameter(Mandatory)][object]$Settings)
    $Settings.IgnoredUpdates = @($Settings.IgnoredUpdates | Where-Object { -not ($_.Device -eq $Device -and $_.NewVersion -eq $NewVersion) })
    Save-AppSettings -Settings $Settings
    Write-Log "Mise à jour de nouveau proposée : $Device $NewVersion"
}

# =============================================================================
#  Progression des tâches de fond (lue par la fenêtre toutes les 500 ms)
# =============================================================================

function Set-TaskProgress {
    param([string]$Stage, [int]$Percent = -1, [string]$Detail)
    try {
        $json = [pscustomobject]@{ Stage = $Stage; Percent = $Percent; Detail = $Detail } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($script:ProgressFile, $json)
    } catch { }   # la fenêtre lit peut-être le fichier au même moment : sans gravité
}

function Get-TaskProgress {
    if (-not (Test-Path -Path $script:ProgressFile)) { return $null }
    try { return ([IO.File]::ReadAllText($script:ProgressFile) | ConvertFrom-Json) } catch { return $null }
}

function Clear-TaskProgress {
    Remove-Item -Path $script:ProgressFile -Force -ErrorAction SilentlyContinue
}

function Invoke-FileDownload {
    <#
        Téléchargement par blocs de 1 Mo, avec progression (%, Mo, Mo/s) pour la fenêtre.
        3 tentatives (attente de 3 puis 6 secondes) : les serveurs répondent parfois
        « 504 Gateway Time-out » de façon passagère.
    #>
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$OutFile,
          [string]$Label = 'fichier', [string]$Accept, [int]$Attempts = 3)

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Invoke-FileDownloadOnce -Url $Url -OutFile $OutFile -Label $Label -Accept $Accept
            return
        } catch {
            Write-Log "Téléchargement de $Label : tentative $i/$Attempts échouée ($($_.Exception.Message))" 'WARN'
            Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
            if ($i -eq $Attempts) { throw }
            Set-TaskProgress -Stage (T 'StageDownload' $Label) -Detail (T 'StageRetry' (3 * $i))
            Start-Sleep -Seconds (3 * $i)
        }
    }
}

function Invoke-FileDownloadOnce {
    param([string]$Url, [string]$OutFile, [string]$Label, [string]$Accept)

    $request = [System.Net.HttpWebRequest]::Create($Url)
    if ($Accept) { $request.Accept = $Accept }
    $request.UserAgent        = $script:UserAgent
    $request.Timeout          = 30000
    $request.ReadWriteTimeout = 60000
    $response = $request.GetResponse()
    try {
        $total  = $response.ContentLength
        $stream = $response.GetResponseStream()
        $output = [IO.File]::Create($OutFile)
        try {
            $buffer = New-Object byte[] (1MB)
            $done   = 0L
            $watch  = [Diagnostics.Stopwatch]::StartNew()
            $last   = -1000
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $output.Write($buffer, 0, $read)
                $done += $read
                if (($watch.ElapsedMilliseconds - $last) -ge 500) {
                    $last  = $watch.ElapsedMilliseconds
                    $speed = $done / 1MB / [math]::Max($watch.Elapsed.TotalSeconds, 0.001)
                    if ($total -gt 0) {
                        $pct    = [int][math]::Floor($done * 100 / $total)
                        $detail = '{0} % · {1:N0} / {2:N0} {4} · {3:N1} {4}/s' -f $pct, ($done / 1MB), ($total / 1MB), $speed, (T 'UnitMB')
                    } else {
                        $pct    = -1
                        $detail = '{0:N0} {2} · {1:N1} {2}/s' -f ($done / 1MB), $speed, (T 'UnitMB')
                    }
                    Set-TaskProgress -Stage (T 'StageDownload' $Label) -Percent $pct -Detail $detail
                }
            }
        } finally {
            $output.Dispose()
            $stream.Dispose()
        }
    } finally {
        $response.Dispose()
    }
    Write-Log ("Téléchargé : {0} ({1:N0} Mo)" -f $Label, ((Get-Item $OutFile).Length / 1MB))
}

# =============================================================================
#  Nettoyage : journaux et téléchargements de plus de 30 jours
#  (les sauvegardes de pilotes ont leur propre limite, voir Backup.ps1)
# =============================================================================

function Clear-OldFiles {
    param([int]$Days = 30)
    $limit = (Get-Date).AddDays(-$Days)
    $old = @()
    $old += @(Get-ChildItem -Path $script:LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit })
    $old += @(Get-ChildItem -Path $script:DownloadDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit })
    if ($old.Count -eq 0) { return }

    $sizeMB = ($old | Measure-Object -Property Length -Sum).Sum / 1MB
    $old | Remove-Item -Force -ErrorAction SilentlyContinue
    # Dossiers devenus vides (les plus profonds d'abord)
    Get-ChildItem -Path $script:DownloadDir -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not (Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log ("Nettoyage : {0} fichier(s) de plus de {1} jours supprimé(s) ({2:N0} Mo libérés)" -f $old.Count, $Days, $sizeMB)
}
