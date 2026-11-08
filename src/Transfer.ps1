# =============================================================================
#  Transfer.ps1 - Export / import de tous les réglages dans un seul fichier
#  (paramètres, liens, configuration matérielle) : pour réinstaller Windows ou
#  copier ses réglages sur un autre PC.
# =============================================================================

function Export-AppSettings {
    param([Parameter(Mandatory)][string]$Path)
    $settings = Get-AppSettings
    $settings.LastCheck = $null
    $data = [pscustomobject]@{
        App           = 'Driver'
        Version       = $script:AppVersion
        Date          = (Get-Date).ToString('s')
        Computer      = $env:COMPUTERNAME
        Settings      = $settings
        Links         = @(Get-AppLinks)
        Configuration = Get-CurrentHardwareProfile
    }
    $data | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
    Write-Log "Réglages exportés : $Path"
}

function Read-AppSettingsFile {
    <# Lit et vérifie un fichier exporté. #>
    param([Parameter(Mandatory)][string]$Path)
    $data = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.App -ne 'Driver' -or -not $data.Settings) { throw (T 'ImportInvalidFile') }
    return $data
}

function Import-AppSettings {
    param([Parameter(Mandatory)][object]$Data, [switch]$IncludeConfiguration)

    # Paramètres : seules les clés connues sont reprises
    $settings = Get-AppSettings
    foreach ($p in $Data.Settings.PSObject.Properties) {
        if ($p.Name -ne 'LastCheck' -and $settings.PSObject.Properties[$p.Name]) { $settings.($p.Name) = $p.Value }
    }
    $settings.IgnoredUpdates = @($settings.IgnoredUpdates | Where-Object { $_ })
    Save-AppSettings -Settings $settings

    $links = @($Data.Links | Where-Object { $_ -and $_.Name -and $_.Url })
    if ($links.Count) { Save-AppLinks -Links $links }

    if ($IncludeConfiguration -and $Data.Configuration) {
        $config = $Data.Configuration
        $config.Date = (Get-Date).ToString('s')     # devient la configuration la plus récente
        [void](Save-HardwareProfile -Snapshot $config -SkipCsv)
    }
    Write-Log ("Réglages importés depuis {0} (PC d'origine : {1}, liens : {2}, configuration : {3})" -f `
        $Data.Date, $Data.Computer, $links.Count, [bool]($IncludeConfiguration -and $Data.Configuration))
}
