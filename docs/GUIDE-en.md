# Driver: user guide

🇫🇷 [Version française](GUIDE-fr.md)

Driver keeps your Windows 11 PC's drivers up to date: the NVIDIA graphics card through NVIDIA's official site, and everything else through Windows Update. **Nothing is installed without your approval**, and every replaced driver is backed up so you can roll back.

## Contents

1. [Install Driver](#1-install-driver)
2. [First launch](#2-first-launch)
3. [The dashboard](#3-the-dashboard)
4. [Update your drivers](#4-update-your-drivers)
5. [Install a manually downloaded driver](#5-install-a-manually-downloaded-driver)
6. [Backups and rollback](#6-backups-and-rollback)
7. [History and report](#7-history-and-report)
8. [New hardware](#8-new-hardware)
9. [Websites and links](#9-websites-and-links)
10. [Settings](#10-settings)
11. [Update Driver itself](#11-update-driver-itself)
12. [Common problems](#12-common-problems)
13. [Uninstall Driver](#13-uninstall-driver)
14. [Where is my data?](#14-where-is-my-data)

> The interface is available in English: **Settings → Language → English**. Logs always stay in French.

---

## 1. Install Driver

### Recommended: one PowerShell command

Browsers (Chrome, Edge, Firefox…) **often block installer files** such as `Installer-Driver.cmd`, because they distrust any downloaded executable file. To avoid that, install Driver straight from PowerShell, without the browser.

1. Open the **Start** menu and type `powershell`.
2. **Right-click** **Windows PowerShell** and choose **Run as administrator**.
3. When Windows asks "Do you want to allow this app to make changes?", answer **Yes**.
4. Paste this command (right-click in the window to paste) and press **Enter**:

```powershell
irm https://raw.githubusercontent.com/saladetomateoignonchef/driver/main/get-driver.ps1 | iex
```

Four steps scroll by (search, download, extraction, installation), then Driver opens by itself. A **Driver** shortcut is created on the Desktop.

> **What the command does:** `irm` (Invoke-RestMethod) downloads the install script from GitHub, and `iex` (Invoke-Expression) runs it. The script downloads the latest Driver version and installs it in `C:\Program Files\DriverUpdater`.
>
> The same command also **repairs** Driver if it no longer opens. Your settings are kept.

### Alternative: the `Installer-Driver.cmd` file

If your browser lets it through:

1. Go to the [Releases](https://github.com/saladetomateoignonchef/driver/releases/latest) page.
2. Download **`Installer-Driver.cmd`** and double-click it.
3. If Windows shows "**Windows protected your PC**" (SmartScreen), click **More info**, then **Run anyway**.

If the browser blocks the download, use the PowerShell method above.

---

## 2. First launch

On first launch, Driver scans **all your hardware** (graphics card, motherboard, audio, network, Bluetooth, USB devices…) and saves it as the **reference configuration**. A welcome message explains this.

All update searches are based on this configuration. If you add or change hardware later, see [New hardware](#8-new-hardware).

After that, Driver checks your drivers **every time the app starts**: as soon as you open it, it runs a scan and shows the available updates.

---

## 3. The dashboard

| Area | Purpose |
|---|---|
| **Left menu** | Access to every page; at the bottom, your PC name, Windows, motherboard and memory |
| **GitHub update** | Checks whether a new Driver version exists |
| **Scan** | Looks for driver updates (1 to 2 minutes) |
| **Install** | Installs the checked updates |
| **Counters** | Devices scanned, available updates, restore point on or off |
| **Cards** | One card per component; framed in orange when an update exists |
| **Dashed area** | Install a manually downloaded driver (drag and drop) |
| **Recent activity** | The day's latest actions |

---

## 4. Update your drivers

1. Click **Scan** (done automatically when Driver opens).
2. Open **Updates** in the menu: each available driver is listed with its current version → new version, and its size.
3. **Check** the ones you want, then click **Install**.
4. Confirm. Driver:
   - creates a Windows **restore point** (if the switch is ON);
   - **backs up** the current driver;
   - downloads and installs the new one, with progress (%, MB/s) at the top of the window.
5. At the end, it offers to **restart** if needed.

> While a graphics driver is being installed, **the screen may go black for a few seconds**: this is normal.

- **Ignore**: this link next to an update stops it from being offered. A newer version of the same driver will be offered again. Undo it in **Settings → Ignored updates**.
- **Game Ready or Studio** (NVIDIA): set in Settings.

---

## 5. Install a manually downloaded driver

Some drivers cannot be checked automatically (for example Gigabyte motherboard drivers, whose site blocks programs). In that case:

1. Open **Websites** in the menu and click **Open** next to your motherboard.
2. On the manufacturer's site, go to the **Drivers** tab — **not** "BIOS" — and download the driver ZIP.
3. **Drag the ZIP** into Driver's window (or click the dashed area to choose it). No need to extract it.
4. Driver finds the drivers that match **your** hardware, compares versions and asks for confirmation.

If nothing is installed, a message explains why:

| Message | Meaning |
|---|---|
| "You are already up to date" | The package has no version newer than yours |
| "This is a BIOS, not a driver" | A BIOS is not installed from Windows; Driver deliberately does not do it (risk for the PC) |
| "The identifiers do not match" | This driver is for another chip or board: check the model |
| "This package is not for this PC" | Your PC has no device of that type |
| "refused for safety" | The package's installer has no valid digital signature |

---

## 6. Backups and rollback

Before each installation, Driver **backs up the current driver**. If the new one causes trouble (a game crashing, no sound…):

1. Open **Backups**.
2. Click **Roll back to this version** next to the driver, then confirm.

Driver keeps **2 versions per driver** by default; older ones are deleted. You can choose 1, 2, 3 or 5 in Settings. An NVIDIA driver backup takes about 1 GB.

> Drivers built into Windows need no backup: only vendor drivers are backed up.

---

## 7. History and report

**History** lists every operation: date, type (installation, package, rollback), driver, version before/after and result.

**Export a report** creates an HTML page on your Desktop with the PC details, the history and the list of installed drivers. Handy to keep or to send to someone helping you.

---

## 8. New hardware

After adding or changing hardware (new graphics card, USB headset…):

1. Open **New hardware**.
2. Click **Detect new hardware**: Driver shows what was **added (+)** and **removed (−)**.
3. Click **Save as new configuration**.

Until you do, the new hardware is flagged by a yellow banner but **is not included** in searches. The last 10 configurations are kept, each with a CSV list you can open in Excel.

---

## 9. Websites and links

- **Websites**: the official driver pages for each of your components (motherboard, graphics card, processor, audio, network, peripherals). One click on **Open** takes you there.
- **Links**: all these links are **editable**. If a site has moved or is blocked, fix the link, add or delete links, then click **Save**. **Test** opens the address you typed.

A link you edited is never replaced automatically. **Restore automatic links** recomputes the others from your hardware.

---

## 10. Settings

| Setting | Options |
|---|---|
| **Automatic check** | At every startup, once a day, once a week, or never |
| **Notification** | ON: a notification at startup; OFF: the window opens directly |
| **NVIDIA driver** | *Game Ready* (games, updated often) or *Studio* (creative work, more stable) |
| **Dark mode** | Sun / moon switch |
| **Backups** | 1, 2, 3 or 5 versions kept per driver, and the space used |
| **Ignored updates** | List, with "Stop ignoring" |
| **Language** | Français or English (applied immediately) |
| **Text size** | 100 %, 115 % or 130 % |
| **Driver sources** | Turn NVIDIA and Windows Update on or off |
| **Export / import** | One file with your settings, links and configuration (to reinstall Windows or set up another PC) |
| **Driver** | Installed version, new version check, update source (GitHub repository) |

> **AMD and Intel** offer no public service to check their drivers: they go through Windows Update, and the **Websites** page opens their official tools.

---

## 11. Update Driver itself

When a new Driver version is published, a **green banner** appears at the top of the window: click **Update Driver**. Driver downloads, installs and restarts by itself.

You can also click **GitHub update** at any time:
- if there is a new version, Driver offers to install it;
- otherwise it shows "**Your software is up to date**".

---

## 12. Common problems

<details>
<summary><b>The browser blocks the installer download</b></summary>

Browsers normally do this with `.cmd` files. Use the [PowerShell command](#recommended-one-powershell-command): it does not need the browser.
</details>

<details>
<summary><b>"Windows protected your PC"</b></summary>

This is SmartScreen, which does not know Driver yet. Click **More info**, then **Run anyway**. Or use the PowerShell command.
</details>

<details>
<summary><b>"Running scripts is disabled on this system"</b></summary>

Windows blocks PowerShell scripts by default. The Driver shortcut and the install command already work around this. If you run a script by hand, first type (only valid for the open window):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
</details>

<details>
<summary><b>The PowerShell command says to open PowerShell AS ADMINISTRATOR</b></summary>

Close the window, then: Start → type `powershell` → **right-click** Windows PowerShell → **Run as administrator**. Paste the command again.
</details>

<details>
<summary><b>Driver no longer opens</b></summary>

Run the [PowerShell command](#recommended-one-powershell-command) again as administrator: it repairs the installation. Your settings and backups are kept.
</details>

<details>
<summary><b>"Driver is already running"</b></summary>

A check is running in the background (for example at PC startup). Wait 2 minutes and try again.
</details>

<details>
<summary><b>"Unable to reach GitHub" or the Driver update fails</b></summary>

GitHub sometimes has brief outages. Driver retries several times and has a fallback, but if GitHub is completely down, try again later. Error details are in the **Logs**.
</details>

<details>
<summary><b>Accents look odd in PowerShell</b></summary>

Only the Windows console display is affected; the installation is fine.
</details>

<details>
<summary><b>An installed driver causes trouble</b></summary>

Go to **Backups** and click **Roll back to this version**. As a last resort, use the Windows restore point created before the installation (Start → "Create a restore point" → **System Restore**).
</details>

<details>
<summary><b>Where are the logs?</b></summary>

**Logs** button in the menu, or the `C:\ProgramData\DriverUpdater\logs` folder (one file per day, kept 30 days). Attach today's file if you ask for help.
</details>

---

## 13. Uninstall Driver

In PowerShell **as administrator**:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\DriverUpdater\Uninstall.ps1"
```

This removes the program, the startup check, the shortcut and the data. To **keep your data** (settings, backups, history, logs), add `-KeepLogs` at the end.

---

## 14. Where is my data?

| Folder | Contents |
|---|---|
| `C:\Program Files\DriverUpdater` | The program |
| `C:\ProgramData\DriverUpdater\settings.json` | Your settings |
| `C:\ProgramData\DriverUpdater\configurations` | Hardware configurations (JSON + CSV) |
| `C:\ProgramData\DriverUpdater\backups` | Driver backups |
| `C:\ProgramData\DriverUpdater\history.json` | History |
| `C:\ProgramData\DriverUpdater\links.json` | Your links |
| `C:\ProgramData\DriverUpdater\logs` | Logs (30 days) |

These files are protected: only administrators can change them, because Driver runs installers with administrator rights.
