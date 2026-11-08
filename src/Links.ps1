# =============================================================================
#  Links.ps1 - Sites de support des composants (modifiables)
#  (C:\ProgramData\DriverUpdater\links.json)
#
#  Les liens "automatiques" sont créés à partir de la configuration matérielle
#  (carte mère, carte graphique, processeur, audio, réseau, périphériques).
#  Chaque lien peut être modifié dans « Liens » : un lien modifié devient
#  "manuel" et n'est plus jamais remplacé automatiquement.
# =============================================================================

$script:LinksFile = Join-Path $script:DataDir 'links.json'

function Get-SearchUrl([string]$Text) {
    return 'https://www.bing.com/search?q=' + [uri]::EscapeDataString("$Text pilote")
}

function New-AppLink {
    param([string]$Category, [string]$Name, [string]$Url, [bool]$Auto = $true)
    [pscustomobject]@{ Category = $Category; Name = $Name; Url = $Url; Auto = $Auto }
}

function Get-VendorDriverPage {
    <# Page officielle de pilotes selon le constructeur, sinon une recherche web. #>
    param([string]$Text)
    switch -Regex ($Text) {
        'NVIDIA|GeForce|Quadro'  { return 'https://www.nvidia.com/fr-fr/drivers/' }
        'AMD|Radeon|Ryzen'       { return 'https://www.amd.com/fr/support/download/drivers.html' }
        'Intel'                  { return 'https://www.intel.fr/content/www/fr/fr/support/detect.html' }
        default                  { return (Get-SearchUrl $Text) }
    }
}

function Get-DefaultLinks {
    <# Liens automatiques construits à partir de la configuration matérielle. #>
    param([object]$Config)
    if (-not $Config) { $Config = Get-CurrentHardwareProfile }
    if (-not $Config) { return @() }
    $links = New-Object System.Collections.Generic.List[object]

    $b = $Config.System.Board
    if ($b -and $b.Product) {
        $maker = $b.Manufacturer -replace '\s+Technology Co\., Ltd\.?', ''
        $links.Add((New-AppLink 'Carte mère' "$maker $($b.Product)" (Get-MotherboardSupportUrl -Board $b)))
    }
    foreach ($gpu in @($Config.System.Gpus | Where-Object { $_ })) {
        $links.Add((New-AppLink 'Carte graphique' $gpu (Get-VendorDriverPage $gpu)))
    }
    if ($Config.System.Processor) {
        $links.Add((New-AppLink 'Processeur / chipset' $Config.System.Processor (Get-VendorDriverPage $Config.System.Processor)))
    }

    $kinds = @(
        @{ Category = 'Audio';       Test = { $_.Class -eq 'MEDIA' -and $_.HardwareId -like 'HDAUDIO\*' -and $_.HardwareId -notmatch 'VEN_10DE' } }
        @{ Category = 'Réseau';      Test = { $_.Class -eq 'NET' } }
        @{ Category = 'Bluetooth';   Test = { $_.Class -eq 'BLUETOOTH' } }
        @{ Category = 'Périphérique'; Test = { $_.HardwareId -like 'USB\*' -and $_.Class -notin @('BLUETOOTH', 'NET') -and $_.Manufacturer -notmatch '^(\(|Microsoft)' } }
    )
    foreach ($k in $kinds) {
        foreach ($d in @($Config.Devices | Where-Object -FilterScript $k.Test | Select-Object -First 4)) {
            $label = (($d.Name -replace '\((R|TM)\)', '') -replace '\s+', ' ').Trim()
            if ($links | Where-Object { $_.Name -eq $label }) { continue }
            $query = if ($d.Manufacturer -and $label -notmatch [regex]::Escape($d.Manufacturer)) { "$($d.Manufacturer) $label" } else { $label }
            $links.Add((New-AppLink $k.Category $label (Get-VendorDriverPage $query)))
        }
    }
    return $links.ToArray()
}

function Get-AppLinks {
    if (Test-Path -Path $script:LinksFile) {
        try {
            # PowerShell 5.1 : passer par une variable pour éclater le tableau JSON
            $raw = Get-Content -Path $script:LinksFile -Raw -Encoding UTF8 | ConvertFrom-Json
            return @($raw | Where-Object { $_ })
        } catch {
            Write-Log "Liens illisibles, liens automatiques utilisés : $($_.Exception.Message)" 'WARN'
        }
    }
    $links = @(Get-DefaultLinks)
    if ($links.Count) { Save-AppLinks -Links $links }
    return $links
}

function Save-AppLinks {
    param([object[]]$Links)
    ConvertTo-Json -InputObject @($Links) -Depth 3 | Set-Content -Path $script:LinksFile -Encoding UTF8
}

function Update-AutoLinks {
    <# Recalcule les liens automatiques (nouveau matériel) en gardant les liens manuels. #>
    param([object]$Config)
    $manual   = @(Get-AppLinks | Where-Object { -not $_.Auto })
    $names    = @($manual | ForEach-Object { $_.Name })
    $defaults = @(Get-DefaultLinks -Config $Config | Where-Object { $names -notcontains $_.Name })
    $all = @($manual) + @($defaults)
    Save-AppLinks -Links $all
    Write-Log "Liens mis à jour : $($manual.Count) manuel(s), $($defaults.Count) automatique(s)"
    return $all
}

function Test-LinkUrl([string]$Url) {
    return [bool]($Url -match '^https?://\S+\.\S+')
}
