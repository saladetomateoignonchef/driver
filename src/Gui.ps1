# =============================================================================
#  Gui.ps1 - Interface graphique "tableau de bord" (WPF)
#
#  La mise en page est décrite dans MainWindow.xaml ; ce fichier la charge,
#  la remplit avec les données et réagit aux clics.
#  Les opérations longues (analyse, installation, retour arrière, mise à jour de
#  Driver) tournent dans un job PowerShell en arrière-plan ; un DispatcherTimer
#  vérifie toutes les 500 ms où il en est (fichier progress.json) et s'il est
#  terminé, pour que la fenêtre ne se fige jamais.
# =============================================================================

. (Join-Path $PSScriptRoot 'DropTarget.ps1')   # charge aussi WPF

# ---------- Thèmes (couleurs remplacées dans les ressources de la fenêtre) ----------
$script:Themes = @{
    Light = @{
        BgBrush = '#F4F6F8'; SurfaceBrush = '#FFFFFF'; SurfaceAltBrush = '#F8FAFC'; LineBrush = '#E3E8ED'
        TextBrush = '#17202A'; MutedBrush = '#5D6B78'; BtnLineBrush = '#D3DAE1'; ChipBrush = '#F1F5F9'
        ChipTextBrush = '#334155'; ToggleOffBrush = '#CBD5E1'; DropLineBrush = '#9FB3C5'; SelectedBrush = '#E6F4F1'
        BannerBrush = '#CCFBF1'; BannerTextBrush = '#134E4A'
    }
    Dark = @{
        BgBrush = '#0E1621'; SurfaceBrush = '#16212D'; SurfaceAltBrush = '#1B2836'; LineBrush = '#263546'
        TextBrush = '#E6EDF3'; MutedBrush = '#93A4B5'; BtnLineBrush = '#34465A'; ChipBrush = '#223244'
        ChipTextBrush = '#CBD5E1'; ToggleOffBrush = '#3A4A5C'; DropLineBrush = '#45607A'; SelectedBrush = '#173A37'
        BannerBrush = '#134E4A'; BannerTextBrush = '#CCFBF1'
    }
}

# ---------- Petites fonctions d'aide pour créer des éléments WPF ----------
$script:BrushConverter = New-Object System.Windows.Media.BrushConverter
function Get-Brush([string]$Hex) { return $script:BrushConverter.ConvertFromString($Hex) }
function New-Thickness([double]$L, [double]$T, [double]$R, [double]$B) { return New-Object System.Windows.Thickness($L, $T, $R, $B) }

function New-Text {
    <# $Color : '#RRGGBB' (couleur fixe) ou nom de couleur du thème : Text, Muted, ChipText... #>
    param([string]$Text, [double]$Size = 13, [string]$Color = 'Text', [switch]$Bold, [switch]$SemiBold)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text         = $Text
    $tb.FontSize     = $Size
    $tb.TextTrimming = 'CharacterEllipsis'
    if ($Color.StartsWith('#')) { $tb.Foreground = Get-Brush $Color }
    else { $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "$($Color)Brush") }
    if ($Bold)     { $tb.FontWeight = [System.Windows.FontWeights]::Bold }
    if ($SemiBold) { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $tb
}

function New-Button {
    param([string]$Text, [string]$Style = 'BtnSmall', [object]$Tag, [object]$Window)
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Text
    $b.Style   = $Window.FindResource($Style)
    $b.Tag     = $Tag
    $b.VerticalAlignment = 'Center'
    return $b
}

