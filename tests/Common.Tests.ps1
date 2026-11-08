# Tests unitaires (Pester 5) : Invoke-Pester .\tests
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\Common.ps1')
}

Describe 'ConvertTo-NvidiaVersion' {
    It 'convertit 32.0.16.1088 en 610.88' {
        ConvertTo-NvidiaVersion -WindowsVersion '32.0.16.1088' | Should -Be '610.88'
    }
    It 'convertit 32.0.15.6094 en 560.94' {
        ConvertTo-NvidiaVersion -WindowsVersion '32.0.15.6094' | Should -Be '560.94'
    }
    It 'renvoie $null pour une version trop courte' {
        ConvertTo-NvidiaVersion -WindowsVersion '1.2' | Should -BeNullOrEmpty
    }
}

Describe 'Get-VersionFromText' {
    It 'extrait la version en fin de titre Windows Update' {
        Get-VersionFromText -Text 'Intel - System - 10.1.31.2' | Should -Be '10.1.31.2'
    }
    It 'renvoie $null sans version' {
        Get-VersionFromText -Text 'Pilote sans version' | Should -BeNullOrEmpty
    }
}

Describe 'Compare-DriverVersion' {
    It 'détecte une version plus récente' { Compare-DriverVersion -A '612.10' -B '610.88' | Should -Be 1 }
    It 'détecte une égalité'               { Compare-DriverVersion -A '610.88' -B '610.88' | Should -Be 0 }
    It 'détecte une version plus ancienne' { Compare-DriverVersion -A '566.36' -B '610.88' | Should -Be -1 }
}
