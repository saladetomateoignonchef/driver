# =============================================================================
#  Gui.ps1 - Interface graphique "tableau de bord" (WPF)
#
#  La mise en page est décrite dans MainWindow.xaml ; ce fichier la charge,
#  la remplit avec les données et réagit aux clics.
#  Les opérations longues (recherche, analyse de paquet, installation) tournent
#  dans un job PowerShell en arrière-plan ; un DispatcherTimer vérifie toutes les
#  500 ms si le job est terminé, pour que la fenêtre ne se fige jamais.
# =============================================================================

. (Join-Path $PSScriptRoot 'DropTarget.ps1')   # charge aussi WPF

# ---------- Petites fonctions d'aide pour créer des éléments WPF ----------
$script:BrushConverter = New-Object System.Windows.Media.BrushConverter
function Get-Brush([string]$Hex) { return $script:BrushConverter.ConvertFromString($Hex) }
function New-Thickness([double]$L, [double]$T, [double]$R, [double]$B) { return New-Object System.Windows.Thickness($L, $T, $R, $B) }

function New-Text {
    param([string]$Text, [double]$Size = 13, [string]$Color = '#17202A', [switch]$Bold, [switch]$SemiBold)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text         = $Text
    $tb.FontSize     = $Size
    $tb.Foreground   = Get-Brush $Color
    $tb.TextTrimming = 'CharacterEllipsis'
    if ($Bold)     { $tb.FontWeight = [System.Windows.FontWeights]::Bold }
    if ($SemiBold) { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $tb
}

# Icônes (tracés vectoriels) et couleurs par type de composant
$script:Icons = @{
    gpu     = @{ Data = 'M1.5,4 L16.5,4 L16.5,14 L1.5,14 Z M13.4,9 A2.4,2.4 0 1 1 8.6,9 A2.4,2.4 0 1 1 13.4,9'; Bg = '#ECFCCB'; Fg = '#4D7C0F' }
    audio   = @{ Data = 'M3,7 L3,11 M6,5 L6,13 M9,3 L9,15 M12,5 L12,13 M15,7 L15,11'; Bg = '#E0F2FE'; Fg = '#0369A1' }
    effect  = @{ Data = 'M3,7 L3,11 M6,5 L6,13 M9,3 L9,15 M12,5 L12,13 M15,7 L15,11'; Bg = '#F3E8FF'; Fg = '#7E22CE' }
    net     = @{ Data = 'M2,12 L16,12 M4,12 L4,6 L14,6 L14,12 M7,9 L11,9'; Bg = '#F1F5F9'; Fg = '#475569' }
    chipset = @{ Data = 'M2,2 L16,2 L16,16 L2,16 Z M6,6 L12,6 L12,12 L6,12 Z'; Bg = '#DBEAFE'; Fg = '#1D4ED8' }
    bt      = @{ Data = 'M6,5 L12,11 L9,14 L9,2 L12,5 L6,11'; Bg = '#E0E7FF'; Fg = '#4338CA' }
    storage = @{ Data = 'M2,5 L16,5 L16,13 L2,13 Z M5,9 L9,9'; Bg = '#FCE7F3'; Fg = '#BE185D' }
    other   = @{ Data = 'M3,3 L15,3 L15,15 L3,15 Z M6,7 L12,7 M6,10 L12,10'; Bg = '#F1F5F9'; Fg = '#475569' }
}

function New-IconBadge([string]$Kind, [double]$Size = 36) {
    $ic = $script:Icons[$Kind]
    if (-not $ic) { $ic = $script:Icons['other'] }
    $bd = New-Object System.Windows.Controls.Border
    $bd.Width = $Size; $bd.Height = $Size
    $bd.CornerRadius = New-Object System.Windows.CornerRadius(9)
    $bd.Background   = Get-Brush $ic.Bg
    $path = New-Object System.Windows.Shapes.Path
    $path.Data            = [System.Windows.Media.Geometry]::Parse($ic.Data)
    $path.Stroke          = Get-Brush $ic.Fg
    $path.StrokeThickness = 1.6
    $path.Width = 18; $path.Height = 18
    $path.Stretch = 'Uniform'
    $path.HorizontalAlignment = 'Center'; $path.VerticalAlignment = 'Center'
    $bd.Child = $path
    return $bd
}

function New-Pill([string]$Text, [bool]$Warn) {
    $bd = New-Object System.Windows.Controls.Border
    $bd.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $bd.Padding      = New-Thickness 10 3 10 3
    $bd.HorizontalAlignment = 'Left'
    if ($Warn) { $bd.Background = Get-Brush '#FEF3C7'; $color = '#92400E' } else { $bd.Background = Get-Brush '#DCFCE7'; $color = '#166534' }
    $bd.Child = New-Text $Text 11.5 $color -SemiBold
    return $bd
}

function New-VersionText([string]$Current, [string]$New) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.FontFamily   = New-Object System.Windows.Media.FontFamily('Consolas')
    $tb.FontSize     = 12.5
    $tb.Foreground   = Get-Brush '#5D6B78'
    $tb.TextTrimming = 'CharacterEllipsis'
    [void]$tb.Inlines.Add((New-Object System.Windows.Documents.Run([string]$Current)))
    if ($New) {
        [void]$tb.Inlines.Add((New-Object System.Windows.Documents.Run('  →  ')))
        $run = New-Object System.Windows.Documents.Run([string]$New)
        $run.Foreground = Get-Brush '#0F766E'
        $run.FontWeight = [System.Windows.FontWeights]::Bold
        [void]$tb.Inlines.Add($run)
    }
    return $tb
}