# Icônes (tracés vectoriels) et couleurs par type de composant
$script:Icons = @{
    gpu     = @{ Data = 'M1.5,4 L16.5,4 L16.5,14 L1.5,14 Z M13.4,9 A2.4,2.4 0 1 1 8.6,9 A2.4,2.4 0 1 1 13.4,9'; Bg = '#ECFCCB'; Fg = '#4D7C0F' }
    audio   = @{ Data = 'M3,7 L3,11 M6,5 L6,13 M9,3 L9,15 M12,5 L12,13 M15,7 L15,11'; Bg = '#E0F2FE'; Fg = '#0369A1' }
    effect  = @{ Data = 'M3,7 L3,11 M6,5 L6,13 M9,3 L9,15 M12,5 L12,13 M15,7 L15,11'; Bg = '#F3E8FF'; Fg = '#7E22CE' }
    net     = @{ Data = 'M2,12 L16,12 M4,12 L4,6 L14,6 L14,12 M7,9 L11,9'; Bg = '#E2E8F0'; Fg = '#475569' }
    chipset = @{ Data = 'M2,2 L16,2 L16,16 L2,16 Z M6,6 L12,6 L12,12 L6,12 Z'; Bg = '#DBEAFE'; Fg = '#1D4ED8' }
    bt      = @{ Data = 'M6,5 L12,11 L9,14 L9,2 L12,5 L6,11'; Bg = '#E0E7FF'; Fg = '#4338CA' }
    storage = @{ Data = 'M2,5 L16,5 L16,13 L2,13 Z M5,9 L9,9'; Bg = '#FCE7F3'; Fg = '#BE185D' }
    other   = @{ Data = 'M3,3 L15,3 L15,15 L3,15 Z M6,7 L12,7 M6,10 L12,10'; Bg = '#E2E8F0'; Fg = '#475569' }
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
    $tb.TextTrimming = 'CharacterEllipsis'
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'MutedBrush')
    [void]$tb.Inlines.Add((New-Object System.Windows.Documents.Run([string]$Current)))
    if ($New) {
        [void]$tb.Inlines.Add((New-Object System.Windows.Documents.Run('  →  ')))
        $run = New-Object System.Windows.Documents.Run([string]$New)
        $run.Foreground = Get-Brush '#14B8A6'
        $run.FontWeight = [System.Windows.FontWeights]::Bold
        [void]$tb.Inlines.Add($run)
    }
    return $tb
}

function New-Columns {
    <# Grille avec des colonnes : 'Auto', '*' ou une largeur en pixels. #>
    param([string[]]$Widths)
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in $Widths) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq 'Auto')  { $cd.Width = [System.Windows.GridLength]::Auto }
        elseif ($w -eq '*') { $cd.Width = New-Object System.Windows.GridLength(1, ([System.Windows.GridUnitType]::Star)) }
        else                { $cd.Width = New-Object System.Windows.GridLength([double]$w) }
        $grid.ColumnDefinitions.Add($cd)
    }
    return $grid
}

