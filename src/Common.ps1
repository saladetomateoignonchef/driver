# =============================================================================
#  Common.ps1 - Fonctions communes : dossiers, journalisation, droits, versions
# =============================================================================

$script:AppName     = 'DriverUpdater'
$script:DataDir     = Join-Path $env:ProgramData 'DriverUpdater'
$script:LogDir      = Join-Path $script:DataDir 'logs'
$script:DownloadDir = Join-Path $script:DataDir 'downloads'
$script:UserAgent   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DriverUpdater/1.0'

# Windows PowerShell 5.1 : on force TLS 1.2 pour les sites constructeurs
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Initialize-AppFolder {
    foreach ($dir in @($script:DataDir, $script:LogDir, $script:DownloadDir)) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
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
    if ($Text -match '(\d+(?:\.\d+){1,3})\s*$') { return $Matches[1] }
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