function Format-Size([double]$SizeMB) {
    if ($SizeMB -ge 1000) { return ('{0:N1} Go' -f ($SizeMB / 1024)) }
    if ($SizeMB -gt 0)    { return ('{0:N0} Mo' -f $SizeMB) }
    return ''
}

function Get-ComponentList {
    <# Les composants principaux du PC, un par carte du tableau de bord. #>
    param([object[]]$Inventory)
    $rules = @(
        @{ Kind = 'gpu';     Title = 'Carte graphique'; Test = { $_.Class -eq 'DISPLAY' -and $_.HardwareId -like 'PCI\*' } }
        @{ Kind = 'audio';   Title = 'Audio';           Test = { $_.Class -eq 'MEDIA' -and $_.HardwareId -like 'HDAUDIO\*' -and $_.VendorId -ne '10DE' } }
        @{ Kind = 'net';     Title = 'Réseau';          Test = { $_.Class -eq 'NET' -and $_.HardwareId -like 'PCI\*' } }
        @{ Kind = 'chipset'; Title = 'Chipset';         Test = { $_.Class -eq 'SYSTEM' -and $_.Name -match 'LPC|Chipset' } }
        @{ Kind = 'bt';      Title = 'Bluetooth';       Test = { $_.Class -eq 'BLUETOOTH' -and $_.HardwareId -like 'USB\*' } }
        @{ Kind = 'storage'; Title = 'Stockage';        Test = { $_.Class -in @('SCSIADAPTER', 'HDC') -and $_.HardwareId -like 'PCI\*' } }
    )
    foreach ($r in $rules) {
        $dev = $Inventory | Where-Object -FilterScript $r.Test | Select-Object -First 1
        if ($dev) {
            [pscustomobject]@{
                Kind    = $r.Kind
                Title   = $r.Title
                Device  = $dev.Name
                Label   = (($dev.Name -replace '\((R|TM)\)', '') -replace '\s+', ' ').Trim()
                Version = $dev.DriverVersion
            }
        }
    }
}

function Get-KindFromClass([string]$DriverClass) {
    switch -Regex ($DriverClass) {
        'Display'         { return @{ Kind = 'gpu';     Title = 'Carte graphique' } }
        'AudioProcessing' { return @{ Kind = 'effect';  Title = 'Effets audio' } }
        'Media|Audio'     { return @{ Kind = 'audio';   Title = 'Audio' } }
        'Net'             { return @{ Kind = 'net';     Title = 'Réseau' } }
        'Bluetooth'       { return @{ Kind = 'bt';      Title = 'Bluetooth' } }
        'System'          { return @{ Kind = 'chipset'; Title = 'Système' } }
        default           { return @{ Kind = 'other';   Title = 'Pilote' } }
    }
}

