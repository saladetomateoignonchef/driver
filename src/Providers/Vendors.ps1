# =============================================================================
#  Providers/Vendors.ps1 - Vérification sur les sites des fabricants
#
#  Pour chaque fabricant présent dans le PC (Intel, AMD, Realtek...), Driver :
#   1. essaie de lire la dernière version sur la page officielle (quand une règle
#      de lecture existe, ex. pilote graphique Intel) ;
#   2. si la page répond avec une version plus récente ET un lien direct :
#      mise à jour proposée (téléchargement, signature vérifiée, installation) ;
#   3. sinon (site qui refuse les programmes : « 403 Access Denied », version
#      illisible...) : un bouton au nom du fabricant est proposé dans la fenêtre.
#      L'utilisateur télécharge le pilote et le glisse dans Driver.
#  Driver ne se fait pas passer pour un navigateur pour contourner un blocage.
# =============================================================================

$script:VendorCatalog = @(
    @{
        Name = 'Intel'; Test = { $_.VendorId -eq '8086' -and $_.Class -eq 'DISPLAY' }
        Url  = 'https://www.intel.com/content/www/us/en/download/785597/intel-arc-iris-xe-graphics-windows.html'
        VersionRegex  = '32\.0\.101\.\d{4}'
        DownloadRegex = 'https://downloadmirror\.intel\.com/\d+/gfx_win_[\d.]+\.(?:zip|exe)'
        Signer = 'Intel Corporation'
    }
    @{ Name = 'Intel';    Test = { $_.VendorId -in @('8086', '8087') -and $_.Class -ne 'DISPLAY' }
       Url = 'https://www.intel.fr/content/www/fr/fr/support/detect.html' }
    @{ Name = 'AMD';      Test = { $_.VendorId -in @('1002', '1022') }
       Url = 'https://www.amd.com/fr/support/download/drivers.html' }
    @{ Name = 'Realtek';  Test = { $_.VendorId -eq '10EC' }; Url = 'board' }       # pilotes Realtek : page de la carte mère
    @{ Name = 'Qualcomm'; Test = { $_.VendorId -in @('168C', '17CB') }; Url = 'search' }
    @{ Name = 'MediaTek'; Test = { $_.VendorId -eq '14C3' }; Url = 'search' }
    @{ Name = 'Broadcom'; Test = { $_.VendorId -eq '14E4' }; Url = 'search' }
)

function Get-VendorPageUrl([hashtable]$Rule, [object[]]$Devices) {
    switch ($Rule.Url) {
        'board' {
            $board = @(Get-AppLinks | Where-Object { $_.Category -eq (T 'CatBoard') }) | Select-Object -First 1
            if ($board) { return $board.Url }
            return (Get-MotherboardSupportUrl)
        }
        'search' { return (Get-SearchUrl "$($Rule.Name) $($Devices[0].Name)") }
        default  { return $Rule.Url }
    }
}

function Get-VendorCheck {
    <#
        Renvoie, par fabricant : Status (update / uptodate / blocked / manual), Url (page à
        ouvrir), Devices, et Candidates (mises à jour automatiques trouvées).
    #>
    param([object[]]$Inventory)
    $physical = @(Select-PhysicalDevice -Inventory $Inventory)
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($rule in $script:VendorCatalog) {
        $devices = @($physical | Where-Object -FilterScript $rule.Test)
        if ($devices.Count -eq 0) { continue }
        $url = Get-VendorPageUrl $rule $devices
        $status = 'manual'; $candidates = @(); $latest = $null

        if ($rule.VersionRegex) {
            Set-TaskProgress -Stage (T 'StageVendor' $rule.Name)
            try {
                $page = Invoke-WebRequest -Uri $rule.Url -UseBasicParsing -UserAgent $script:UserAgent -TimeoutSec 15
                $versions = @([regex]::Matches($page.Content, $rule.VersionRegex) | ForEach-Object { $_.Value } | Sort-Object { [version]$_ } -Descending)
                $download = [regex]::Match($page.Content, $rule.DownloadRegex)
                if ($versions.Count) {
                    $latest = $versions[0]
                    $status = 'uptodate'
                    foreach ($d in $devices) {
                        if ((Compare-DriverVersion -A $latest -B $d.DriverVersion) -eq 1) {
                            if ($download.Success) {
                                $c = New-UpdateCandidate -Source $rule.Name -Device $d.Name -CurrentVersion $d.DriverVersion `
                                    -NewVersion $latest -Key $download.Value -Title (T 'VendorSite' $rule.Name)
                                $c | Add-Member -NotePropertyName DriverClass -NotePropertyValue $d.Class
                                $c | Add-Member -NotePropertyName Signer -NotePropertyValue $rule.Signer
                                $candidates += $c
                                $status = 'update'
                            } else { $status = 'manual' }       # version plus récente mais pas de lien direct
                        }
                    }
                }
                Write-Log "Site $($rule.Name) : dernière version lue $latest ($status)"
            } catch {
                $code = $null
                if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
                $status = 'blocked'
                Write-Log "Site $($rule.Name) inaccessible aux programmes ($code $($_.Exception.Message)) : bouton proposé" 'WARN'
            }
        }

        $existing = $checks | Where-Object { $_.Vendor -eq $rule.Name -and $_.Url -eq $url } | Select-Object -First 1
        if ($existing) {
            $existing.Devices = @($existing.Devices) + @($devices | ForEach-Object { "$($_.Name) ($($_.DriverVersion))" })
            continue
        }
        $checks.Add([pscustomobject]@{
            Vendor     = $rule.Name
            Url        = $url
            Status     = $status
            Latest     = $latest
            Devices    = @($devices | ForEach-Object { "$($_.Name) ($($_.DriverVersion))" })
            Candidates = $candidates
        })
    }
    return $checks.ToArray()
}

function Install-VendorDriver {
    <# Télécharge le fichier du fabricant, vérifie sa signature puis l'installe comme un paquet manuel. #>
    param([Parameter(Mandatory)][object]$Candidate)
    $name = Split-Path ([uri]$Candidate.Key).AbsolutePath -Leaf
    $file = Join-Path $script:DownloadDir $name
    Invoke-FileDownload -Url $Candidate.Key -OutFile $file -Label "$($Candidate.Source) $($Candidate.NewVersion)"
    if ($file -like '*.exe' -and $Candidate.Signer) {
        $sig = Get-AuthenticodeSignature -FilePath $file
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch [regex]::Escape($Candidate.Signer)) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            throw (T 'MsgBadSignature' $sig.Status)
        }
    }
    $analysis = Get-DriverPackageAnalysis -Path $file
    return @(Install-DriverPackage -Analysis $analysis)
}
