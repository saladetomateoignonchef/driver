# =============================================================================
#  Profile.ps1 - Configuration matérielle enregistrée
#
#  Au premier lancement, Driver analyse le matériel (même principe que le tout
#  premier script : Win32_PnPSignedDriver) et enregistre cette "configuration"
#  dans C:\ProgramData\DriverUpdater\configurations :
#    - configuration-AAAAMMJJ-HHMMSS.json  (lu par Driver)
#    - configuration-AAAAMMJJ-HHMMSS.csv   (lisible dans Excel / Notepad++)
#  Les recherches de mises à jour se basent sur la dernière configuration :
#  un matériel ajouté depuis est signalé ("Nouveau matériel") et n'est pris en
#  compte qu'après l'enregistrement d'une nouvelle configuration.
# =============================================================================

$script:ProfileDir  = Join-Path $script:DataDir 'configurations'
$script:ProfileKeep = 10     # nombre de configurations gardées

function Select-PhysicalDevice {
    <#
        Garde le matériel "réel" : cartes PCI, puces audio, appareils USB.
        On écarte les sous-éléments (clavier/souris HID, concentrateurs USB) et
        tout ce qui est purement logiciel (volumes, files d'impression...).
    #>
    param([object[]]$Inventory)
    $Inventory |
        Where-Object {
            $_.HardwareId -match '^(PCI|HDAUDIO|USB)\\' -and
            $_.HardwareId -notmatch 'ROOT_HUB' -and
            $_.Class -notin @('HIDCLASS', 'KEYBOARD', 'MOUSE')
        } |
        Sort-Object HardwareId -Unique
}

function Get-HardwareSnapshot {
    <# Photo complète du matériel actuel (système + périphériques). #>
    $inventory = @(Get-DeviceInventory)
    $os    = Get-CimInstance Win32_OperatingSystem
    $cs    = Get-CimInstance Win32_ComputerSystem
    $cpu   = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus  = @(Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\*' } | ForEach-Object { $_.Name })
    $board = Get-MotherboardInfo

    [pscustomobject]@{
        Date     = (Get-Date).ToString('s')
        Computer = $env:COMPUTERNAME
        System   = [pscustomobject]@{
            OS        = "$($os.Caption) (build $($os.BuildNumber))"
            Processor = ([string]$cpu.Name).Trim()
            RamGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB)
            Board     = $board
            Gpus      = $gpus
        }
        Devices  = @(Select-PhysicalDevice -Inventory $inventory | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name; Manufacturer = $_.Manufacturer; Class = $_.Class
                HardwareId = $_.HardwareId; DriverVersion = $_.DriverVersion
            }
        })
        AllDevices = $inventory.Count
    }
}

function Save-HardwareProfile {
    <# Enregistre la configuration (JSON + CSV) et ne garde que les $ProfileKeep dernières. #>
    param([Parameter(Mandatory)][object]$Snapshot, [switch]$SkipCsv)
    if (-not (Test-Path $script:ProfileDir)) { New-Item -ItemType Directory -Path $script:ProfileDir -Force | Out-Null }

    $base = Join-Path $script:ProfileDir ('configuration-{0:yyyyMMdd-HHmmss}' -f [datetime]$Snapshot.Date)
    $Snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path "$base.json" -Encoding UTF8 -ErrorAction Stop
    # Même format que le tout premier script (lisible dans Excel)
    if (-not $SkipCsv) {
        @(Get-DeviceInventory) | Select-Object Name, Manufacturer, DriverVersion, DriverDate, Class, HardwareId |
            Export-Csv -Path "$base.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }

    $old = @(Get-ChildItem -Path $script:ProfileDir -Filter 'configuration-*.json' | Sort-Object Name -Descending | Select-Object -Skip $script:ProfileKeep)
    foreach ($f in $old) {
        Remove-Item -Path $f.FullName, ($f.FullName -replace '\.json$', '.csv') -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Configuration matérielle enregistrée : $base.json ($(@($Snapshot.Devices).Count) périphériques)"
    return "$base.json"
}

function Get-HardwareProfileList {
    <# Configurations enregistrées, la plus récente d'abord. #>
    foreach ($f in @(Get-ChildItem -Path $script:ProfileDir -Filter 'configuration-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        try {
            # Rapide : la date vient du nom du fichier, le nombre de périphériques d'un simple comptage
            # (lire et décoder les 10 fichiers JSON en entier rendait la page lente)
            $date  = [datetime]::ParseExact(($f.BaseName -replace '^configuration-', ''), 'yyyyMMdd-HHmmss', $null)
            $count = ([regex]::Matches([IO.File]::ReadAllText($f.FullName), '"HardwareId"')).Count
            [pscustomobject]@{ Path = $f.FullName; Csv = ($f.FullName -replace '\.json$', '.csv'); Date = $date; Count = $count }
        } catch { }
    }
}

function Get-CurrentHardwareProfile {
    $last = Get-ChildItem -Path $script:ProfileDir -Filter 'configuration-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $last) { return $null }
    try { return (Get-Content -Path $last.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Initialize-HardwareProfile {
    <# Premier lancement : crée la configuration. Renvoie $true si elle vient d'être créée. #>
    if (Get-CurrentHardwareProfile) { return $false }
    Write-Log 'Premier lancement : analyse complète du matériel'
    [void](Save-HardwareProfile -Snapshot (Get-HardwareSnapshot))
    return $true
}

function Compare-HardwareProfile {
    <# Différences entre la configuration enregistrée et le matériel actuel. #>
    param([object]$Config, [object[]]$CurrentDevices)
    $known   = @($Config.Devices | ForEach-Object { $_.HardwareId })
    $current = @($CurrentDevices | ForEach-Object { $_.HardwareId })
    [pscustomobject]@{
        Added   = @($CurrentDevices | Where-Object { $known -notcontains $_.HardwareId })
        Removed = @($Config.Devices | Where-Object { $current -notcontains $_.HardwareId })
    }
}

function Get-WatchedInventory {
    <#
        Inventaire utilisé pour les recherches : tout le PC, SAUF le matériel
        physique absent de la configuration enregistrée (nouveau matériel pas
        encore validé dans « Nouveau matériel »).
    #>
    param([object[]]$Inventory)
    if (-not $Inventory) { $Inventory = @(Get-DeviceInventory) }
    $config = Get-CurrentHardwareProfile
    if (-not $config) { return [pscustomobject]@{ Inventory = $Inventory; NewHardware = @() } }
    $new = @((Compare-HardwareProfile -Config $config -CurrentDevices @(Select-PhysicalDevice -Inventory $Inventory)).Added)
    $newIds = @($new | ForEach-Object { $_.HardwareId })
    [pscustomobject]@{
        Inventory   = @($Inventory | Where-Object { $newIds -notcontains $_.HardwareId })
        NewHardware = $new
    }
}
