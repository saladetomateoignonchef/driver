# Driver — mise à jour automatique des pilotes (Windows 11)

Application PowerShell avec interface graphique qui détecte les pilotes obsolètes
de mon PC et me propose de les mettre à jour. **Rien n'est installé sans ma validation.**

![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-blue) ![Windows 11](https://img.shields.io/badge/Windows-11-0078D6)

## Fonctionnement

```
 ┌──────────────┐   WMI (Win32_PnPSignedDriver)
 │  Inventaire  │ ─────────────────────────────►  liste des périphériques + versions
 └──────┬───────┘
        │
        ├──► Fournisseur NVIDIA ──► API du site nvidia.com  (carte graphique GeForce)
        │
        └──► Fournisseur Windows Update ──► API COM Microsoft.Update.Session
                                            (chipset Intel, Realtek audio/réseau, Bluetooth…)
        │
 ┌──────▼───────┐
 │   Fenêtre    │  je coche les pilotes → point de restauration → installation → vérification
 └──────────────┘
```

| Étape | Détail technique |
|---|---|
| Inventaire | `Get-CimInstance Win32_PnPSignedDriver` : identifiants `VEN_xxxx` / `DEV_xxxx` (ex. `VEN_10DE` = NVIDIA) |
| NVIDIA | `lookupValueSearch.aspx` (trouve l'ID du modèle) puis `AjaxDriverService.php` (dernier pilote en JSON) |
| Versions NVIDIA | Windows affiche `32.0.16.1088`, NVIDIA affiche `610.88` → on garde les 5 derniers chiffres |
| Windows Update | Recherche `IsInstalled=0 and Type='Driver'`, puis téléchargement et installation via l'API COM |
| Sécurité | Vérification de la signature Authenticode (*NVIDIA Corporation*), point de restauration, journaux |
| Démarrage | Tâche planifiée à l'ouverture de session (+2 min) : la fenêtre ne s'ouvre **que** s'il y a des mises à jour |

## Structure du projet

```
driver/
├── DriverUpdater.ps1          # point d'entrée (fenêtre ou mode -Startup)
├── Install.ps1                # installe dans Program Files + tâche planifiée + raccourci
├── Uninstall.ps1              # désinstalle proprement
├── src/
│   ├── Common.ps1             # journaux, droits admin, conversion de versions
│   ├── Inventory.ps1          # inventaire matériel (WMI)
│   ├── Core.ps1               # orchestration recherche / installation
│   ├── Gui.ps1                # interface Windows Forms
│   ├── Loader.ps1             # charge tous les modules
│   └── Providers/
│       ├── Nvidia.ps1         # fournisseur NVIDIA
│       └── WindowsUpdate.ps1  # fournisseur Windows Update
├── tests/Common.Tests.ps1     # tests unitaires Pester
└── docs/cahier-des-charges.md
```

## Installation

1. Télécharger le dépôt (bouton **Code → Download ZIP**) et l'extraire, ou `git clone`.
2. Ouvrir PowerShell dans le dossier, puis débloquer les fichiers téléchargés :
   ```powershell
   Get-ChildItem -Recurse | Unblock-File
   ```
3. Lancer l'installation (une fenêtre UAC demande les droits administrateur) :
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1
   ```

Un raccourci **Driver** apparaît sur le Bureau, et la vérification se fera à chaque ouverture de session.

## Utilisation sans installation (test)

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\DriverUpdater.ps1
```

## Dépannage

**« l'exécution de scripts est désactivée sur ce système »** : Windows bloque les scripts par défaut.
Pour autoriser les scripts dans la fenêtre PowerShell ouverte uniquement (rien n'est modifié de façon permanente) :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Journaux

`C:\ProgramData\DriverUpdater\logs\AAAA-MM-JJ.log` (bouton **Journaux** dans la fenêtre).

## Tests

```powershell
Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser
Invoke-Pester .\tests
```

## Désinstallation

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

## Limites connues

- Les API NVIDIA utilisées ne sont pas documentées officiellement : NVIDIA peut les modifier.
  En cas de panne, Windows Update prend le relais pour la carte graphique.
- AMD et Intel n'ont pas d'API publique simple : leurs pilotes passent par Windows Update.
- Le BIOS et les firmwares ne sont pas gérés (trop risqué en automatique).
- Utiliser **Windows PowerShell 5.1** (`powershell.exe`), pas PowerShell 7 : `Checkpoint-Computer`
  (points de restauration) n'existe que dans la 5.1.

## Licence

MIT — voir [LICENSE](LICENSE).
