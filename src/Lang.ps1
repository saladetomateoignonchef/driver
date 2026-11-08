# =============================================================================
#  Lang.ps1 - Traductions (français / anglais)
#
#  Les textes affichés sont dans src/lang/fr.json et src/lang/en.json.
#  - Dans le code : T 'Clé' [valeurs...]       ex. T 'UpdatesCount' 3
#  - Dans MainWindow.xaml : {DynamicResource L_Clé}  (remplacé au changement de langue)
#  Une clé absente de la langue choisie est prise en français.
#  Les journaux (logs) restent en français.
# =============================================================================

$script:LangDir  = Join-Path $PSScriptRoot 'lang'
$script:Strings  = @{}
$script:Language = 'fr'

function Read-LangFile([string]$Code) {
    $file  = Join-Path $script:LangDir "$Code.json"
    $table = @{}
    if (Test-Path $file) {
        $json = Get-Content -Path $file -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $table[$p.Name] = [string]$p.Value }
    }
    return $table
}

function Initialize-Language([string]$Code) {
    if ($Code -notin @('fr', 'en')) { $Code = 'fr' }
    $strings = Read-LangFile 'fr'
    if ($Code -ne 'fr') {
        $overlay = Read-LangFile $Code
        foreach ($k in @($overlay.Keys)) { $strings[$k] = $overlay[$k] }
    }
    $script:Strings  = $strings
    $script:Language = $Code
}

function T {
    <# Texte traduit. Les valeurs remplacent {0}, {1}... #>
    param([Parameter(Mandatory, Position = 0)][string]$Key, [Parameter(ValueFromRemainingArguments)]$Values)
    $text = $script:Strings[$Key]
    if (-not $text) { return $Key }
    if ($Values -and @($Values).Count) { return ($text -f [object[]]@($Values)) }
    return $text
}

Initialize-Language ((Get-AppSettings).Language)
