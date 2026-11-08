# Tests unitaires (Pester 5) : paramètres, mises à jour ignorées, identifiants matériels
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\Common.ps1')
    . (Join-Path $PSScriptRoot '..\src\Backup.ps1')
}

Describe 'Test-CheckDue' {
    BeforeAll { $now = [datetime]'2026-11-08T12:00:00' }
    It 'au démarrage : toujours' {
        Test-CheckDue -Settings ([pscustomobject]@{ CheckFrequency = 'Startup'; LastCheck = $now.ToString('s') }) -Now $now | Should -BeTrue
    }
    It 'jamais : jamais' {
        Test-CheckDue -Settings ([pscustomobject]@{ CheckFrequency = 'Never'; LastCheck = $null }) -Now $now | Should -BeFalse
    }
    It 'une fois par jour : pas deux fois dans la journée' {
        Test-CheckDue -Settings ([pscustomobject]@{ CheckFrequency = 'Daily'; LastCheck = $now.AddHours(-3).ToString('s') }) -Now $now | Should -BeFalse
    }
    It 'une fois par jour : le lendemain oui' {
        Test-CheckDue -Settings ([pscustomobject]@{ CheckFrequency = 'Daily'; LastCheck = $now.AddDays(-1).ToString('s') }) -Now $now | Should -BeTrue
    }
    It 'une fois par semaine : jamais vérifié -> oui' {
        Test-CheckDue -Settings ([pscustomobject]@{ CheckFrequency = 'Weekly'; LastCheck = $null }) -Now $now | Should -BeTrue
    }
    It 'une fois par semaine : 3 jours après -> non' {
        Test-CheckDue -Settings ([pscustomobject]@{ CheckFrequency = 'Weekly'; LastCheck = $now.AddDays(-3).ToString('s') }) -Now $now | Should -BeFalse
    }
}

Describe 'Test-UpdateIgnored' {
    BeforeAll {
        $settings = [pscustomobject]@{ IgnoredUpdates = @([pscustomobject]@{ Device = 'Voice Clarity'; NewVersion = '1.0.4.55794' }) }
    }
    It 'ignore la version choisie' {
        Test-UpdateIgnored -Candidate ([pscustomobject]@{ Device = 'Voice Clarity'; NewVersion = '1.0.4.55794' }) -Settings $settings | Should -BeTrue
    }
    It 'repropose une version plus récente' {
        Test-UpdateIgnored -Candidate ([pscustomobject]@{ Device = 'Voice Clarity'; NewVersion = '1.0.5.1' }) -Settings $settings | Should -BeFalse
    }
    It 'ne touche pas aux autres pilotes' {
        Test-UpdateIgnored -Candidate ([pscustomobject]@{ Device = 'NVIDIA GeForce RTX 3060'; NewVersion = '621.14' }) -Settings $settings | Should -BeFalse
    }
}

Describe 'Get-HardwareIdVariant' {
    It 'va du plus précis au plus général (PCI)' {
        $v = Get-HardwareIdVariant -HardwareId 'PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA&REV_A1'
        $v[0]  | Should -Be 'PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA&REV_A1'
        $v     | Should -Contain 'PCI\VEN_10DE&DEV_2504&REV_A1'
        $v[-1] | Should -Be 'PCI\VEN_10DE&DEV_2504'
    }
    It 'gère les identifiants USB' {
        Get-HardwareIdVariant -HardwareId 'USB\VID_2357&PID_0604&REV_0200' | Should -Contain 'USB\VID_2357&PID_0604'
    }
}

Describe 'Get-SafeName' {
    It 'retire les caractères interdits dans un nom de dossier' {
        Get-SafeName 'Realtek: Audio/HD*' | Should -Be 'Realtek_ Audio_HD_'
    }
}
