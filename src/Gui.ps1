# =============================================================================
#  Gui.ps1 - Fenêtre graphique (Windows Forms)
#
#  Les opérations longues (recherche, installation) tournent dans un job
#  PowerShell en arrière-plan pour que la fenêtre ne se fige pas. Un Timer
#  vérifie toutes les 500 ms si le job est terminé.
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-MainWindow {
    param(
        [object[]]$InitialResults,   # résultats déjà trouvés (lancement au démarrage)
        [switch]$AutoSearch          # lance une recherche dès l'ouverture
    )

    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:CurrentJob = $null
    $script:JobKind    = $null
    $script:LastResults   = @()
    $script:VendorDrivers = $null

    # ---------- Fenêtre ----------
    $form = New-Object System.Windows.Forms.Form
    $form.Text          = 'Driver - Mise à jour des pilotes'
    $form.Size          = New-Object System.Drawing.Size(940, 560)
    $form.MinimumSize   = New-Object System.Drawing.Size(720, 400)
    $form.StartPosition = 'CenterScreen'
    $form.Font          = New-Object System.Drawing.Font('Segoe UI', 9)

    # ---------- Bandeau d'état (haut) ----------
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Dock      = 'Top'
    $lblStatus.Height    = 40
    $lblStatus.TextAlign = 'MiddleLeft'
    $lblStatus.Padding   = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $lblStatus.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

    # ---------- Liste des mises à jour ----------
    $list = New-Object System.Windows.Forms.ListView
    $list.Dock          = 'Fill'
    $list.View          = 'Details'
    $list.CheckBoxes    = $true
    $list.FullRowSelect = $true
    $list.GridLines     = $true
    foreach ($col in @(@('Périphérique', 330), @('Source', 120), @('Version actuelle', 140), @('Nouvelle version', 140), @('Taille', 80))) {
        [void]$list.Columns.Add($col[0], $col[1])
    }

    # ---------- Barre du bas : options + boutons ----------
    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock          = 'Bottom'
    $panel.Height        = 48
    $panel.Padding       = New-Object System.Windows.Forms.Padding(8)
    $panel.FlowDirection = 'LeftToRight'

    $btnSearch  = New-Object System.Windows.Forms.Button -Property @{ Text = 'Rechercher'; Width = 110; Height = 30 }
    $btnInstall = New-Object System.Windows.Forms.Button -Property @{ Text = 'Installer la sélection'; Width = 160; Height = 30; Enabled = $false }
    $btnLogs    = New-Object System.Windows.Forms.Button -Property @{ Text = 'Journaux'; Width = 90; Height = 30 }
    $btnClose   = New-Object System.Windows.Forms.Button -Property @{ Text = 'Fermer'; Width = 90; Height = 30 }
    $chkAll     = New-Object System.Windows.Forms.CheckBox -Property @{ Text = 'Afficher tous les pilotes'; Checked = $false; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding(12, 8, 0, 0)) }
    $chkRestore = New-Object System.Windows.Forms.CheckBox -Property @{ Text = 'Créer un point de restauration'; Checked = $true; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding(12, 8, 12, 0)) }
    $progress   = New-Object System.Windows.Forms.ProgressBar -Property @{ Width = 150; Height = 20; Style = 'Marquee'; Visible = $false; Margin = (New-Object System.Windows.Forms.Padding(6, 6, 0, 0)) }

    $panel.Controls.AddRange(@($btnSearch, $btnInstall, $chkRestore, $chkAll, $btnLogs, $btnClose, $progress))
    $form.Controls.Add($lblStatus)
    $form.Controls.Add($panel)
    $form.Controls.Add($list)
    $list.BringToFront()   # la zone "Fill" doit être devant pour respecter les zones Top/Bottom

    # ---------- Fonctions internes ----------
    function Set-Busy([bool]$Busy, [string]$Text) {
        $lblStatus.Text      = $Text
        $progress.Visible    = $Busy
        $btnSearch.Enabled   = -not $Busy
        $btnInstall.Enabled  = (-not $Busy) -and ($list.Items.Count -gt 0)
        $form.UseWaitCursor  = $Busy
    }

    function Update-ResultList([object[]]$Results) {
        $script:LastResults = @($Results | Where-Object { $_ })
        $list.BeginUpdate()
        $list.Items.Clear()
        foreach ($r in $script:LastResults) {
            if (-not $r) { continue }
            $item = New-Object System.Windows.Forms.ListViewItem([string]$r.Device)
            [void]$item.SubItems.Add([string]$r.Source)
            [void]$item.SubItems.Add([string]$r.CurrentVersion)
            [void]$item.SubItems.Add([string]$r.NewVersion)
            $size = if ($r.SizeMB -gt 0) { '{0} Mo' -f $r.SizeMB } else { '-' }
            [void]$item.SubItems.Add($size)
            $item.ToolTipText = [string]$r.Title
            $item.Checked = $true
            $item.Tag     = $r
            [void]$list.Items.Add($item)
        }

        # Option "Afficher tous les pilotes" : on ajoute en gris ceux qui sont à jour
        if ($chkAll.Checked) {
            if (-not $script:VendorDrivers) { $script:VendorDrivers = @(Get-VendorDriverList) }
            $withUpdate = @($script:LastResults | ForEach-Object { $_.Device })
            foreach ($d in $script:VendorDrivers) {
                if ($withUpdate -contains $d.Name) { continue }
                $item = New-Object System.Windows.Forms.ListViewItem([string]$d.Name)
                [void]$item.SubItems.Add([string]$d.Manufacturer)
                [void]$item.SubItems.Add([string]$d.DriverVersion)
                [void]$item.SubItems.Add('À jour')
                [void]$item.SubItems.Add('')
                $item.ForeColor   = [System.Drawing.Color]::Gray
                $item.ToolTipText = [string]$d.HardwareId
                $item.Tag         = $null      # rien à installer
                [void]$list.Items.Add($item)
            }
        }
        $list.EndUpdate()
        $list.ShowItemToolTips = $true

        $count = $script:LastResults.Count
        if ($count -eq 0) {
            Set-Busy $false 'Tous les pilotes sont à jour.'
        } else {
            Set-Busy $false ("{0} mise(s) à jour disponible(s). Coche celles à installer puis clique sur « Installer la sélection »." -f $count)
        }
        $btnInstall.Enabled = ($count -gt 0)
    }

    function Start-Search {
        Set-Busy $true 'Recherche des mises à jour en cours (cela peut prendre 1 à 2 minutes)...'
        $list.Items.Clear()
        $script:VendorDrivers = $null   # l'inventaire sera relu après la recherche
        $script:JobKind    = 'search'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot -ScriptBlock {
            param($root)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Find-DriverUpdate
        }
        $timer.Start()
    }

    # ---------- Timer de surveillance du job ----------
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $timer.Add_Tick({
        if (-not $script:CurrentJob) { return }
        if ([string]$script:CurrentJob.State -notin @('Completed', 'Failed', 'Stopped')) { return }

        $timer.Stop()
        $output = @(Receive-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue)
        $failed = ($script:CurrentJob.State -ne 'Completed')
        Remove-Job -Job $script:CurrentJob -Force
        $script:CurrentJob = $null

        if ($script:JobKind -eq 'search') {
            Update-ResultList $output
            if ($failed) { $lblStatus.Text = 'La recherche a échoué : consulte les journaux.' }
        }
        elseif ($script:JobKind -eq 'install') {
            $ok     = @($output | Where-Object { $_.Success }).Count
            $ko     = @($output | Where-Object { -not $_.Success })
            $reboot = @($output | Where-Object { $_.RebootRequired }).Count -gt 0

            $msg = "$ok pilote(s) installé(s) avec succès."
            if ($ko.Count -gt 0) {
                $msg += "`r`n`r`nÉchecs :`r`n" + (($ko | ForEach-Object { "- $($_.Device) : $($_.Message)" }) -join "`r`n")
            }
            Set-Busy $false 'Installation terminée.'

            if ($reboot) {
                $answer = [System.Windows.Forms.MessageBox]::Show("$msg`r`n`r`nUn redémarrage est nécessaire. Redémarrer maintenant ?", 'Driver', 'YesNo', 'Question')
                if ($answer -eq 'Yes') { Restart-Computer -Force }
            } else {
                [void][System.Windows.Forms.MessageBox]::Show($msg, 'Driver', 'OK', 'Information')
            }
            Start-Search
        }
    })

    # ---------- Événements des boutons ----------
    $btnSearch.Add_Click({ Start-Search })

    # Bascule "Afficher tous les pilotes" (sans relancer de recherche)
    $chkAll.Add_CheckedChanged({
        if (-not $script:CurrentJob) { Update-ResultList $script:LastResults }
    })

    # Les lignes "À jour" ne peuvent pas être cochées
    $list.Add_ItemCheck({
        param($s, $e)
        if ($null -eq $list.Items[$e.Index].Tag) { $e.NewValue = [System.Windows.Forms.CheckState]::Unchecked }
    })

    $btnInstall.Add_Click({
        $selected = @($list.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { $_ })
        if ($selected.Count -eq 0) {
            [void][System.Windows.Forms.MessageBox]::Show('Aucun pilote coché.', 'Driver', 'OK', 'Warning')
            return
        }
        $names   = ($selected | ForEach-Object { "- $($_.Device) ($($_.CurrentVersion) -> $($_.NewVersion))" }) -join "`r`n"
        $confirm = [System.Windows.Forms.MessageBox]::Show("Installer ces pilotes ?`r`n`r`n$names", 'Confirmation', 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }

        Write-Log ("Installation validée par l'utilisateur : " + (($selected | ForEach-Object { $_.Device }) -join ', '))
        Set-Busy $true 'Installation en cours... Ne pas éteindre l''ordinateur (l''écran peut clignoter).'
        $btnInstall.Enabled = $false
        $script:JobKind    = 'install'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot, $selected, $chkRestore.Checked -ScriptBlock {
            param($root, $items, $restorePoint)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Install-DriverUpdate -Candidate $items -CreateRestorePoint:$restorePoint
        }
        $timer.Start()
    })

    $btnLogs.Add_Click({ Start-Process explorer.exe -ArgumentList $script:LogDir })
    $btnClose.Add_Click({ $form.Close() })

    $form.Add_FormClosing({
        param($s, $e)
        if ($script:CurrentJob -and $script:JobKind -eq 'install') {
            [void][System.Windows.Forms.MessageBox]::Show('Une installation est en cours, merci de patienter.', 'Driver', 'OK', 'Warning')
            $e.Cancel = $true
        }
        elseif ($script:CurrentJob) {
            # Recherche en cours : on l'arrête proprement
            Stop-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $script:CurrentJob -Force -ErrorAction SilentlyContinue
            $script:CurrentJob = $null
        }
    })

    $form.Add_Shown({
        $form.Activate()
        if ($InitialResults) { Update-ResultList $InitialResults }
        elseif ($AutoSearch)  { Start-Search }
        else                  { Set-Busy $false 'Clique sur « Rechercher » pour vérifier tes pilotes.' }
    })

    [void]$form.ShowDialog()
    $timer.Dispose()
    $form.Dispose()
}
