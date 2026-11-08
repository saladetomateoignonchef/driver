# =============================================================================
#  Inventory.ps1 - Inventaire du matériel et des pilotes installés (WMI/CIM)
# =============================================================================

function Get-DeviceInventory {
    <#
        Interroge la classe WMI Win32_PnPSignedDriver et renvoie, pour chaque
        périphérique : nom, classe, version du pilote, identifiant matériel,
        identifiant constructeur (VEN_/VID_) et identifiant produit (DEV_/PID_).
    #>
    Get-CimInstance -ClassName Win32_PnPSignedDriver |
        Where-Object { $_.DeviceName -and $_.HardWareID } |
        ForEach-Object {
            $hwid     = [string]$_.HardWareID
            $vendorId = $null
            $deviceId = $null
            if ($hwid -match '(?:VEN|VID)_([0-9A-Fa-f]{4})') { $vendorId = $Matches[1].ToUpper() }
            if ($hwid -match '(?:DEV|PID)_([0-9A-Fa-f]{4})') { $deviceId = $Matches[1].ToUpper() }

            [pscustomobject]@{
                Name          = $_.DeviceName
                Manufacturer  = $_.Manufacturer
                Class         = $_.DeviceClass
                DriverVersion = $_.DriverVersion
                DriverDate    = $_.DriverDate
                HardwareId    = $hwid
                VendorId      = $vendorId
                DeviceId      = $deviceId
            }
        }
}

function Find-InventoryDevice {
    <# Retrouve un périphérique de l'inventaire à partir d'un Hardware ID (Windows Update). #>
    param([object[]]$Inventory, [string]$HardwareId)
    if (-not $HardwareId) { return $null }
    $Inventory | Where-Object { $_.HardwareId -like "$HardwareId*" } | Select-Object -First 1
}