function Show-MainWindow {
    param(
        [object[]]$InitialResults,   # résultats déjà trouvés (lancement au démarrage)
        [switch]$AutoSearch          # lance une recherche dès l'ouverture
    )

    # ---------- Chargement de la fenêtre ----------
    [xml]$xaml = Get-Content -Path (Join-Path $PSScriptRoot 'MainWindow.xaml') -Raw -Encoding UTF8
    $window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $ui = @{}
    foreach ($name in @('NavDashboard', 'NavUpdates', 'NavAll', 'NavPackage', 'NavBoard', 'NavLogs', 'UpdatesBadge', 'UpdatesBadgeText',
                        'PcName', 'PcInfo', 'PageTitle', 'StatusText', 'BtnSearch', 'BtnInstall', 'Busy',
                        'ViewDashboard', 'ViewUpdates', 'ViewAll', 'KpiDevices', 'KpiUpdates', 'ChkRestore',
                        'CardsPanel', 'DropZone', 'ActivityText', 'UpdatesPanel', 'UpdatesEmpty', 'AllGrid')) {
        $ui[$name] = $window.FindName($name)
    }

    $script:CurrentJob   = $null
    $script:JobKind      = $null
    $script:Updates      = @()
    $script:Inventory    = $null
    $script:UpdateChecks = New-Object System.Collections.Generic.List[object]
    $script:LastSearch   = $null
    $script:Board        = $null

    # ---------- Fonctions internes ----------
    function Show-Message([string]$Text, [string]$Title = 'Driver', [string]$Buttons = 'OK', [string]$Icon = 'Information') {
        return [System.Windows.MessageBox]::Show($window, $Text, $Title, $Buttons, $Icon)
    }

    function Set-View([string]$Name) {
        $views  = @{ dashboard = 'ViewDashboard'; updates = 'ViewUpdates'; all = 'ViewAll' }
        $navs   = @{ dashboard = 'NavDashboard';  updates = 'NavUpdates';  all = 'NavAll' }
        $titles = @{ dashboard = 'Tableau de bord'; updates = 'Mises à jour'; all = 'Tous les pilotes' }
        foreach ($k in @($views.Keys)) {
            $on = ($k -eq $Name)
            $ui[$views[$k]].Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
            $ui[$navs[$k]].Background  = if ($on) { Get-Brush '#1D3A55' } else { [System.Windows.Media.Brushes]::Transparent }
            $ui[$navs[$k]].Foreground  = if ($on) { [System.Windows.Media.Brushes]::White } else { Get-Brush '#B8C7D6' }
        }
        $ui.PageTitle.Text = $titles[$Name]
    }

    function Get-StatusLine {
        if (-not $script:LastSearch) { return 'Pas encore analysé' }
        return ('Dernière analyse : aujourd''hui à {0:HH:mm}' -f $script:LastSearch)
    }

    function Get-CheckedUpdates {
        return @($script:UpdateChecks | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
    }

    function Update-InstallButton {
        $n = @(Get-CheckedUpdates).Count
        $ui.BtnInstall.Content   = if ($n -gt 0) { "Installer $n mise(s) à jour" } else { 'Installer' }
        $ui.BtnInstall.IsEnabled = ($n -gt 0) -and (-not $script:CurrentJob)
    }

    function Set-Busy([bool]$Busy, [string]$Text) {
        $ui.StatusText.Text      = $Text
        $ui.Busy.Visibility      = if ($Busy) { 'Visible' } else { 'Collapsed' }
        $ui.BtnSearch.IsEnabled  = -not $Busy
        $ui.DropZone.IsEnabled   = -not $Busy
        $ui.NavPackage.IsEnabled = -not $Busy
        Update-InstallButton
        $window.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::AppStarting } else { $null }
    }

    function Update-Activity {
        # Les 4 derniers événements importants du journal du jour
        $file  = Join-Path $script:LogDir ('{0:yyyy-MM-dd}.log' -f (Get-Date))
        $lines = @()
        if (Test-Path $file) {
            $pattern = '\] (Recherche terminée|Installation validée|Point de restauration créé|NVIDIA : installateur terminé|Windows Update : .* -> Code|pnputil : code \d+|Paquet manuel : (\d+ fichier|installation validée))'
            $lines = @(Get-Content -Path $file -Encoding UTF8 | Where-Object { $_ -match $pattern } | Select-Object -Last 4)
        }
        if ($lines.Count -eq 0) { $ui.ActivityText.Text = "Aucune activité aujourd'hui."; return }
        [array]::Reverse($lines)
        $ui.ActivityText.Text = (@($lines | ForEach-Object {
            $msg = $_ -replace '^\S+ (\d\d:\d\d):\d\d \[\w+\] ', '$1 · '
            if ($msg.Length -gt 78) { $msg = $msg.Substring(0, 75) + '…' }
            $msg
        })) -join "`n"
    }

    function Update-PcInfo {
        $ui.PcName.Text = $env:COMPUTERNAME
        try {
            $os    = (Get-CimInstance Win32_OperatingSystem).Caption -replace '^Microsoft\s+', ''
            $ram   = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
            $script:Board = Get-MotherboardInfo
            $maker = $script:Board.Manufacturer -replace '\s+Technology Co\., Ltd\.?', ''
            $ui.PcInfo.Text = "$os`n$maker $($script:Board.Product)`n$ram Go de RAM"
        } catch { }
    }

    function Update-Dashboard {
        $updates = @($script:Updates | Where-Object { $_ })
        $inv     = @($script:Inventory | Where-Object { $_ })

        # Compteurs + pastille du menu
        $ui.KpiDevices.Text       = if ($inv.Count) { [string]$inv.Count } else { '-' }
        $ui.KpiUpdates.Text       = [string]$updates.Count
        $ui.KpiUpdates.Foreground = if ($updates.Count) { Get-Brush '#D97706' } else { Get-Brush '#166534' }
        $ui.UpdatesBadge.Visibility = if ($updates.Count) { 'Visible' } else { 'Collapsed' }
        $ui.UpdatesBadgeText.Text = [string]$updates.Count

        # Cartes : d'abord les mises à jour, puis les composants à jour
        $ui.CardsPanel.Children.Clear()
        $components = @(Get-ComponentList -Inventory $inv)
        $used  = @{}
        $cards = New-Object System.Collections.Generic.List[object]
        foreach ($u in $updates) {
            $comp = $components | Where-Object { $_.Device -eq $u.Device } | Select-Object -First 1
            if ($comp) { $used[$comp.Device] = $true; $kind = $comp.Kind; $title = $comp.Title; $label = $comp.Label }
            else {
                $k = Get-KindFromClass $u.DriverClass
                if ($u.Source -eq 'NVIDIA') { $k = @{ Kind = 'gpu'; Title = 'Carte graphique' } }
                $kind = $k.Kind; $title = $k.Title; $label = $u.Device
            }
            $size = Format-Size $u.SizeMB
            $pill = if ($size) { "Mise à jour · $size" } else { 'Mise à jour' }
            $cards.Add(@{ Kind = $kind; Title = $title; Label = $label; Warn = $true; Pill = $pill; Current = $u.CurrentVersion; New = $u.NewVersion })
        }
        foreach ($c in $components) {
            if ($used[$c.Device]) { continue }
            $cards.Add(@{ Kind = $c.Kind; Title = $c.Title; Label = $c.Label; Warn = $false; Pill = 'À jour'; Current = $c.Version; New = $null })
        }

        foreach ($c in $cards) {
            $card = New-Object System.Windows.Controls.Border
            $styleName = if ($c.Warn) { 'CardWarn' } else { 'Card' }
            $card.Style  = $window.FindResource($styleName)
            $card.Margin = New-Thickness 0 0 12 12
            $stack = New-Object System.Windows.Controls.StackPanel

            $head = New-Object System.Windows.Controls.DockPanel
            $icon = New-IconBadge $c.Kind
            [System.Windows.Controls.DockPanel]::SetDock($icon, 'Left')
            [void]$head.Children.Add($icon)
            $titles = New-Object System.Windows.Controls.StackPanel
            $titles.Margin = New-Thickness 12 0 0 0
            $titles.VerticalAlignment = 'Center'
            [void]$titles.Children.Add((New-Text $c.Title 14 -SemiBold))
            [void]$titles.Children.Add((New-Text $c.Label 12 '#5D6B78'))
            [void]$head.Children.Add($titles)
            [void]$stack.Children.Add($head)

            $pillEl = New-Pill $c.Pill $c.Warn
            $pillEl.Margin = New-Thickness 0 12 0 0
            [void]$stack.Children.Add($pillEl)

            $ver = New-VersionText $c.Current $c.New
            $ver.Margin = New-Thickness 0 9 0 0
            [void]$stack.Children.Add($ver)

            $card.Child = $stack
            [void]$ui.CardsPanel.Children.Add($card)
        }
    }

    function Update-UpdatesView {
        $ui.UpdatesPanel.Children.Clear()
        $script:UpdateChecks.Clear()
        $updates = @($script:Updates | Where-Object { $_ })
        $ui.UpdatesEmpty.Visibility = if ($updates.Count) { 'Collapsed' } else { 'Visible' }

        foreach ($u in $updates) {
            $row = New-Object System.Windows.Controls.Border
            $row.Style   = $window.FindResource('Card')
            $row.Margin  = New-Thickness 0 0 0 8
            $row.Padding = New-Thickness 16 12 18 12
            $grid = New-Object System.Windows.Controls.Grid
            foreach ($w in @('Auto', 'Auto', '*', 'Auto', 'Auto', '90')) {
                $cd = New-Object System.Windows.Controls.ColumnDefinition
                if ($w -eq 'Auto')   { $cd.Width = [System.Windows.GridLength]::Auto }
                elseif ($w -eq '*')  { $cd.Width = New-Object System.Windows.GridLength(1, ([System.Windows.GridUnitType]::Star)) }
                else                 { $cd.Width = New-Object System.Windows.GridLength([double]$w) }
                $grid.ColumnDefinitions.Add($cd)
            }

            $chk = New-Object System.Windows.Controls.CheckBox
            $chk.Style     = $window.FindResource('Check')
            $chk.IsChecked = $true
            $chk.Tag       = $u
            $chk.VerticalAlignment = 'Center'
            $chk.Margin = New-Thickness 0 0 14 0
            $chk.Add_Click({ Update-InstallButton })
            $script:UpdateChecks.Add($chk)
            [System.Windows.Controls.Grid]::SetColumn($chk, 0); [void]$grid.Children.Add($chk)

            $comp = Get-KindFromClass $u.DriverClass
            if ($u.Source -eq 'NVIDIA') { $comp = @{ Kind = 'gpu'; Title = 'Carte graphique' } }
            $icon = New-IconBadge $comp.Kind 34
            $icon.Margin = New-Thickness 0 0 14 0
            [System.Windows.Controls.Grid]::SetColumn($icon, 1); [void]$grid.Children.Add($icon)

            $names = New-Object System.Windows.Controls.StackPanel
            $names.VerticalAlignment = 'Center'
            [void]$names.Children.Add((New-Text $u.Device 14 -SemiBold))
            $sub = if ($u.Title) { $u.Title } else { $comp.Title }
            [void]$names.Children.Add((New-Text $sub 12 '#5D6B78'))
            [System.Windows.Controls.Grid]::SetColumn($names, 2); [void]$grid.Children.Add($names)

            $tag = New-Object System.Windows.Controls.Border
            $tag.CornerRadius = New-Object System.Windows.CornerRadius(10)
            $tag.Padding    = New-Thickness 9 2 9 2
            $tag.Margin     = New-Thickness 12 0 18 0
            $tag.Background = Get-Brush '#F1F5F9'
            $tag.VerticalAlignment = 'Center'
            $tag.Child = New-Text $u.Source 11.5 '#334155'
            [System.Windows.Controls.Grid]::SetColumn($tag, 3); [void]$grid.Children.Add($tag)

            $ver = New-VersionText $u.CurrentVersion $u.NewVersion
            $ver.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($ver, 4); [void]$grid.Children.Add($ver)

            $size = New-Text (Format-Size $u.SizeMB) 12.5 '#5D6B78'
            $size.HorizontalAlignment = 'Right'; $size.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($size, 5); [void]$grid.Children.Add($size)

            $row.Child = $grid
            [void]$ui.UpdatesPanel.Children.Add($row)
        }
        Update-InstallButton
    }

    function Update-AllView {
        $updates = @($script:Updates | Where-Object { $_ })
        $rows = foreach ($d in @(Get-VendorDriverList -Inventory $script:Inventory)) {
            $u = $updates | Where-Object { $_.Device -eq $d.Name } | Select-Object -First 1
            [pscustomobject]@{
                Name          = $d.Name
                Manufacturer  = $d.Manufacturer
                DriverVersion = $d.DriverVersion
                Status        = if ($u) { "Mise à jour : $($u.NewVersion)" } else { '✓ À jour' }
            }
        }
        $ui.AllGrid.ItemsSource = @($rows)
    }

    function Update-All {
        Update-Dashboard
        Update-UpdatesView
        Update-AllView
        Update-Activity
    }

    function Start-Search {
        if ($script:CurrentJob) { return }
        Set-Busy $true 'Analyse en cours : NVIDIA et Windows Update (1 à 2 minutes)...'
        $script:JobKind    = 'search'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot -ScriptBlock {
            param($root)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            $inv = @(Get-DeviceInventory)
            $upd = @(Find-DriverUpdate -Inventory $inv)
            # JSON : les listes imbriquées survivent au passage entre processus
            [pscustomobject]@{ Updates = $upd; Inventory = $inv } | ConvertTo-Json -Depth 4 -Compress
        }
        $timer.Start()
    }

    function Start-Install {
        if ($script:CurrentJob) { return }
        $selected = @(Get-CheckedUpdates | Where-Object { $_ })
        if ($selected.Count -eq 0) { return }
        $names = ($selected | ForEach-Object { "- $($_.Device) ($($_.CurrentVersion) -> $($_.NewVersion))" }) -join "`r`n"
        if ([string](Show-Message "Installer ces pilotes ?`r`n`r`n$names" 'Confirmation' 'YesNo' 'Question') -ne 'Yes') { return }

        Write-Log ("Installation validée par l'utilisateur : " + (($selected | ForEach-Object { $_.Device }) -join ', '))
        Set-Busy $true 'Installation en cours... Ne pas éteindre l''ordinateur (l''écran peut clignoter).'
        $script:JobKind    = 'install'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot, $selected, ($ui.ChkRestore.IsChecked -eq $true) -ScriptBlock {
            param($root, $items, $restorePoint)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Install-DriverUpdate -Candidate $items -CreateRestorePoint:$restorePoint
        }
        Update-InstallButton
        $timer.Start()
    }

    function Start-PackageAnalysis([string]$Path) {
        if ($script:CurrentJob) { [void](Show-Message 'Une opération est déjà en cours, patiente un peu.'); return }
        Write-Log "Paquet déposé : $Path"
        Set-Busy $true ("Analyse du paquet « {0} »..." -f (Split-Path $Path -Leaf))
        $script:JobKind    = 'analyze'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot, $Path -ScriptBlock {
            param($root, $p)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Get-DriverPackageAnalysis -Path $p | ConvertTo-Json -Depth 5
        }
        $timer.Start()
    }

    function Select-Package {
        if ($script:CurrentJob) { [void](Show-Message 'Une opération est déjà en cours, patiente un peu.'); return }
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Title  = 'Choisir un paquet de pilotes'
        $dlg.Filter = 'Paquets de pilotes (*.zip;*.exe)|*.zip;*.exe|Tous les fichiers (*.*)|*.*'
        if ($dlg.ShowDialog($window) -eq $true) { Start-PackageAnalysis $dlg.FileName }
    }

    function Show-PackageDiagnostic([object]$Analysis) {
        # Explique POURQUOI rien n'a été trouvé, pour distinguer "mauvais paquet" et "problème"
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('Aucun pilote de ce paquet ne correspond au matériel de ce PC.')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine(("Contenu du paquet : {0} fichier(s), dont {1} pilote(s) .inf et {2} programme(s) .exe." -f $Analysis.FileCount, $Analysis.InfCount, $Analysis.ExeCount))
        [void]$sb.AppendLine()

        $infList = @($Analysis.InfSummary | Where-Object { $_ })
        $bios    = @($Analysis.BiosFiles | Where-Object { $_ })
        if ($bios.Count -gt 0 -and $Analysis.InfCount -eq 0) {
            [void]$sb.AppendLine("=> C'est un BIOS ($($bios[0])), pas un pilote.")
            [void]$sb.AppendLine('Un BIOS ne s''installe pas depuis Windows : il se met à jour depuis le BIOS lui-même (Q-Flash chez Gigabyte).')
            [void]$sb.AppendLine('Driver ne le fait volontairement pas : une coupure pendant la mise à jour peut rendre le PC inutilisable.')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('Pour les pilotes, prends l''onglet « Pilotes » (Driver) de la page support, et non « BIOS ».')
        }
        elseif ($Analysis.InfCount -eq 0 -and $Analysis.ExeCount -eq 0) {
            [void]$sb.AppendLine('=> Ce paquet ne contient ni pilote (.inf) ni installateur (.exe). Ce n''est probablement pas un pilote (manuel, utilitaire ?).')
        }
        elseif ($Analysis.InfCount -eq 0) {
            [void]$sb.AppendLine('=> Aucun fichier .inf lisible : le pilote est sans doute compressé dans l''installateur, mais aucun setup.exe principal n''a été trouvé.')
        }
        else {
            [void]$sb.AppendLine('Ce que vise le paquet :')
            foreach ($i in ($infList | Select-Object -First 6)) {
                $ids = (@($i.Ids) | Select-Object -First 4) -join ', '
                if (-not $ids) { $ids = 'aucun identifiant PCI/USB' }
                [void]$sb.AppendLine(("  - {0} (type {1}, version {2}) : {3}" -f $i.InfName, $i.Class, $i.Version, $ids))
            }
            if ($infList.Count -gt 6) { [void]$sb.AppendLine(("  ... et {0} autre(s) .inf" -f ($infList.Count - 6))) }
            [void]$sb.AppendLine()
            $pc = @($Analysis.PcDevices | Where-Object { $_ })
            if ($pc.Count -gt 0) {
                [void]$sb.AppendLine('Ton matériel de ce type :')
                foreach ($d in ($pc | Select-Object -First 6)) { [void]$sb.AppendLine("  - $d") }
                [void]$sb.AppendLine()
                [void]$sb.AppendLine('=> Les identifiants ne correspondent pas : c''est probablement le pilote d''une autre puce ou d''une autre carte. Vérifie le modèle sur le site.')
            } else {
                [void]$sb.AppendLine('=> Ton PC n''a aucun périphérique de ce type : ce paquet n''est pas pour ce PC.')
            }
        }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('Détails complets dans les journaux.')
        [void](Show-Message $sb.ToString() 'Driver - paquet non compatible' 'OK' 'Warning')
    }

    function Confirm-PackageInstall([object]$Analysis, [string]$Json) {
        $drivers = @($Analysis.Drivers | Where-Object { $_ })
        $newer   = @($drivers | Where-Object { $_.IsNewer })
        $older   = @($drivers | Where-Object { -not $_.IsNewer })
        $text    = ''
        if ($older.Count -gt 0) {
            $text += "Déjà à jour (ignorés) :`r`n" + (($older | ForEach-Object { "- $($_.Device) : $($_.CurrentVersion) (paquet : $($_.PackageVersion))" }) -join "`r`n") + "`r`n`r`n"
        }

        if ($newer.Count -gt 0) {
            $text = "Pilotes plus récents trouvés pour ton matériel :`r`n" +
                (($newer | ForEach-Object { "- $($_.Device) : $($_.CurrentVersion) -> $($_.PackageVersion)" }) -join "`r`n") +
                "`r`n`r`n" + $text + 'Installer maintenant ?'
        }
        elseif ($older.Count -gt 0) {
            Set-Busy $false (Get-StatusLine)
            [void](Show-Message ($text + 'Tu es déjà à jour : ce paquet ne contient pas de version plus récente que la tienne.') 'Driver - déjà à jour')
            return
        }
        elseif ($Analysis.InfCount -eq 0 -and $Analysis.Setup -and $Analysis.SetupSigned) {
            # Pas de .inf lisible : le pilote est enfermé dans l'installateur du constructeur
            $text = "Ce paquet ne contient pas de pilote installable directement : il passe par son propre installateur.`r`n`r`n" +
                "Lancer « $(Split-Path $Analysis.Setup -Leaf) » (signé par $($Analysis.SetupSigner)) ?`r`n" +
                'Tu devras suivre ses étapes.'
        }
        elseif ($Analysis.InfCount -eq 0 -and $Analysis.Setup) {
            Set-Busy $false (Get-StatusLine)
            [void](Show-Message "L'installateur « $(Split-Path $Analysis.Setup -Leaf) » n'a pas de signature numérique valide : il est refusé par sécurité." 'Driver' 'OK' 'Warning')
            return
        }
        else {
            Set-Busy $false (Get-StatusLine)
            Show-PackageDiagnostic -Analysis $Analysis
            return
        }

        if ([string](Show-Message $text 'Installer le paquet' 'YesNo' 'Question') -ne 'Yes') {
            Set-Busy $false (Get-StatusLine)
            return
        }

        Write-Log "Paquet manuel : installation validée par l'utilisateur ($($Analysis.Source))"
        Set-Busy $true 'Installation du paquet en cours... (l''écran ou le son peuvent couper quelques secondes)'
        $script:JobKind    = 'install'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot, $Json, ($ui.ChkRestore.IsChecked -eq $true) -ScriptBlock {
            param($root, $json, $restorePoint)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Install-DriverPackage -Analysis ($json | ConvertFrom-Json) -CreateRestorePoint:$restorePoint
        }
        $timer.Start()
    }

    # ---------- Surveillance du job en arrière-plan ----------
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if (-not $script:CurrentJob) { return }
        if ([string]$script:CurrentJob.State -notin @('Completed', 'Failed', 'Stopped')) { return }

        $timer.Stop()
        $jobErrors = $null
        $output = @(Receive-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue -ErrorVariable jobErrors)
        $failed = ([string]$script:CurrentJob.State -ne 'Completed')
        Remove-Job -Job $script:CurrentJob -Force
        $script:CurrentJob = $null
        $errText = (@($jobErrors) | Where-Object { $_ } | ForEach-Object { $_.ToString() }) -join "`r`n"
        if ($errText) { Write-Log "Erreur dans la tâche de fond ($($script:JobKind)) : $errText" 'ERREUR' }

        if ($script:JobKind -eq 'search') {
            $json = ($output | Where-Object { $_ -is [string] }) -join "`n"
            if ($json) {
                $data = $json | ConvertFrom-Json
                $script:Updates    = @($data.Updates | Where-Object { $_ })
                $script:Inventory  = @($data.Inventory | Where-Object { $_ })
                $script:LastSearch = Get-Date
                Update-All
                Set-Busy $false (Get-StatusLine)
            } else {
                Set-Busy $false 'L''analyse a échoué : consulte les journaux.'
            }
        }
        elseif ($script:JobKind -eq 'analyze') {
            $json = ($output | Where-Object { $_ -is [string] }) -join "`n"
            if ($failed -or -not $json) {
                Set-Busy $false (Get-StatusLine)
                [void](Show-Message "Impossible d'analyser ce paquet.`r`n`r`n$errText" 'Driver' 'OK' 'Error')
            } else {
                Confirm-PackageInstall -Analysis ($json | ConvertFrom-Json) -Json $json
            }
        }
        elseif ($script:JobKind -eq 'install') {
            $results = @($output | Where-Object { $_ -and $_.PSObject.Properties['Success'] })
            $ok      = @($results | Where-Object { $_.Success }).Count
            $reboot  = @($results | Where-Object { $_.RebootRequired }).Count -gt 0

            $msg = "$ok opération(s) réussie(s) sur $($results.Count)."
            if ($results.Count -gt 0) {
                $msg += "`r`n`r`n" + (($results | ForEach-Object { "- $($_.Device) : $($_.Message)" }) -join "`r`n")
            }
            if ($errText) { $msg += "`r`n`r`nErreur : $errText" }
            Set-Busy $false 'Installation terminée.'
            Update-Activity

            if ($reboot) {
                if ([string](Show-Message "$msg`r`n`r`nUn redémarrage est nécessaire. Redémarrer maintenant ?" 'Driver' 'YesNo' 'Question') -eq 'Yes') {
                    Restart-Computer -Force
                }
            } else {
                [void](Show-Message $msg)
            }
            Start-Search
        }
    })

    # ---------- Événements ----------
    $ui.NavDashboard.Add_Click({ Set-View 'dashboard' })
    $ui.NavUpdates.Add_Click({ Set-View 'updates' })
    $ui.NavAll.Add_Click({ Set-View 'all' })
    $ui.NavPackage.Add_Click({ Select-Package })
    $ui.NavBoard.Add_Click({
        $url = Get-MotherboardSupportUrl -Board $script:Board
        Write-Log "Ouverture de la page support carte mère : $url"
        Start-Process $url
    })
    $ui.NavLogs.Add_Click({ Start-Process explorer.exe -ArgumentList $script:LogDir })
    $ui.BtnSearch.Add_Click({ Start-Search })
    $ui.BtnInstall.Add_Click({ Start-Install })
    $ui.DropZone.Add_MouseLeftButtonUp({ Select-Package })

    $window.Add_SourceInitialized({
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        # Barre de titre bleu nuit (#12263A) et texte blanc - format 0x00BBGGRR
        [DriverWindowTheme]::SetCaption($hwnd, 0x003A2612, 0x00FFFFFF)
        # Glisser-déposer de fichiers malgré les droits administrateur
        try {
            $script:DropHook = New-Object DriverDropHook($hwnd)
            $script:DropHook.add_FilesDropped({
                param($s, $e)
                if ($e.Files.Count -gt 0) { Start-PackageAnalysis $e.Files[0] }
            })
        } catch {
            Write-Log "Glisser-déposer indisponible : $($_.Exception.Message)" 'WARN'
        }
    })

    $window.Add_Closing({
        param($s, $e)
        if ($script:CurrentJob -and $script:JobKind -eq 'install') {
            [void](Show-Message 'Une installation est en cours, merci de patienter.' 'Driver' 'OK' 'Warning')
            $e.Cancel = $true
        }
        elseif ($script:CurrentJob) {
            Stop-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $script:CurrentJob -Force -ErrorAction SilentlyContinue
            $script:CurrentJob = $null
        }
    })

    $script:FirstRender = $true
    $window.Add_ContentRendered({
        if (-not $script:FirstRender) { return }
        $script:FirstRender = $false
        Set-View 'dashboard'
        Update-PcInfo
        if ($InitialResults) {
            # Lancement au démarrage : la recherche est déjà faite
            $script:Updates    = @($InitialResults | Where-Object { $_ })
            $script:Inventory  = @(Get-DeviceInventory)
            $script:LastSearch = Get-Date
            Update-All
            Set-Busy $false (Get-StatusLine)
        }
        elseif ($AutoSearch) {
            $script:Inventory = @(Get-DeviceInventory)
            Update-All
            Start-Search
        }
        else {
            Update-All
            Set-Busy $false (Get-StatusLine)
        }
    })

    [void]$window.ShowDialog()
    $timer.Stop()
}
