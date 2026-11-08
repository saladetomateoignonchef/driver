# =============================================================================
#  History.ps1 - Historique des installations + rapport HTML
#  (C:\ProgramData\DriverUpdater\history.json, 500 dernières entrées)
# =============================================================================

function Get-DriverHistory {
    <# Historique, le plus récent d'abord. #>
    if (-not (Test-Path -Path $script:HistoryFile)) { return @() }
    try {
        # PowerShell 5.1 : ConvertFrom-Json renvoie un tableau JSON comme UN seul objet ;
        # le passer dans le pipeline depuis une variable l'éclate en éléments.
        $raw = Get-Content -Path $script:HistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($raw | Where-Object { $_ } | Sort-Object { [datetime]$_.Date } -Descending)
    } catch {
        Write-Log "Historique illisible : $($_.Exception.Message)" 'WARN'
        return @()
    }
}

function Add-HistoryEntry {
    param(
        [string]$Type = 'Installation',   # Installation | Paquet | Retour arrière
        [string]$Device, [string]$Source, [string]$OldVersion, [string]$NewVersion,
        [bool]$Success, [string]$Message
    )
    $entry = [pscustomobject]@{
        Date = (Get-Date).ToString('s'); Type = $Type; Device = $Device; Source = $Source
        OldVersion = $OldVersion; NewVersion = $NewVersion; Success = $Success; Message = $Message
    }
    $all = @(Get-DriverHistory) | Sort-Object { [datetime]$_.Date }
    $all = @($all) + @($entry) | Select-Object -Last 500
    ConvertTo-Json -InputObject @($all) -Depth 3 | Set-Content -Path $script:HistoryFile -Encoding UTF8
}

function Export-DriverReport {
    <# Rapport HTML autonome : PC, composants, pilotes installés, historique. Renvoie le chemin du fichier. #>
    param([string]$Path)

    if (-not $Path) {
        $Path = Join-Path ([Environment]::GetFolderPath('Desktop')) ('Driver-rapport-{0:yyyy-MM-dd_HHmm}.html' -f (Get-Date))
    }
    function E([object]$Text) { return [System.Net.WebUtility]::HtmlEncode([string]$Text) }

    $os    = (Get-CimInstance Win32_OperatingSystem).Caption
    $cpu   = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $ram   = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $board = Get-MotherboardInfo
    $gpu   = (Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\*' } | Select-Object -First 1)

    $drivers = @(Get-VendorDriverList)
    $history = @(Get-DriverHistory)
    $okCount = @($history | Where-Object { $_.Success }).Count

    $histRows = ($history | ForEach-Object {
        $state = if ($_.Success) { "<span class='ok'>$(E (T 'RepOk'))</span>" } else { "<span class='ko'>$(E (T 'RepFail'))</span>" }
        $date = ([datetime]$_.Date).ToString('dd/MM/yyyy HH:mm')
        "<tr><td>$(E $date)</td><td>$(E $_.Type)</td><td>$(E $_.Device)</td>" +
        "<td class='mono'>$(E $_.OldVersion)</td><td class='mono'>$(E $_.NewVersion)</td><td>$state</td><td class='muted'>$(E $_.Message)</td></tr>"
    }) -join "`n"
    if (-not $histRows) { $histRows = "<tr><td colspan='7' class='muted'>$(E (T 'NoHistory'))</td></tr>" }

    $drvRows = ($drivers | ForEach-Object {
        "<tr><td>$(E $_.Name)</td><td>$(E $_.Manufacturer)</td><td class='mono'>$(E $_.DriverVersion)</td><td>$(E $_.Class)</td></tr>"
    }) -join "`n"

    $html = @"
<!doctype html>
<html lang="$($script:Language)"><head><meta charset="utf-8"><title>$(E (T 'RepTitle')) - $(E $env:COMPUTERNAME)</title>
<style>
 body{font-family:'Segoe UI',sans-serif;background:#f4f6f8;color:#17202a;margin:0;padding:32px}
 .wrap{max-width:1100px;margin:auto}
 header{background:#12263a;color:#fff;border-radius:14px;padding:24px 28px;display:flex;justify-content:space-between;align-items:center}
 header h1{margin:0;font-size:24px} header p{margin:4px 0 0;color:#b8c7d6}
 .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0}
 .card{background:#fff;border:1px solid #e3e8ed;border-radius:12px;padding:14px 16px}
 .card small{color:#5d6b78;display:block} .card b{font-size:15px}
 h2{font-size:17px;margin:28px 0 10px}
 table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e3e8ed;border-radius:12px;overflow:hidden;font-size:13px}
 th{background:#f8fafc;color:#5d6b78;text-align:left;padding:10px 12px;border-bottom:1px solid #e3e8ed}
 td{padding:9px 12px;border-bottom:1px solid #eef1f4;vertical-align:top}
 .mono{font-family:Consolas,monospace} .muted{color:#5d6b78} .ok{color:#166534;font-weight:600} .ko{color:#b91c1c;font-weight:600}
 footer{margin-top:24px;color:#5d6b78;font-size:12px}
</style></head><body><div class="wrap">
<header><div><h1>$(E (T 'RepTitle'))</h1><p>$(E $env:COMPUTERNAME) · $(E (T 'RepGenerated' (Get-Date -Format 'dd/MM/yyyy HH:mm')))</p></div><div>Driver v$(E $script:AppVersion)</div></header>
<div class="grid">
 <div class="card"><small>$(E (T 'RepSystem'))</small><b>$(E $os)</b></div>
 <div class="card"><small>$(E (T 'HwBoard'))</small><b>$(E $board.Manufacturer) $(E $board.Product)</b></div>
 <div class="card"><small>$(E (T 'HwCpu'))</small><b>$(E $cpu)</b></div>
 <div class="card"><small>$(E (T 'HwGpu')) · $(E (T 'HwRam'))</small><b>$(E $gpu.Name) · $(E (T 'RamGB' $ram))</b></div>
</div>
<h2>$(E (T 'RepHistory' $history.Count $okCount))</h2>
<table><tr><th>$(E (T 'ColDate'))</th><th>$(E (T 'ColType'))</th><th>$(E (T 'ColDriver'))</th><th>$(E (T 'ColBefore'))</th><th>$(E (T 'ColAfter'))</th><th>$(E (T 'ColResult'))</th><th>$(E (T 'RepDetail'))</th></tr>
$histRows
</table>
<h2>$(E (T 'RepDrivers' $drivers.Count))</h2>
<table><tr><th>$(E (T 'ColDevice'))</th><th>$(E (T 'ColManufacturer'))</th><th>$(E (T 'ColInstalled'))</th><th>$(E (T 'ColType'))</th></tr>
$drvRows
</table>
<footer>$(E (T 'RepFooter')) — https://github.com/$(Get-UpdateRepo)</footer>
</div></body></html>
"@
    Set-Content -Path $Path -Value $html -Encoding UTF8
    Write-Log "Rapport exporté : $Path"
    return $Path
}
