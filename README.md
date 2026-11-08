# Driver — mise à jour automatique des pilotes (Windows 11)

Application PowerShell avec interface graphique qui détecte les pilotes obsolètes
de mon PC et me propose de les mettre à jour. **Rien n'est installé sans ma validation.**

![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-blue) ![Windows 11](https://img.shields.io/badge/Windows-11-0078D6) [![Tests](https://github.com/saladetomateoignonchef/driver/actions/workflows/ci.yml/badge.svg)](https://github.com/saladetomateoignonchef/driver/actions/workflows/ci.yml)

## Fonctionnalités

| | |
|---|---|
| **Tableau de bord** | Une carte par composant (carte graphique, audio, réseau, chipset, Bluetooth, stockage) avec son état |
| **Mises à jour** | NVIDIA (Game Ready ou Studio) + Windows Update, installation après validation, bouton « Ignorer » |
| **Paquets manuels** | Glisser-déposer d'un ZIP constructeur : analyse des `.inf`, comparaison des versions, diagnostic clair |
| **Sauvegardes** | Le pilote actuel est sauvegardé avant chaque installation ; retour arrière en un clic ; limite de 1, 2, 3 ou 5 versions par pilote |
| **Historique** | Toutes les opérations, exportables en rapport HTML |
| **Démarrage** | Vérification à chaque démarrage, une fois par jour ou par semaine, avec notification |
| **Paramètres** | Fréquence, notification, Game Ready / Studio, thème clair / sombre, sauvegardes, mises à jour ignorées |
| **Mise à jour de Driver** | Bandeau quand une nouvelle version est publiée sur GitHub, installation en un clic |
| **Entretien** | Journaux et téléchargements de plus de 30 jours supprimés automatiquement |

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
 │  Tableau de  │
 │    bord      │  je coche les pilotes → point de restauration → installation → vérification
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

## Installer un paquet téléchargé à la main (glisser-déposer)

Pour les pilotes que l'appli ne peut pas vérifier seule (par exemple ceux de la carte mère Gigabyte,
dont le site bloque les scripts) :

1. bouton **Site carte mère** → télécharger le ZIP du pilote ;
2. **glisser le ZIP dans la fenêtre** (ou bouton **Installer un paquet…**) ;
3. l'appli extrait le ZIP, repère les `.inf` qui correspondent au matériel du PC, compare les versions
   et demande confirmation ;
4. installation avec `pnputil` (outil Windows, qui refuse les pilotes non signés).
   S'il n'y a pas de `.inf` utilisable, le `setup.exe` du paquet est lancé, uniquement s'il est signé.

> Une application administrateur ne reçoit normalement pas le glisser-déposer de l'Explorateur
> (protection UIPI de Windows). `src/DropTarget.ps1` l'autorise explicitement avec
> `ChangeWindowMessageFilterEx` pour les seuls messages de dépôt de fichiers.

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
│   ├── MainWindow.xaml        # mise en page de la fenêtre (WPF, style tableau de bord)
│   ├── Gui.ps1                # remplissage de la fenêtre et réactions aux clics
│   ├── DropTarget.ps1         # glisser-déposer en administrateur + barre de titre colorée
│   ├── ManualPackage.ps1      # analyse et installation d'un ZIP de pilotes
│   ├── Backup.ps1             # sauvegarde avant installation, limite, retour arrière
│   ├── History.ps1            # historique + rapport HTML
│   ├── SelfUpdate.ps1         # mise à jour de Driver depuis les Releases GitHub
│   ├── Notify.ps1             # notification au démarrage
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

## Publier une nouvelle version

1. Changer `$script:AppVersion` dans `src/Common.ps1` (ex. `2.1.0`).
2. Créer et pousser le tag correspondant : `git tag v2.1.0` puis `git push origin v2.1.0`.
3. GitHub Actions teste le code sur Windows ; si tout passe, le ZIP est publié dans **Releases**
   et les Driver installés proposent la mise à jour.

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
- Le BIOS et les firmwares ne sont pas gérés (trop risqué en automatique) : un BIOS déposé dans la fenêtre est reconnu et refusé.
- Le retour arrière n'est possible que pour les pilotes de constructeurs (`oemXX.inf`), pas pour ceux intégrés à Windows.
- Les sauvegardes du pilote NVIDIA sont volumineuses (environ 1 Go chacune) : d'où la limite par pilote.
- Utiliser **Windows PowerShell 5.1** (`powershell.exe`), pas PowerShell 7 : `Checkpoint-Computer`
  (points de restauration) n'existe que dans la 5.1.

## Licence

MIT — voir [LICENSE](LICENSE).
