# Tests unitaires (Pester 5) : traductions
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\Common.ps1')
    . (Join-Path $PSScriptRoot '..\src\Lang.ps1')
    $langDir = Join-Path $PSScriptRoot '..\src\lang'
    function Get-Keys([string]$Code) {
        @((Get-Content (Join-Path $langDir "$Code.json") -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $_.Name })
    }
}

Describe 'Traductions' {
    It 'le français et l''anglais ont exactement les mêmes clés' {
        $fr = Get-Keys 'fr'; $en = Get-Keys 'en'
        @($fr | Where-Object { $en -notcontains $_ }) | Should -BeNullOrEmpty
        @($en | Where-Object { $fr -notcontains $_ }) | Should -BeNullOrEmpty
    }
    It 'toutes les clés utilisées dans MainWindow.xaml existent' {
        $xaml = Get-Content (Join-Path $PSScriptRoot '..\src\MainWindow.xaml') -Raw -Encoding UTF8
        $used = @([regex]::Matches($xaml, 'L_(\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $fr = Get-Keys 'fr'
        @($used | Where-Object { $fr -notcontains $_ }) | Should -BeNullOrEmpty
    }
    It 'traduit en français' {
        Initialize-Language 'fr'
        T 'BtnSearch' | Should -Be 'Analyser'
        T 'GitHubUpToDate' '2.2.0' | Should -Be 'Votre logiciel est à jour (version 2.2.0).'
    }
    It 'traduit en anglais avec plusieurs valeurs' {
        Initialize-Language 'en'
        T 'BtnGitHubUpdate' | Should -Be 'GitHub update'
        T 'OpsResult' 2 3 | Should -Be '2 of 3 operation(s) succeeded.'
    }
    It 'renvoie la clé si elle est inconnue, et le français pour une langue inconnue' {
        Initialize-Language 'de'
        T 'CleQuiNExistePas' | Should -Be 'CleQuiNExistePas'
        T 'BtnSearch' | Should -Be 'Analyser'
    }
}
