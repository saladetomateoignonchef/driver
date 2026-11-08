# Cahier des charges — Projet « Driver »

| | |
|---|---|
| **Auteur** | Léo Jarielle — BTS SIO option SISR |
| **Date** | 8 novembre 2026 |
| **Version** | 1.0 |

## 1. Contexte

Sur mon poste personnel sous Windows 11, je mets à jour mes pilotes à la main : je vais sur le
site de NVIDIA pour ma carte graphique, puis sur les sites d'Intel, de Realtek ou de Gigabyte
pour le reste. C'est long, je l'oublie souvent, et un pilote obsolète peut causer des problèmes
de performances, de stabilité ou de sécurité.

**Configuration matérielle relevée par inventaire WMI :**

| Composant | Matériel | Pilote installé |
|---|---|---|
| Carte graphique | NVIDIA GeForce RTX 3060 (`PCI\VEN_10DE&DEV_2504`) | 32.0.16.1088 (= 610.88) |
| Processeur | Intel Core 11ᵉ génération (Rocket Lake, famille 6 modèle 167) | — |
| Chipset / carte mère | Intel H470 (série 400), carte mère Gigabyte (`SUBSYS_xxxx1458`) | 10.1.31.2 |
| Audio | Realtek ALC897 (`HDAUDIO\...VEN_10EC&DEV_0897`) | 6.0.9373.1 |
| Réseau | Realtek PCIe GbE RTL8168 | 10.72.524.2024 |
| Bluetooth | Adaptateur USB TP-Link | 1.9.1038.3023 |
| Stockage | SSD NVMe Kingston NV2 2 To | pilote Microsoft |
| Périphériques | Casque Logitech G733, clavier/souris Corsair | pilotes Logitech / Microsoft |

## 2. Objectif

Je souhaite réaliser une application qui :

1. détecte automatiquement le matériel de mon PC et la version de chaque pilote ;
2. interroge les sources officielles (site NVIDIA, Windows Update) pour connaître les dernières versions ;
3. m'affiche dans une fenêtre graphique les pilotes qui peuvent être mis à jour ;
4. installe uniquement ceux que je valide.

## 3. Périmètre

**Inclus :**
- carte graphique NVIDIA via le site du constructeur ;
- tous les autres pilotes proposés par Windows Update (chipset, audio, réseau, Bluetooth…) ;
- lancement automatique à l'ouverture de session ;
- lancement manuel via un raccourci sur le Bureau.

**Exclus :**
- mise à jour du BIOS et des firmwares (risque de rendre le PC inutilisable) ;
- logiciels constructeurs (Logitech G HUB, Corsair iCUE…) ;
- autres systèmes que Windows 10/11 64 bits.

## 4. Besoins fonctionnels

| N° | Besoin | Priorité |
|---|---|---|
| F1 | Inventorier les périphériques et leurs versions de pilote | Indispensable |
| F2 | Trouver le dernier pilote NVIDIA pour ma carte graphique | Indispensable |
| F3 | Trouver les pilotes disponibles sur Windows Update | Indispensable |
| F4 | Afficher les mises à jour dans une fenêtre (périphérique, source, version actuelle, nouvelle version, taille) | Indispensable |
| F5 | Me laisser cocher/décocher chaque mise à jour et demander une confirmation | Indispensable |
| F6 | Créer un point de restauration avant l'installation | Important |
| F7 | Vérifier au démarrage et n'ouvrir la fenêtre que s'il y a des mises à jour | Important |
| F8 | Proposer un redémarrage si nécessaire | Important |
| F9 | Consulter les journaux depuis la fenêtre | Souhaitable |

## 5. Contraintes techniques

- **Langage :** Windows PowerShell 5.1, déjà intégré à Windows 11, donc rien à installer.
- **Interface :** Windows Forms, chargé depuis PowerShell.
- **Droits :** l'installation de pilotes nécessite les droits administrateur (élévation UAC).
- **Démarrage automatique :** tâche planifiée avec « exécuter avec les autorisations maximales ».
- **Versionnement :** dépôt Git public sur GitHub.

## 6. Contraintes de sécurité

- Je ne télécharge que depuis des sources officielles (nvidia.com, Windows Update).
- Je vérifie la signature numérique de chaque fichier téléchargé avant de l'exécuter.
- J'installe le programme dans `C:\Program Files` pour qu'un utilisateur standard ne puisse pas
  modifier un script qui s'exécute en administrateur (risque d'élévation de privilèges).
- Je ne fais aucune installation sans validation de l'utilisateur.
- Je crée un point de restauration pour pouvoir revenir en arrière.
- Je trace toutes les actions dans un journal (`C:\ProgramData\DriverUpdater\logs`).

## 7. Livrables

- Le code source sur GitHub (dépôt `driver`).
- Un script d'installation et un script de désinstallation.
- Un README (installation, utilisation, architecture).
- Des tests unitaires (Pester).
- Ce cahier des charges.

## 8. Planning prévisionnel

| Étape | Contenu | Durée |
|---|---|---|
| 1 | Cahier des charges, analyse du matériel | 1 séance |
| 2 | Inventaire WMI + fournisseur NVIDIA | 1 séance |
| 3 | Fournisseur Windows Update | 1 séance |
| 4 | Interface graphique | 1 séance |
| 5 | Tâche planifiée, installation, sécurité | 1 séance |
| 6 | Tests sur mon poste, corrections, documentation | 1 séance |

## 9. Critères de validation

- La fenêtre affiche correctement ma RTX 3060 avec sa version actuelle (610.88).
- Si un pilote plus récent existe, il apparaît dans la liste et s'installe après ma validation.
- Après installation, la version relue sur le système correspond à la version attendue.
- Au démarrage, si tout est à jour, aucune fenêtre ne s'ouvre et le journal l'indique.
