# Driver : guide d'utilisation

🇬🇧 [English version](GUIDE-en.md)

Driver garde à jour les pilotes de ton PC Windows 11 : la carte graphique NVIDIA via le site officiel, et tout le reste via Windows Update. **Rien ne s'installe sans ta validation**, et chaque pilote remplacé est sauvegardé pour pouvoir revenir en arrière.

## Sommaire

1. [Installer Driver](#1-installer-driver)
2. [Premier lancement](#2-premier-lancement)
3. [Le tableau de bord](#3-le-tableau-de-bord)
4. [Mettre à jour les pilotes](#4-mettre-à-jour-les-pilotes)
5. [Installer un pilote téléchargé à la main](#5-installer-un-pilote-téléchargé-à-la-main)
6. [Sauvegardes et retour arrière](#6-sauvegardes-et-retour-arrière)
7. [Historique et rapport](#7-historique-et-rapport)
8. [Nouveau matériel](#8-nouveau-matériel)
9. [Sites et liens](#9-sites-et-liens)
10. [Paramètres](#10-paramètres)
11. [Mettre à jour Driver lui-même](#11-mettre-à-jour-driver-lui-même)
12. [Problèmes fréquents](#12-problèmes-fréquents)
13. [Désinstaller Driver](#13-désinstaller-driver)
14. [Où sont mes données ?](#14-où-sont-mes-données-)

---

## 1. Installer Driver

### Méthode recommandée : une commande PowerShell

Les navigateurs (Chrome, Edge, Firefox…) **bloquent souvent les fichiers d'installation** comme `Installer-Driver.cmd`, car ils se méfient de tout fichier exécutable téléchargé. Pour éviter le problème, on installe Driver directement depuis PowerShell, sans passer par le navigateur.

1. Ouvre le menu **Démarrer** et tape `powershell`.
2. Sur **Windows PowerShell**, fais un **clic droit** puis **Exécuter en tant qu'administrateur**.
3. Windows demande « Voulez-vous autoriser cette application à apporter des modifications ? » : réponds **Oui**.
4. Colle cette commande (clic droit dans la fenêtre pour coller), puis appuie sur **Entrée** :

```powershell
irm https://raw.githubusercontent.com/saladetomateoignonchef/driver/main/get-driver.ps1 | iex
```

Quatre étapes défilent (recherche, téléchargement, extraction, installation), puis Driver s'ouvre tout seul. Un raccourci **Driver** est créé sur le Bureau.

> **Ce que fait la commande :** `irm` (Invoke-RestMethod) télécharge le script d'installation depuis GitHub, et `iex` (Invoke-Expression) l'exécute. Le script télécharge la dernière version de Driver et l'installe dans `C:\Program Files\DriverUpdater`.
>
> La même commande sert aussi à **réparer** Driver s'il ne s'ouvre plus. Tes réglages sont conservés.

### Installer sans tâche planifiée (option `-NoTask`)

Par défaut, Driver crée une tâche planifiée qui cherche les mises à jour à l'ouverture de session, avec les droits administrateur. Si tu préfères **lancer la recherche toi-même** (ou si ton antivirus / ton PC d'entreprise bloque ce type de tâche), installe Driver sans elle :

```powershell
$env:DRIVER_NOTASK = '1'; irm https://raw.githubusercontent.com/saladetomateoignonchef/driver/main/get-driver.ps1 | iex
```

Avec une installation manuelle : `powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1 -NoTask`.

Ce choix est **mémorisé** : les mises à jour de Driver ne recréent pas la tâche. Tu peux changer d'avis à tout moment avec l'interrupteur **Paramètres → Rechercher les mises à jour à l'ouverture de session**.

### Autre méthode : le fichier `Installer-Driver.cmd`

Si ton navigateur le laisse passer :

1. Va sur la page [Releases](https://github.com/saladetomateoignonchef/driver/releases/latest).
2. Télécharge **`Installer-Driver.cmd`** et double-clique dessus.
3. Si Windows affiche « **Windows a protégé votre ordinateur** » (SmartScreen), clique sur **Informations complémentaires** puis **Exécuter quand même**.

Si le navigateur bloque le téléchargement, utilise la méthode PowerShell ci-dessus.

---

## 2. Premier lancement

Au premier lancement, Driver analyse **tout ton matériel** (carte graphique, carte mère, audio, réseau, Bluetooth, périphériques USB…) et l'enregistre comme **configuration de référence**. Un message de bienvenue l'explique.

Toutes les recherches de mises à jour se basent sur cette configuration. Si tu ajoutes ou changes du matériel plus tard, voir [Nouveau matériel](#8-nouveau-matériel).

Ensuite, Driver vérifie tes pilotes **à chaque démarrage de l'application** : dès que tu l'ouvres, il lance une analyse et t'affiche les mises à jour disponibles.

---

## 3. Le tableau de bord

| Zone | Rôle |
|---|---|
| **Menu de gauche** | Accès à toutes les pages ; en bas, le nom de ton PC, Windows, la carte mère et la mémoire |
| **Maj GitHub** | Vérifie s'il existe une nouvelle version de Driver |
| **Analyser** | Lance une recherche de mises à jour de pilotes (1 à 2 minutes) |
| **Installer** | Installe les mises à jour cochées |
| **Compteurs** | Nombre de périphériques analysés, de mises à jour disponibles, point de restauration activé ou non |
| **Cartes** | Une carte par composant ; encadrée en orange s'il y a une mise à jour |
| **Zone en pointillés** | Pour installer un pilote téléchargé à la main (glisser-déposer) |
| **Activité récente** | Les dernières actions de la journée |

---

## 4. Mettre à jour les pilotes

1. Clique sur **Analyser** (c'est fait automatiquement à l'ouverture).
2. Ouvre **Mises à jour** dans le menu : chaque pilote disponible y est listé avec sa version actuelle → sa nouvelle version, et sa taille.
3. **Coche** ceux que tu veux installer, puis clique sur **Installer**.
4. Confirme. Driver :
   - crée un **point de restauration** Windows (si l'interrupteur est sur ON) ;
   - **sauvegarde** le pilote actuel ;
   - télécharge et installe le nouveau, avec la progression (%, Mo/s) en haut de la fenêtre.
5. À la fin, il te propose de **redémarrer** si c'est nécessaire.

> Pendant l'installation d'un pilote de carte graphique, **l'écran peut devenir noir quelques secondes** : c'est normal.

- **Ignorer** : à droite d'une mise à jour, ce lien fait qu'elle ne te sera plus proposée. Une version plus récente du même pilote le sera de nouveau. Tu peux annuler dans **Paramètres → Mises à jour ignorées**.
- **Game Ready ou Studio** (NVIDIA) : se règle dans les Paramètres.

---

## 5. Installer un pilote téléchargé à la main

Certains pilotes ne peuvent pas être vérifiés automatiquement (par exemple ceux de la carte mère Gigabyte, dont le site bloque les programmes). Dans ce cas :

1. Ouvre **Sites** dans le menu et clique sur **Ouvrir** à côté de ta carte mère.
2. Sur le site du constructeur, va dans l'onglet **Pilotes** (Driver) — **pas** « BIOS » — et télécharge le ZIP du pilote.
3. **Glisse le ZIP** dans la fenêtre de Driver (ou clique sur la zone en pointillés pour le choisir). Pas besoin de l'extraire.
4. Driver repère les pilotes qui correspondent à **ton** matériel, compare les versions et te demande confirmation.

Si rien ne s'installe, un message t'explique pourquoi :

| Message | Signification |
|---|---|
| « Tu es déjà à jour » | Le paquet ne contient pas de version plus récente que la tienne |
| « C'est un BIOS, pas un pilote » | Le BIOS ne s'installe pas depuis Windows ; Driver ne le fait volontairement pas (risque pour le PC) |
| « Les identifiants ne correspondent pas » | Ce pilote est pour une autre puce ou une autre carte : vérifie le modèle |
| « Ce paquet n'est pas pour ce PC » | Ton PC n'a aucun périphérique de ce type |
| « refusé par sécurité » | L'installateur du paquet n'a pas de signature numérique valide |

---

## 6. Sauvegardes et retour arrière

Avant chaque installation, Driver **sauvegarde le pilote actuel**. Si le nouveau pose problème (un jeu qui plante, plus de son…) :

1. Ouvre **Sauvegardes**.
2. Clique sur **Revenir à cette version** à côté du pilote voulu, puis confirme.

Driver garde **2 versions par pilote** par défaut ; au-delà, les plus anciennes sont supprimées. Tu peux choisir 1, 2, 3 ou 5 dans les Paramètres. Une sauvegarde du pilote NVIDIA pèse environ 1 Go.

> Les pilotes intégrés à Windows n'ont pas besoin de sauvegarde : seuls les pilotes de constructeurs sont sauvegardés.

---

## 7. Historique et rapport

**Historique** liste toutes les opérations : date, type (installation, paquet, retour arrière), pilote, version avant/après et résultat.

Le bouton **Exporter un rapport** crée une page HTML sur ton Bureau avec les infos du PC, l'historique et la liste des pilotes installés. Pratique à garder ou à envoyer à quelqu'un qui t'aide.

---

## 8. Nouveau matériel

Après avoir ajouté ou changé du matériel (nouvelle carte graphique, casque USB…) :

1. Ouvre **Nouveau matériel**.
2. Clique sur **Détecter le nouveau matériel** : Driver affiche ce qui a été **ajouté (+)** et **retiré (−)**.
3. Clique sur **Enregistrer comme nouvelle configuration**.

Tant que ce n'est pas fait, le nouveau matériel est signalé par un bandeau jaune mais **n'est pas pris en compte** dans les recherches. Les 10 dernières configurations sont gardées, chacune avec une liste CSV lisible dans Excel.

---

## 9. Sites et liens

- **Sites** : les pages de pilotes officielles de chacun de tes composants (carte mère, carte graphique, processeur, audio, réseau, périphériques). Un clic sur **Ouvrir** et tu y es.
- **Liens** : tous ces liens sont **modifiables**. Si un site a changé d'adresse ou est bloqué, corrige le lien, ajoutes-en ou supprimes-en, puis clique sur **Enregistrer**. Le bouton **Tester** ouvre l'adresse saisie.

Un lien que tu as modifié n'est plus jamais remplacé automatiquement. **Rétablir les liens automatiques** recalcule les autres à partir de ton matériel.

---

## 10. Paramètres

| Réglage | Choix |
|---|---|
| **Recherche à l'ouverture de session** | Interrupteur ON/OFF ; si ON : à chaque ouverture de session, une fois par jour ou une fois par semaine |
| **Notification** | ON : une notification au démarrage ; OFF : la fenêtre s'ouvre directement |
| **Pilote NVIDIA** | *Game Ready* (jeux, mis à jour souvent) ou *Studio* (création, plus stable) |
| **Mode sombre** | Interrupteur soleil / lune |
| **Sauvegardes** | 1, 2, 3 ou 5 versions gardées par pilote, et l'espace utilisé |
| **Mises à jour ignorées** | Liste, avec « Ne plus ignorer » |
| **Langue** | Français ou English (changement immédiat) |
| **Taille du texte** | 100 %, 115 % ou 130 % |
| **Sources des pilotes** | Activer ou désactiver NVIDIA et Windows Update |
| **Exporter / importer** | Un fichier avec tes paramètres, tes liens et ta configuration (pour réinstaller Windows ou un autre PC) |
| **Driver** | Version installée, vérification des nouvelles versions, source des mises à jour (dépôt GitHub) |

> **AMD et Intel** ne proposent pas de service public pour vérifier leurs pilotes : ils passent par Windows Update, et la page **Sites** ouvre leurs outils officiels.

---

## 11. Mettre à jour Driver lui-même

Quand une nouvelle version de Driver est publiée, un **bandeau vert** apparaît en haut de la fenêtre : clique sur **Mettre à jour Driver**. Driver se télécharge, s'installe et redémarre tout seul.

Tu peux aussi cliquer sur **Maj GitHub** à tout moment :
- s'il y a une nouvelle version, Driver propose de la faire ;
- sinon, il affiche « **Votre logiciel est à jour** ».

---

## 12. Problèmes fréquents

<details>
<summary><b>Le navigateur bloque le téléchargement de l'installateur</b></summary>

C'est un comportement normal des navigateurs avec les fichiers `.cmd`. Utilise la [commande PowerShell](#méthode-recommandée--une-commande-powershell) : elle n'a pas besoin du navigateur.
</details>

<details>
<summary><b>« Windows a protégé votre ordinateur »</b></summary>

C'est SmartScreen, qui ne connaît pas encore Driver. Clique sur **Informations complémentaires** puis **Exécuter quand même**. Ou utilise la commande PowerShell.
</details>

<details>
<summary><b>« L'exécution de scripts est désactivée sur ce système »</b></summary>

Windows bloque les scripts PowerShell par défaut. Le raccourci Driver et la commande d'installation contournent déjà ce blocage. Si tu lances un script à la main, tape d'abord (valable seulement pour la fenêtre ouverte) :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
</details>

<details>
<summary><b>La commande PowerShell dit « Il faut ouvrir PowerShell EN ADMINISTRATEUR »</b></summary>

Ferme la fenêtre, puis : Démarrer → tape `powershell` → **clic droit** sur Windows PowerShell → **Exécuter en tant qu'administrateur**. Recolle la commande.
</details>

<details>
<summary><b>Driver ne s'ouvre plus</b></summary>

Relance la [commande PowerShell](#méthode-recommandée--une-commande-powershell) en administrateur : elle répare l'installation. Tes réglages et sauvegardes sont conservés.
</details>

<details>
<summary><b>« Driver est déjà en cours d'exécution »</b></summary>

Une vérification tourne en arrière-plan (au démarrage du PC par exemple). Attends 2 minutes et réessaie.
</details>

<details>
<summary><b>« Impossible de joindre GitHub » ou la mise à jour de Driver échoue</b></summary>

GitHub a parfois des pannes passagères. Driver réessaie plusieurs fois et a un plan B, mais si GitHub est complètement indisponible, réessaie plus tard. Le détail de l'erreur est dans les **Logs**.
</details>

<details>
<summary><b>Les accents s'affichent bizarrement dans PowerShell (« CrÚation »)</b></summary>

C'est seulement l'affichage de la console Windows ; l'installation n'est pas affectée.
</details>

<details>
<summary><b>Un pilote installé pose problème</b></summary>

Va dans **Sauvegardes** et clique sur **Revenir à cette version**. En dernier recours, utilise le point de restauration Windows créé avant l'installation (Démarrer → « Créer un point de restauration » → **Restauration du système**).
</details>

<details>
<summary><b>Où trouver les logs ?</b></summary>

Bouton **Logs** dans le menu, ou dossier `C:\ProgramData\DriverUpdater\logs` (un fichier par jour, gardé 30 jours). Joins le fichier du jour si tu demandes de l'aide.
</details>

---

## 13. Désinstaller Driver

Dans PowerShell **en administrateur** :

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\DriverUpdater\Uninstall.ps1"
```

Cela supprime le programme, la vérification au démarrage, le raccourci et les données. Pour **garder tes données** (réglages, sauvegardes, historique, logs), ajoute `-KeepLogs` à la fin.

---

## 14. Où sont mes données ?

| Dossier | Contenu |
|---|---|
| `C:\Program Files\DriverUpdater` | Le programme |
| `C:\ProgramData\DriverUpdater\settings.json` | Tes paramètres |
| `C:\ProgramData\DriverUpdater\configurations` | Configurations matérielles (JSON + CSV) |
| `C:\ProgramData\DriverUpdater\backups` | Sauvegardes de pilotes |
| `C:\ProgramData\DriverUpdater\history.json` | Historique |
| `C:\ProgramData\DriverUpdater\links.json` | Tes liens |
| `C:\ProgramData\DriverUpdater\logs` | Logs (30 jours) |

Ces fichiers sont protégés : seuls les administrateurs peuvent les modifier, car Driver exécute des installateurs avec les droits administrateur.