function Add-ToGrid([object]$Grid, [object]$Element, [int]$Column) {
    [System.Windows.Controls.Grid]::SetColumn($Element, $Column)
    [void]$Grid.Children.Add($Element)
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
        [switch]$AutoSearch          # lance une analyse dès l'ouverture
    )

    # ---------- Chargement de la fenêtre ----------
    [xml]$xaml = Get-Content -Path (Join-Path $PSScriptRoot 'MainWindow.xaml') -Raw -Encoding UTF8
    $window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $ui = @{}
    # éléments nommés de la fenêtre (pas ceux des modèles de boutons, qui ont leur propre espace de noms)
    foreach ($node in $xaml.SelectNodes('//*[@*[local-name()="Name"]][not(ancestor::*[local-name()="ControlTemplate"])]')) {
        $name = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $ui[$name] = $window.FindName($name) }
    }
    $iconFile = Join-Path $PSScriptRoot 'driver.ico'
    if (Test-Path $iconFile) {
        try { $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconFile))) } catch { }
    }

    $script:Settings     = Get-AppSettings
    $script:CurrentJob   = $null
    $script:JobKind      = $null
    $script:Updates      = @()
    $script:Inventory    = $null
    $script:UpdateChecks = New-Object System.Collections.Generic.List[object]
    $script:LastSearch   = $null
    $script:Board        = $null
    $script:AppRelease   = $null
    $script:LoadingSettings = $false

    # ---------- Fonctions internes ----------
    function Show-Message([string]$Text, [string]$Title = 'Driver', [string]$Buttons = 'OK', [string]$Icon = 'Information') {
        return [string]([System.Windows.MessageBox]::Show($window, $Text, $Title, $Buttons, $Icon))
    }

    function Set-Theme([string]$Name) {
        $palette = $script:Themes[$Name]
        if (-not $palette) { $palette = $script:Themes['Light'] }
        foreach ($key in @($palette.Keys)) { $window.Resources[$key] = Get-Brush $palette[$key] }
    }

    function Set-View([string]$Name) {
        $views  = @{ dashboard = 'ViewDashboard'; updates = 'ViewUpdates'; all = 'ViewAll'; backups = 'ViewBackups'; history = 'ViewHistory'; settings = 'ViewSettings' }
        $navs   = @{ dashboard = 'NavDashboard';  updates = 'NavUpdates';  all = 'NavAll';  backups = 'NavBackups';  history = 'NavHistory';  settings = 'NavSettings' }
        $titles = @{ dashboard = 'Tableau de bord'; updates = 'Mises à jour'; all = 'Tous les pilotes'; backups = 'Sauvegardes'; history = 'Historique'; settings = 'Paramètres' }
        foreach ($k in @($views.Keys)) {
            $on = ($k -eq $Name)
            $ui[$views[$k]].Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
            $ui[$navs[$k]].Background  = if ($on) { Get-Brush '#1D3A55' } else { [System.Windows.Media.Brushes]::Transparent }
            $ui[$navs[$k]].Foreground  = if ($on) { [System.Windows.Media.Brushes]::White } else { Get-Brush '#B8C7D6' }
        }
        $ui.PageTitle.Text = $titles[$Name]
        switch ($Name) {
            'backups'  { Update-BackupsView }
            'history'  { Update-HistoryView }
            'settings' { Update-SettingsView }
        }
    }

    function Get-StatusLine {
        if (-not $script:LastSearch) { return 'Pas encore analysé' }
        return ('Dernière analyse : aujourd''hui à {0:HH:mm}' -f $script:LastSearch)
    }

    function Get-VisibleUpdates {
        return @($script:Updates | Where-Object { $_ -and -not (Test-UpdateIgnored -Candidate $_ -Settings $script:Settings) })
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
        $ui.StatusText.Text       = $Text
        $ui.Busy.Visibility       = if ($Busy) { 'Visible' } else { 'Collapsed' }
        $ui.Busy.IsIndeterminate  = $true
        $ui.BtnSearch.IsEnabled   = -not $Busy
        $ui.DropZone.IsEnabled    = -not $Busy
        $ui.NavPackage.IsEnabled  = -not $Busy
        $ui.BtnAppUpdate.IsEnabled = -not $Busy
        Update-InstallButton
        $window.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::AppStarting } else { $null }
        if (-not $Busy) { Clear-TaskProgress }
    }

    function Start-BackgroundJob([string]$Kind, [object[]]$Arguments, [scriptblock]$Script) {
        Clear-TaskProgress
        $script:JobKind    = $Kind
        $script:CurrentJob = Start-Job -ArgumentList $Arguments -ScriptBlock $Script
        Update-InstallButton
        $timer.Start()
    }

    function Update-Activity {
        # Les 4 derniers événements importants du journal du jour
        $file  = Join-Path $script:LogDir ('{0:yyyy-MM-dd}.log' -f (Get-Date))
        $lines = @()
        if (Test-Path $file) {
            $pattern = '\] (Recherche terminée|Installation validée|Point de restauration créé|NVIDIA : installateur terminé|Windows Update : .* -> Code|pnputil : code \d+|Paquet manuel : (\d+ fichier|installation validée)|Retour arrière : (Version|Échec|Aucun)|Sauvegarde : .* sauvegardé \(|Mise à jour de Driver|Nettoyage)'
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

    # ---------- Vue : tableau de bord ----------
    function Update-Dashboard {
        $updates = Get-VisibleUpdates
        $inv     = @($script:Inventory | Where-Object { $_ })

        $ui.KpiDevices.Text       = if ($inv.Count) { [string]$inv.Count } else { '-' }
        $ui.KpiUpdates.Text       = [string]$updates.Count
        $ui.KpiUpdates.Foreground = if ($updates.Count) { Get-Brush '#D97706' } else { Get-Brush '#16A34A' }
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
            [void]$titles.Children.Add((New-Text $c.Label 12 'Muted'))
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

    # ---------- Vue : mises à jour ----------
    function Update-UpdatesView {
        $ui.UpdatesPanel.Children.Clear()
        $script:UpdateChecks.Clear()
        $updates = Get-VisibleUpdates
        $ui.UpdatesEmpty.Visibility = if ($updates.Count) { 'Collapsed' } else { 'Visible' }

        foreach ($u in $updates) {
            $row = New-Object System.Windows.Controls.Border
            $row.Style   = $window.FindResource('Card')
            $row.Margin  = New-Thickness 0 0 0 8
            $row.Padding = New-Thickness 16 12 14 12
            $grid = New-Columns @('Auto', 'Auto', '*', 'Auto', 'Auto', '80', 'Auto')

            $chk = New-Object System.Windows.Controls.CheckBox
            $chk.Style     = $window.FindResource('Check')
            $chk.IsChecked = $true
            $chk.Tag       = $u
            $chk.VerticalAlignment = 'Center'
            $chk.Margin = New-Thickness 0 0 14 0
            $chk.Add_Click({ Update-InstallButton })
            $script:UpdateChecks.Add($chk)
            Add-ToGrid $grid $chk 0

            $comp = Get-KindFromClass $u.DriverClass
            if ($u.Source -eq 'NVIDIA') { $comp = @{ Kind = 'gpu'; Title = 'Carte graphique' } }
            $icon = New-IconBadge $comp.Kind 34
            $icon.Margin = New-Thickness 0 0 14 0
            Add-ToGrid $grid $icon 1

            $names = New-Object System.Windows.Controls.StackPanel
            $names.VerticalAlignment = 'Center'
            [void]$names.Children.Add((New-Text $u.Device 14 -SemiBold))
            $sub = if ($u.Title) { $u.Title } else { $comp.Title }
            [void]$names.Children.Add((New-Text $sub 12 'Muted'))
            Add-ToGrid $grid $names 2

            $tag = New-Object System.Windows.Controls.Border
            $tag.CornerRadius = New-Object System.Windows.CornerRadius(10)
            $tag.Padding = New-Thickness 9 2 9 2
            $tag.Margin  = New-Thickness 12 0 18 0
            $tag.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'ChipBrush')
            $tag.VerticalAlignment = 'Center'
            $tag.Child = New-Text $u.Source 11.5 'ChipText'
            Add-ToGrid $grid $tag 3

            $ver = New-VersionText $u.CurrentVersion $u.NewVersion
            $ver.VerticalAlignment = 'Center'
            Add-ToGrid $grid $ver 4

            $size = New-Text (Format-Size $u.SizeMB) 12.5 'Muted'
            $size.HorizontalAlignment = 'Right'; $size.VerticalAlignment = 'Center'
            Add-ToGrid $grid $size 5

            $ignore = New-Button -Text 'Ignorer' -Style 'BtnLink' -Tag $u -Window $window
            $ignore.Margin = New-Thickness 10 0 0 0
            $ignore.ToolTip = 'Ne plus proposer cette version (réversible dans Paramètres)'
            $ignore.Add_Click({
                param($s, $e)
                Add-IgnoredUpdate -Candidate $s.Tag -Settings $script:Settings
                Update-All
            })
            Add-ToGrid $grid $ignore 6

            $row.Child = $grid
            [void]$ui.UpdatesPanel.Children.Add($row)
        }
        Update-InstallButton
    }

    # ---------- Vue : tous les pilotes ----------
    function Update-AllView {
        $updates = Get-VisibleUpdates
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

    # ---------- Vue : sauvegardes ----------
    function Update-BackupsView {
        $ui.BackupsPanel.Children.Clear()
        $backups = @(Get-DriverBackup | Sort-Object Date -Descending)
        $ui.BackupsEmpty.Visibility = if ($backups.Count) { 'Collapsed' } else { 'Visible' }
        $ui.BtnBackupsClear.IsEnabled = ($backups.Count -gt 0)
        $ui.BackupsInfo.Text = '{0} sauvegarde(s) · {1} au total · limite : {2} version(s) par pilote (modifiable dans Paramètres)' -f `
            $backups.Count, (Format-Size (Get-BackupTotalSizeMB)), $script:Settings.BackupKeep
        if (-not $backups.Count) { $ui.BackupsInfo.Text = "Limite : $($script:Settings.BackupKeep) version(s) par pilote (modifiable dans Paramètres)" }

        foreach ($b in $backups) {
            $row = New-Object System.Windows.Controls.Border
            $row.Style   = $window.FindResource('Card')
            $row.Margin  = New-Thickness 0 0 0 8
            $row.Padding = New-Thickness 16 12 14 12
            $grid = New-Columns @('Auto', '*', 'Auto', 'Auto', 'Auto')

            $icon = New-IconBadge 'other' 34
            $icon.Margin = New-Thickness 0 0 14 0
            Add-ToGrid $grid $icon 0

            $info = New-Object System.Windows.Controls.StackPanel
            $info.VerticalAlignment = 'Center'
            [void]$info.Children.Add((New-Text $b.Device 14 -SemiBold))
            [void]$info.Children.Add((New-Text ('Version {0} · sauvegardée le {1:dd/MM/yyyy} à {1:HH:mm}' -f $b.Version, $b.Date) 12 'Muted'))
            Add-ToGrid $grid $info 1

            $size = New-Text (Format-Size $b.SizeMB) 12.5 'Muted'
            $size.VerticalAlignment = 'Center'; $size.Margin = New-Thickness 12 0 16 0
            Add-ToGrid $grid $size 2

            $restore = New-Button -Text 'Revenir à cette version' -Style 'BtnPrimary' -Tag $b -Window $window
            $restore.Padding = New-Thickness 12 6 12 6; $restore.FontSize = 12
            $restore.Add_Click({ param($s, $e); Start-Restore $s.Tag })
            Add-ToGrid $grid $restore 3

            $del = New-Button -Text 'Supprimer' -Style 'BtnSmall' -Tag $b -Window $window
            $del.Margin = New-Thickness 8 0 0 0
            $del.Add_Click({
                param($s, $e)
                $b = $s.Tag
                if ((Show-Message "Supprimer la sauvegarde de $($b.Device) (version $($b.Version)) ?" 'Sauvegardes' 'YesNo' 'Question') -eq 'Yes') {
                    Remove-DriverBackup -Path $b.Path
                    Update-BackupsView
                }
            })
            Add-ToGrid $grid $del 4

            $row.Child = $grid
            [void]$ui.BackupsPanel.Children.Add($row)
        }
    }

    # ---------- Vue : historique ----------
    function Update-HistoryView {
        $history = @(Get-DriverHistory)
        $ok = @($history | Where-Object { $_.Success }).Count
        $ui.HistoryInfo.Text = "$($history.Count) opération(s) enregistrée(s), dont $ok réussie(s)"
        $ui.HistoryEmpty.Visibility = if ($history.Count) { 'Collapsed' } else { 'Visible' }
        $ui.HistoryGrid.ItemsSource = @($history | ForEach-Object {
            [pscustomobject]@{
                Date       = ([datetime]$_.Date).ToString('dd/MM/yyyy HH:mm')
                Type       = $_.Type
                Device     = $_.Device
                OldVersion = $_.OldVersion
                NewVersion = $_.NewVersion
                Result     = if ($_.Success) { '✓ Réussi' } else { '✗ Échec' }
            }
        })
    }

    # ---------- Vue : paramètres ----------
    function Update-SettingsView {
        $script:LoadingSettings = $true
        $s = $script:Settings
        $ui.RbFreqStartup.IsChecked = ($s.CheckFrequency -eq 'Startup')
        $ui.RbFreqDaily.IsChecked   = ($s.CheckFrequency -eq 'Daily')
        $ui.RbFreqWeekly.IsChecked  = ($s.CheckFrequency -eq 'Weekly')
        $ui.RbFreqNever.IsChecked   = ($s.CheckFrequency -eq 'Never')
        $ui.ChkNotify.IsChecked     = [bool]$s.Notifications
        $ui.RbGameReady.IsChecked   = ($s.NvidiaBranch -ne 'Studio')
        $ui.RbStudio.IsChecked      = ($s.NvidiaBranch -eq 'Studio')
        $ui.RbLight.IsChecked       = ($s.Theme -ne 'Dark')
        $ui.RbDark.IsChecked        = ($s.Theme -eq 'Dark')
        $ui.RbKeep1.IsChecked       = ([int]$s.BackupKeep -eq 1)
        $ui.RbKeep2.IsChecked       = ([int]$s.BackupKeep -eq 2)
        $ui.RbKeep3.IsChecked       = ([int]$s.BackupKeep -eq 3)
        $ui.RbKeep5.IsChecked       = ([int]$s.BackupKeep -eq 5)
        $ui.ChkAutoUpdate.IsChecked = [bool]$s.AutoUpdateCheck
        $ui.AppVersionText.Text     = "Version installée : $($script:AppVersion) · github.com/$($script:GitHubRepo)"
        $ui.BackupSizeText.Text     = "Espace utilisé actuellement par les sauvegardes : $(Format-Size (Get-BackupTotalSizeMB))"
        if (-not $ui.BackupSizeText.Text.EndsWith('o')) { $ui.BackupSizeText.Text += '0 Mo' }

        # Liste des mises à jour ignorées
        $ui.IgnoredPanel.Children.Clear()
        $ignored = @($s.IgnoredUpdates | Where-Object { $_ })
        $ui.IgnoredEmpty.Visibility = if ($ignored.Count) { 'Collapsed' } else { 'Visible' }
        foreach ($i in $ignored) {
            $grid = New-Columns @('*', 'Auto')
            $grid.Margin = New-Thickness 0 4 0 4
            $t = New-Text "$($i.Device) · version $($i.NewVersion)" 13
            $t.VerticalAlignment = 'Center'
            Add-ToGrid $grid $t 0
            $btn = New-Button -Text 'Ne plus ignorer' -Style 'BtnSmall' -Tag $i -Window $window
            $btn.Add_Click({
                param($src, $e)
                Remove-IgnoredUpdate -Device $src.Tag.Device -NewVersion $src.Tag.NewVersion -Settings $script:Settings
                Update-All
                Update-SettingsView
            })
            Add-ToGrid $grid $btn 1
            [void]$ui.IgnoredPanel.Children.Add($grid)
        }
        $script:LoadingSettings = $false
    }

    function Save-Setting([string]$Name, [object]$Value) {
        if ($script:LoadingSettings) { return }
        $script:Settings.$Name = $Value
        Save-AppSettings -Settings $script:Settings
        Write-Log "Paramètre modifié : $Name = $Value"
    }

    function Update-All {
        Update-Dashboard
        Update-UpdatesView
        Update-AllView
        Update-Activity
    }

    # ---------- Actions ----------
    function Start-Search {
        if ($script:CurrentJob) { return }
        Set-Busy $true 'Analyse en cours : NVIDIA et Windows Update (1 à 2 minutes)...'
        Start-BackgroundJob 'search' @($script:AppRoot) {
            param($root)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            $inv = @(Get-DeviceInventory)
            $upd = @(Find-DriverUpdate -Inventory $inv)
            # JSON : les listes imbriquées survivent au passage entre processus
            [pscustomobject]@{ Updates = $upd; Inventory = $inv } | ConvertTo-Json -Depth 4 -Compress
        }
    }

    function Start-Install {
        if ($script:CurrentJob) { return }
        $selected = @(Get-CheckedUpdates | Where-Object { $_ })
        if ($selected.Count -eq 0) { return }
        $names = ($selected | ForEach-Object { "- $($_.Device) ($($_.CurrentVersion) -> $($_.NewVersion))" }) -join "`r`n"
        $text  = "Installer ces pilotes ?`r`n`r`n$names`r`n`r`nLe pilote actuel sera sauvegardé avant (retour arrière possible dans « Sauvegardes »)."
        if ((Show-Message $text 'Confirmation' 'YesNo' 'Question') -ne 'Yes') { return }

        Write-Log ("Installation validée par l'utilisateur : " + (($selected | ForEach-Object { $_.Device }) -join ', '))
        Set-Busy $true 'Préparation de l''installation...'
        Start-BackgroundJob 'install' @($script:AppRoot, $selected, ($ui.ChkRestore.IsChecked -eq $true)) {
            param($root, $items, $restorePoint)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Install-DriverUpdate -Candidate $items -CreateRestorePoint:$restorePoint
        }
    }

    function Start-Restore([object]$Backup) {
        if ($script:CurrentJob) { [void](Show-Message 'Une opération est déjà en cours, patiente un peu.'); return }
        $current = (@($script:Inventory) | Where-Object { $_.Name -eq $Backup.Device } | Select-Object -First 1).DriverVersion
        $text = "Revenir à la version $($Backup.Version) de :`r`n$($Backup.Device) ?`r`n`r`nVersion actuelle : $current`r`n`r`n" +
                "Windows va réinstaller de force l'ancienne version. L'écran ou le son peuvent couper quelques secondes."
        if ((Show-Message $text 'Retour arrière' 'YesNo' 'Question') -ne 'Yes') { return }
        Set-Busy $true "Retour arrière : $($Backup.Device)..."
        Start-BackgroundJob 'install' @($script:AppRoot, $Backup.Path, ($ui.ChkRestore.IsChecked -eq $true)) {
            param($root, $path, $restorePoint)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Restore-DriverBackup -Path $path -CreateRestorePoint:$restorePoint
        }
    }

    function Start-AppUpdate {
        if ($script:CurrentJob -or -not $script:AppRelease) { return }
        $r = $script:AppRelease
        if ((Show-Message "Mettre à jour Driver en version $($r.Version) ?`r`n`r`nDriver se relancera tout seul à la fin." 'Mise à jour de Driver' 'YesNo' 'Question') -ne 'Yes') { return }
        Set-Busy $true "Mise à jour de Driver en version $($r.Version)..."
        Start-BackgroundJob 'selfupdate' @($script:AppRoot, $r.AssetUrl, $r.Version, $r.AssetWebUrl) {
            param($root, $url, $version, $webUrl)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Install-AppUpdate -AssetUrl $url -Version $version -AssetWebUrl $webUrl
        }
    }

    function Show-AppUpdateBanner([object]$Release) {
        $script:AppRelease = $Release
        if (-not $Release) { $ui.AppUpdateBanner.Visibility = 'Collapsed'; return }
        $ui.AppUpdateText.Text = "Une nouvelle version de Driver est disponible : $($Release.Version) (tu as la $($script:AppVersion))."
        $ui.AppUpdateBanner.Visibility = 'Visible'
    }

    function Start-PackageAnalysis([string]$Path) {
        if ($script:CurrentJob) { [void](Show-Message 'Une opération est déjà en cours, patiente un peu.'); return }
        Write-Log "Paquet déposé : $Path"
        Set-Busy $true ("Analyse du paquet « {0} »..." -f (Split-Path $Path -Leaf))
        Start-BackgroundJob 'analyze' @($script:AppRoot, $Path) {
            param($root, $p)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Get-DriverPackageAnalysis -Path $p | ConvertTo-Json -Depth 5
        }
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
                "`r`n`r`n" + $text + "Le pilote actuel sera sauvegardé avant.`r`nInstaller maintenant ?"
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

        if ((Show-Message $text 'Installer le paquet' 'YesNo' 'Question') -ne 'Yes') {
            Set-Busy $false (Get-StatusLine)
            return
        }

        Write-Log "Paquet manuel : installation validée par l'utilisateur ($($Analysis.Source))"
        Set-Busy $true 'Installation du paquet en cours... (l''écran ou le son peuvent couper quelques secondes)'
        Start-BackgroundJob 'install' @($script:AppRoot, $Json, ($ui.ChkRestore.IsChecked -eq $true)) {
            param($root, $json, $restorePoint)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Install-DriverPackage -Analysis ($json | ConvertFrom-Json) -CreateRestorePoint:$restorePoint
        }
    }

    # ---------- Surveillance du job en arrière-plan ----------
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if (-not $script:CurrentJob) { $timer.Stop(); return }

        # Progression écrite par le job (étape, %, Mo/s)
        $p = Get-TaskProgress
        if ($p -and $p.Stage) {
            $ui.StatusText.Text = if ($p.Detail) { "$($p.Stage) — $($p.Detail)" } else { [string]$p.Stage }
            if ([int]$p.Percent -ge 0) { $ui.Busy.IsIndeterminate = $false; $ui.Busy.Value = [int]$p.Percent }
            else { $ui.Busy.IsIndeterminate = $true }
        }

        if ([string]$script:CurrentJob.State -notin @('Completed', 'Failed', 'Stopped')) { return }

        $timer.Stop()
        $jobErrors = $null
        $output = @(Receive-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue -ErrorVariable jobErrors)
        $failed = ([string]$script:CurrentJob.State -ne 'Completed')
        Remove-Job -Job $script:CurrentJob -Force
        $script:CurrentJob = $null
        $errText = (@($jobErrors) | Where-Object { $_ } | ForEach-Object { $_.ToString() }) -join "`r`n"
        if ($errText) { Write-Log "Erreur dans la tâche de fond ($($script:JobKind)) : $errText" 'ERREUR' }

        switch ($script:JobKind) {
            'search' {
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
            'analyze' {
                $json = ($output | Where-Object { $_ -is [string] }) -join "`n"
                if ($failed -or -not $json) {
                    Set-Busy $false (Get-StatusLine)
                    [void](Show-Message "Impossible d'analyser ce paquet.`r`n`r`n$errText" 'Driver' 'OK' 'Error')
                } else {
                    Confirm-PackageInstall -Analysis ($json | ConvertFrom-Json) -Json $json
                }
            }
            'selfupdate' {
                $r = $output | Where-Object { $_ -and $_.PSObject.Properties['Success'] } | Select-Object -First 1
                Set-Busy $false (Get-StatusLine)
                if ($r -and $r.Success) {
                    [void](Show-Message "$($r.Message).`r`n`r`nDriver va redémarrer pour utiliser la nouvelle version." 'Mise à jour de Driver')
                    $script:RestartRequested = $true
                    $window.Close()
                } else {
                    $why = if ($r) { $r.Message } else { $errText }
                    [void](Show-Message "La mise à jour de Driver a échoué.`r`n`r`n$why" 'Mise à jour de Driver' 'OK' 'Error')
                }
            }
            'install' {
                $results = @($output | Where-Object { $_ -and $_.PSObject.Properties['Success'] })
                $ok      = @($results | Where-Object { $_.Success }).Count
                $reboot  = @($results | Where-Object { $_.RebootRequired }).Count -gt 0

                $msg = "$ok opération(s) réussie(s) sur $($results.Count)."
                if ($results.Count -gt 0) {
                    $msg += "`r`n`r`n" + (($results | ForEach-Object { "- $($_.Device) : $($_.Message)" }) -join "`r`n")
                }
                if ($errText) { $msg += "`r`n`r`nErreur : $errText" }
                Set-Busy $false 'Opération terminée.'
                Update-Activity
                if ($ui.ViewBackups.Visibility -eq 'Visible') { Update-BackupsView }

                if ($reboot) {
                    if ((Show-Message "$msg`r`n`r`nUn redémarrage est nécessaire. Redémarrer maintenant ?" 'Driver' 'YesNo' 'Question') -eq 'Yes') {
                        Restart-Computer -Force
                    }
                } else {
                    [void](Show-Message $msg)
                }
                Start-Search
            }
        }
    })

    # ---------- Événements : menu et boutons ----------
    $ui.NavDashboard.Add_Click({ Set-View 'dashboard' })
    $ui.NavUpdates.Add_Click({ Set-View 'updates' })
    $ui.NavAll.Add_Click({ Set-View 'all' })
    $ui.NavBackups.Add_Click({ Set-View 'backups' })
    $ui.NavHistory.Add_Click({ Set-View 'history' })
    $ui.NavSettings.Add_Click({ Set-View 'settings' })
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
    $ui.BtnAppUpdate.Add_Click({ Start-AppUpdate })
    $ui.BtnAppUpdateLater.Add_Click({ $ui.AppUpdateBanner.Visibility = 'Collapsed' })

    $ui.BtnBackupsClear.Add_Click({
        if ((Show-Message "Supprimer TOUTES les sauvegardes de pilotes ?`r`n`r`nLe retour arrière ne sera plus possible." 'Sauvegardes' 'YesNo' 'Warning') -eq 'Yes') {
            Clear-AllBackups
            Update-BackupsView
        }
    })

    $ui.BtnReport.Add_Click({
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            $path = Export-DriverReport
            Start-Process $path
            $ui.StatusText.Text = "Rapport enregistré sur le Bureau : $(Split-Path $path -Leaf)"
        } catch {
            [void](Show-Message "Impossible de créer le rapport : $($_.Exception.Message)" 'Rapport' 'OK' 'Error')
        } finally {
            $window.Cursor = $null
        }
    })

    # ---------- Événements : paramètres (enregistrés à chaque changement) ----------
    $ui.RbFreqStartup.Add_Checked({ Save-Setting 'CheckFrequency' 'Startup' })
    $ui.RbFreqDaily.Add_Checked({   Save-Setting 'CheckFrequency' 'Daily' })
    $ui.RbFreqWeekly.Add_Checked({  Save-Setting 'CheckFrequency' 'Weekly' })
    $ui.RbFreqNever.Add_Checked({   Save-Setting 'CheckFrequency' 'Never' })
    $ui.ChkNotify.Add_Click({       Save-Setting 'Notifications' ($ui.ChkNotify.IsChecked -eq $true) })
    $ui.RbGameReady.Add_Checked({   Save-Setting 'NvidiaBranch' 'GameReady' })
    $ui.RbStudio.Add_Checked({      Save-Setting 'NvidiaBranch' 'Studio' })
    $ui.RbLight.Add_Checked({ Save-Setting 'Theme' 'Light'; Set-Theme 'Light' })
    $ui.RbDark.Add_Checked({  Save-Setting 'Theme' 'Dark';  Set-Theme 'Dark' })
    foreach ($n in @(1, 2, 3, 5)) {
        $ui["RbKeep$n"].Tag = $n
        $ui["RbKeep$n"].Add_Checked({
            param($s, $e)
            if ($script:LoadingSettings) { return }
            Save-Setting 'BackupKeep' ([int]$s.Tag)
            Limit-AllBackups -Keep ([int]$s.Tag)
            $ui.BackupSizeText.Text = "Espace utilisé actuellement par les sauvegardes : $(Format-Size (Get-BackupTotalSizeMB))"
        })
    }
    $ui.ChkAutoUpdate.Add_Click({ Save-Setting 'AutoUpdateCheck' ($ui.ChkAutoUpdate.IsChecked -eq $true) })
    $ui.BtnCheckAppUpdate.Add_Click({
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            $latest = Get-LatestAppRelease
            if ((Compare-DriverVersion -A $latest.Version -B $script:AppVersion) -eq 1 -and $latest.AssetUrl) {
                Show-AppUpdateBanner $latest
            } else {
                [void](Show-Message "Tu as déjà la dernière version de Driver ($($script:AppVersion))." 'Driver')
            }
        } catch {
            [void](Show-Message "Impossible de joindre GitHub : $($_.Exception.Message)" 'Driver' 'OK' 'Warning')
        } finally {
            $window.Cursor = $null
        }
    })

    # ---------- Fenêtre ----------
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
        if ($script:CurrentJob -and $script:JobKind -in @('install', 'selfupdate')) {
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
            # Lancement au démarrage : l'analyse est déjà faite
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
        if ($script:Settings.AutoUpdateCheck) { Show-AppUpdateBanner (Test-AppUpdate) }
    })

    Set-Theme $script:Settings.Theme
    [void]$window.ShowDialog()
    $timer.Stop()
}
