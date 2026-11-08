# Tests unitaires (Pester 5) : configuration matérielle et liens
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\Common.ps1')
    . (Join-Path $PSScriptRoot '..\src\Inventory.ps1')
    . (Join-Path $PSScriptRoot '..\src\Profile.ps1')
    . (Join-Path $PSScriptRoot '..\src\Links.ps1')

    $inventory = @(
        [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 3060'; Manufacturer = 'NVIDIA'; Class = 'DISPLAY'; HardwareId = 'PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA&REV_A1' }
        [pscustomobject]@{ Name = 'Realtek High Definition Audio'; Manufacturer = 'Microsoft'; Class = 'MEDIA'; HardwareId = 'HDAUDIO\FUNC_01&VEN_10EC&DEV_0897&SUBSYS_1458A194&REV_1004' }
        [pscustomobject]@{ Name = 'G733'; Manufacturer = 'Logitech'; Class = 'USB'; HardwareId = 'USB\VID_046D&PID_0AFE&REV_0100' }
        [pscustomobject]@{ Name = 'HID Keyboard Device'; Manufacturer = '(Standard keyboards)'; Class = 'KEYBOARD'; HardwareId = 'HID\VID_258A&PID_0049' }
        [pscustomobject]@{ Name = 'USB Input Device'; Manufacturer = '(Standard system devices)'; Class = 'HIDCLASS'; HardwareId = 'USB\VID_258A&PID_0049&MI_00' }
        [pscustomobject]@{ Name = 'USB Root Hub (USB 3.0)'; Manufacturer = '(Standard USB HUBs)'; Class = 'USB'; HardwareId = 'USB\ROOT_HUB30' }
        [pscustomobject]@{ Name = 'Volume'; Manufacturer = 'Microsoft'; Class = 'VOLUME'; HardwareId = 'STORAGE\Volume' }
    )
}

Describe 'Select-PhysicalDevice' {
    It 'garde les cartes PCI, puces audio et appareils USB' {
        $names = @(Select-PhysicalDevice -Inventory $inventory | ForEach-Object { $_.Name })
        $names | Should -Contain 'NVIDIA GeForce RTX 3060'
        $names | Should -Contain 'Realtek High Definition Audio'
        $names | Should -Contain 'G733'
    }
    It 'écarte claviers/souris HID, concentrateurs USB et éléments logiciels' {
        $names = @(Select-PhysicalDevice -Inventory $inventory | ForEach-Object { $_.Name })
        $names | Should -Not -Contain 'HID Keyboard Device'
        $names | Should -Not -Contain 'USB Input Device'
        $names | Should -Not -Contain 'USB Root Hub (USB 3.0)'
        $names | Should -Not -Contain 'Volume'
    }
}

Describe 'Compare-HardwareProfile' {
    It 'détecte le matériel ajouté et retiré' {
        $config = [pscustomobject]@{ Devices = @(
            [pscustomobject]@{ Name = 'Ancienne carte'; HardwareId = 'PCI\VEN_1002&DEV_73DF' }
            [pscustomobject]@{ Name = 'G733'; HardwareId = 'USB\VID_046D&PID_0AFE&REV_0100' }
        ) }
        $diff = Compare-HardwareProfile -Config $config -CurrentDevices @(Select-PhysicalDevice -Inventory $inventory)
        @($diff.Added | ForEach-Object { $_.Name }) | Should -Contain 'NVIDIA GeForce RTX 3060'
        @($diff.Added | ForEach-Object { $_.Name }) | Should -Not -Contain 'G733'
        @($diff.Removed | ForEach-Object { $_.Name }) | Should -Be @('Ancienne carte')
    }
}

Describe 'Liens' {
    It 'valide les adresses' {
        Test-LinkUrl 'https://www.nvidia.com/fr-fr/drivers/' | Should -BeTrue
        Test-LinkUrl 'www.nvidia.com' | Should -BeFalse
        Test-LinkUrl 'https://' | Should -BeFalse
    }
    It 'choisit la page officielle du constructeur' {
        Get-VendorDriverPage 'NVIDIA GeForce RTX 3060' | Should -Match 'nvidia\.com'
        Get-VendorDriverPage '11th Gen Intel(R) Core(TM) i5-11400F' | Should -Match 'intel\.'
        Get-VendorDriverPage 'AMD Radeon RX 6700 XT' | Should -Match 'amd\.com'
        Get-VendorDriverPage 'Realtek PCIe GbE' | Should -Match 'bing\.com/search'
    }
    It 'crée les liens automatiques depuis une configuration' {
        $config = [pscustomobject]@{
            System = [pscustomobject]@{
                Board = [pscustomobject]@{ Manufacturer = 'Gigabyte Technology Co., Ltd.'; Product = 'H510M H V2'; Version = 'x.x' }
                Gpus = @('NVIDIA GeForce RTX 3060'); Processor = '11th Gen Intel(R) Core(TM) i5-11400F'
            }
            Devices = @(Select-PhysicalDevice -Inventory $inventory)
        }
        $links = @(Get-DefaultLinks -Config $config)
        ($links | Where-Object Category -eq 'Carte mère').Url | Should -Be 'https://www.gigabyte.com/fr/Motherboard/H510M-H-V2-rev-10/support'
        ($links | Where-Object Category -eq 'Carte graphique').Url | Should -Be 'https://www.nvidia.com/fr-fr/drivers/'
        @($links | Where-Object Category -eq 'Périphérique').Count | Should -BeGreaterThan 0
        @($links | Where-Object { -not $_.Auto }).Count | Should -Be 0
    }
}
