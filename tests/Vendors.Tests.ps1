# Tests unitaires (Pester 5) : vérification sur les sites des fabricants (réseau simulé)
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\Common.ps1')
    . (Join-Path $PSScriptRoot '..\src\Lang.ps1')
    Initialize-Language 'fr'
    . (Join-Path $PSScriptRoot '..\src\Inventory.ps1')
    . (Join-Path $PSScriptRoot '..\src\Profile.ps1')
    . (Join-Path $PSScriptRoot '..\src\Links.ps1')
    . (Join-Path $PSScriptRoot '..\src\Providers\Vendors.ps1')
    Mock Set-TaskProgress { }
    Mock Write-Log { }
    Mock Get-AppLinks { @([pscustomobject]@{ Category = 'Carte mère'; Name = 'Gigabyte'; Url = 'https://www.gigabyte.com/fr/Motherboard/X/support'; Auto = $true }) }
    $inventory = @(
        [pscustomobject]@{ Name = 'Intel(R) Iris(R) Xe Graphics'; Manufacturer = 'Intel Corporation'; Class = 'DISPLAY'; VendorId = '8086'; HardwareId = 'PCI\VEN_8086&DEV_9A49&SUBSYS_0A1C1028'; DriverVersion = '32.0.101.7088' }
        [pscustomobject]@{ Name = 'Realtek PCIe GbE Family Controller'; Manufacturer = 'Realtek'; Class = 'NET'; VendorId = '10EC'; HardwareId = 'PCI\VEN_10EC&DEV_8168&SUBSYS_E0001458'; DriverVersion = '10.72.524.2024' }
    )
}

Describe 'Get-VendorCheck' {
    It 'site qui refuse les programmes : bouton proposé, aucune mise à jour automatique' {
        Mock Invoke-WebRequest { throw (New-Object System.Net.WebException('403 Forbidden')) }
        $checks = @(Get-VendorCheck -Inventory $inventory)
        $intel = $checks | Where-Object { $_.Vendor -eq 'Intel' } | Select-Object -First 1
        $intel.Status | Should -Be 'blocked'
        $intel.Url | Should -Match 'intel\.com'
        @($intel.Candidates).Count | Should -Be 0
    }
    It 'site qui répond : nouvelle version et lien direct lus sur la page' {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = 'Version 32.0.101.7088 ... Latest 32.0.101.8974 <a href="https://downloadmirror.intel.com/862356/gfx_win_101.8974.zip">ZIP</a>' } }
        $intel = @(Get-VendorCheck -Inventory $inventory) | Where-Object { $_.Vendor -eq 'Intel' } | Select-Object -First 1
        $intel.Status | Should -Be 'update'
        $c = @($intel.Candidates)[0]
        $c.NewVersion | Should -Be '32.0.101.8974'
        $c.Key | Should -Be 'https://downloadmirror.intel.com/862356/gfx_win_101.8974.zip'
        $c.Source | Should -Be 'Intel'
    }
    It 'pilote Realtek de carte mère : bouton vers la page de la carte mère' {
        Mock Invoke-WebRequest { throw (New-Object System.Net.WebException('403')) }
        $rt = @(Get-VendorCheck -Inventory $inventory) | Where-Object { $_.Vendor -eq 'Realtek' }
        $rt.Url | Should -Be 'https://www.gigabyte.com/fr/Motherboard/X/support'
        $rt.Status | Should -Be 'manual'
    }
}
