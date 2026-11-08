# =============================================================================
#  Gui.ps1 - Fenêtre graphique (Windows Forms)
#
#  Les opérations longues (recherche, installation) tournent dans un job
#  PowerShell en arrière-plan pour que la fenêtre ne se fige pas. Un Timer
#  vérifie toutes les 500 ms si le job est terminé.
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'DropTarget.ps1')

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
    $form.Text          = 'Driver - Mise à jour des pilotes  (glisse ici un ZIP de pilotes pour l''installer)'
    $form.Size          = New-Object System.Drawing.Size(1080, 580)
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
    $panel.AutoSize      = $true             # passe sur 2 lignes si la fenêtre est étroite
    $panel.AutoSizeMode  = 'GrowAndShrink'
    $panel.Padding       = New-Object System.Windows.Forms.Padding(8)
    $panel.FlowDirection = 'LeftToRight'

    $btnSearch  = New-Object System.Windows.Forms.Button -Property @{ Text = 'Rechercher'; Width = 110; Height = 30 }
    $btnInstall = New-Object System.Windows.Forms.Button -Property @{ Text = 'Installer la sélection'; Width = 160; Height = 30; Enabled = $false }
    $btnPackage = New-Object System.Windows.Forms.Button -Property @{ Text = 'Installer un paquet…'; Width = 140; Height = 30 }
    $btnBoard   = New-Object System.Windows.Forms.Button -Property @{ Text = 'Site carte mère'; Width = 120; Height = 30 }
    $btnLogs    = New-Object System.Windows.Forms.Button -Property @{ Text = 'Journaux'; Width = 90; Height = 30 }
    $btnClose   = New-Object System.Windows.Forms.Button -Property @{ Text = 'Fermer'; Width = 90; Height = 30 }
    $chkAll     = New-Object System.Windows.Forms.CheckBox -Property @{ Text = 'Afficher tous les pilotes'; Checked = $false; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding(12, 8, 0, 0)) }
    $chkRestore = New-Object System.Windows.Forms.CheckBox -Property @{ Text = 'Créer un point de restauration'; Checked = $true; AutoSize = $true; Margin = (New-Object System.Windows.Forms.Padding(12, 8, 12, 0)) }
    $progress   = New-Object System.Windows.Forms.ProgressBar -Property @{ Width = 150; Height = 20; Style = 'Marquee'; Visible = $false; Margin = (New-Object System.Windows.Forms.Padding(6, 6, 0, 0)) }

    $panel.Controls.AddRange(@($btnSearch, $btnInstall, $btnPackage, $chkRestore, $chkAll, $btnBoard, $btnLogs, $btnClose, $progress))
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

    function Start-PackageAnalysis([string]$Path) {
        if ($script:CurrentJob) {
            [void][System.Windows.Forms.MessageBox]::Show('Une opération est déjà en cours, patiente un peu.', 'Driver', 'OK', 'Information')
            return
        }
        Write-Log "Paquet déposé : $Path"
        Set-Busy $true ("Analyse du paquet « {0} »..." -f (Split-Path $Path -Leaf))
        $script:JobKind    = 'analyze'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot, $Path -ScriptBlock {
            param($root, $p)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            # JSON : les objets imbriqués survivent au passage entre processus
            Get-DriverPackageAnalysis -Path $p | ConvertTo-Json -Depth 5
        }
        $timer.Start()
    }

    function Show-PackageDiagnostic([object]$Analysis) {
        # Explique POURQUOI rien n'a été trouvé, pour distinguer "mauvais paquet" et "problème"
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('Aucun pilote de ce paquet ne correspond au matériel de ce PC.')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine(("Contenu du paquet : {0} fichier(s), dont {1} pilote(s) .inf et {2} programme(s) .exe." -f $Analysis.FileCount, $Analysis.InfCount, $Analysis.ExeCount))
        [void]$sb.AppendLine()

        $infList = @($Analysis.InfSummary | Where-Object { $_ })
        if ($Analysis.InfCount -eq 0 -and $Analysis.ExeCount -eq 0) {
            [void]$sb.AppendLine('=> Ce paquet ne contient ni pilote (.inf) ni installateur (.exe). Ce n''est probablement pas un pilote (manuel, utilitaire, BIOS ?).')
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
        [void]$sb.AppendLine('Détails complets dans les journaux (bouton « Journaux »).')
        [void][System.Windows.Forms.MessageBox]::Show($sb.ToString(), 'Driver - paquet non compatible', 'OK', 'Warning')
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
            Set-Busy $false 'Déjà à jour.'
            [void][System.Windows.Forms.MessageBox]::Show($text + 'Tu es déjà à jour : ce paquet ne contient pas de version plus récente que la tienne.', 'Driver - déjà à jour', 'OK', 'Information')
            return
        }
        elseif ($Analysis.InfCount -eq 0 -and $Analysis.Setup -and $Analysis.SetupSigned) {
            # Pas de .inf lisible : le pilote est enfermé dans l'installateur du constructeur
            $text = "Ce paquet ne contient pas de pilote installable directement : il passe par son propre installateur.`r`n`r`n" +
                "Lancer « $(Split-Path $Analysis.Setup -Leaf) » (signé par $($Analysis.SetupSigner)) ?`r`n" +
                'Tu devras suivre ses étapes.'
        }
        elseif ($Analysis.InfCount -eq 0 -and $Analysis.Setup) {
            Set-Busy $false 'Paquet refusé.'
            [void][System.Windows.Forms.MessageBox]::Show("L'installateur « $(Split-Path $Analysis.Setup -Leaf) » n'a pas de signature numérique valide : il est refusé par sécurité.", 'Driver', 'OK', 'Warning')
            return
        }
        else {
            Set-Busy $false 'Ce paquet ne correspond pas à ton matériel.'
            Show-PackageDiagnostic -Analysis $Analysis
            return
        }

        if ([System.Windows.Forms.MessageBox]::Show($text, 'Installer le paquet', 'YesNo', 'Question') -ne 'Yes') {
            Set-Busy $false 'Installation du paquet annulée.'
            return
        }

        Write-Log "Paquet manuel : installation validée par l'utilisateur ($($Analysis.Source))"
        Set-Busy $true 'Installation du paquet en cours... (l''écran ou le son peuvent couper quelques secondes)'
        $script:JobKind    = 'install'
        $script:CurrentJob = Start-Job -ArgumentList $script:AppRoot, $Json, $chkRestore.Checked -ScriptBlock {
            param($root, $json, $restorePoint)
            . (Join-Path $root 'src\Loader.ps1')
            Initialize-AppFolder
            Install-DriverPackage -Analysis ($json | ConvertFrom-Json) -CreateRestorePoint:$restorePoint
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
        $jobErrors = $null
        $output = @(Receive-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue -ErrorVariable jobErrors)
        $errText = (@($jobErrors) | Where-Object { $_ } | ForEach-Object { $_.ToString() }) -join "`r`n"
        if ($errText) { Write-Log "Erreur dans la tâche de fond ($($script:JobKind)) : $errText" 'ERREUR' }
        $failed = ($script:CurrentJob.State -ne 'Completed')
        Remove-Job -Job $script:CurrentJob -Force
        $script:CurrentJob = $null

        if ($script:JobKind -eq 'search') {
            Update-ResultList $output
            if ($failed) { $lblStatus.Text = 'La recherche a échoué : consulte les journaux.' }
        }
        elseif ($script:JobKind -eq 'analyze') {
            $json = ($output | Where-Object { $_ -is [string] }) -join "`n"
            if ($failed -or -not $json) {
                Set-Busy $false 'Analyse du paquet impossible.'
                [void][System.Windows.Forms.MessageBox]::Show("Impossible d'analyser ce paquet.`r`n`r`n$errText", 'Driver', 'OK', 'Error')
            } else {
                Confirm-PackageInstall -Analysis ($json | ConvertFrom-Json) -Json $json
            }
        }
        elseif ($script:JobKind -eq 'install') {
            $ok     = @($output | Where-Object { $_.Success }).Count
            $ko     = @($output | Where-Object { -not $_.Success })
            $reboot = @($output | Where-Object { $_.RebootRequired }).Count -gt 0

            $msg = "$ok opération(s) réussie(s) sur $(@($output).Count)."
            if (@($output).Count -gt 0) {
                $msg += "`r`n`r`n" + (($output | ForEach-Object { "- $($_.Device) : $($_.Message)" }) -join "`r`n")
            }
            if ($errText) { $msg += "`r`n`r`nErreur : $errText" }
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

    $btnPackage.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = 'Choisir un paquet de pilotes'
        $dlg.Filter = 'Paquets de pilotes (*.zip;*.exe)|*.zip;*.exe|Tous les fichiers (*.*)|*.*'
        if ($dlg.ShowDialog($form) -eq 'OK') { Start-PackageAnalysis $dlg.FileName }
    })

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

    # Carte mère : on affiche le modèle dans l'info-bulle et on ouvre sa page support
    try {
        $board = Get-MotherboardInfo
        $toolTip = New-Object System.Windows.Forms.ToolTip
        $toolTip.SetToolTip($btnBoard, "Ouvre la page des pilotes de ta carte mère : $($board.Manufacturer) $($board.Product)")
    } catch { $board = $null }
    $btnBoard.Add_Click({
        $url = Get-MotherboardSupportUrl -Board $board
        Write-Log "Ouverture de la page support carte mère : $url"
        Start-Process $url
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
        # Glisser-déposer : sur la liste et sur la fenêtre
        try {
            $script:DropTargets = @(
                (New-Object ElevatedDropTarget -ArgumentList $list),
                (New-Object ElevatedDropTarget -ArgumentList $form)
            )
            foreach ($dt in $script:DropTargets) {
                $dt.add_FilesDropped({ param($s, $e) if ($e.Files.Count -gt 0) { Start-PackageAnalysis $e.Files[0] } })
            }
        } catch {
            Write-Log "Glisser-déposer indisponible : $($_.Exception.Message)" 'WARN'
        }
        if ($InitialResults) { Update-ResultList $InitialResults }
        elseif ($AutoSearch)  { Start-Search }
        else                  { Set-Busy $false 'Clique sur « Rechercher » pour vérifier tes pilotes.' }
    })

    [void]$form.ShowDialog()
    $timer.Dispose()
    $form.Dispose()
}
