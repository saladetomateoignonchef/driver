# =============================================================================
#  Notify.ps1 - Notification au démarrage (icône dans la zone de notification)
#
#  Au lieu d'ouvrir directement la fenêtre, on affiche une notification Windows
#  "N mises à jour disponibles". Un clic dessus (ou sur l'icône) ouvre Driver.
#  L'icône reste 1 heure dans la zone de notification, puis Driver se ferme.
# =============================================================================

function Show-UpdateNotification {
    <# Renvoie $true si l'utilisateur veut ouvrir Driver. #>
    param([int]$Count, [string]$Summary, [string]$Title)
    if (-not $Title) { $Title = T 'NotifyTitle' $Count }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:NotifyOpen = $false
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $iconFile = Join-Path $script:AppRoot 'src\driver.ico'
    $icon.Icon = if (Test-Path $iconFile) {
        New-Object System.Drawing.Icon((New-Object System.IO.MemoryStream(, [IO.File]::ReadAllBytes($iconFile))))   # sans verrouiller le fichier
    } else { [System.Drawing.SystemIcons]::Information }
    $icon.Text = 'Driver : ' + $(if ($Title.Length -gt 50) { $Title.Substring(0, 50) } else { $Title })

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $itemOpen  = $menu.Items.Add((T 'NotifyOpen'))
    $itemLater = $menu.Items.Add((T 'Later'))
    $icon.ContextMenuStrip = $menu

    $open  = { $script:NotifyOpen = $true; [System.Windows.Forms.Application]::ExitThread() }
    $later = { [System.Windows.Forms.Application]::ExitThread() }
    $icon.Add_BalloonTipClicked($open)
    $icon.Add_DoubleClick($open)
    $itemOpen.Add_Click($open)
    $itemLater.Add_Click($later)

    # Sans réponse au bout d'une heure, on libère la place
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 3600000
    $timer.Add_Tick($later)
    $timer.Start()

    $icon.Visible = $true
    $icon.BalloonTipTitle = $Title
    $icon.BalloonTipText  = "$Summary`n$(T 'NotifyClick')"
    $icon.BalloonTipIcon  = 'Info'
    $icon.ShowBalloonTip(15000)
    Write-Log "Notification affichée : $Count mise(s) à jour"

    [System.Windows.Forms.Application]::Run()   # attend un clic (ou le délai)

    $timer.Stop(); $timer.Dispose()
    $icon.Visible = $false
    $icon.Dispose()
    Write-Log ("Notification : {0}" -f $(if ($script:NotifyOpen) { 'ouverture demandée' } else { 'ignorée / plus tard' }))
    return $script:NotifyOpen
}
