# Hytale Together

[![Release](https://img.shields.io/badge/Release-v0.3.1--preview-brightgreen.svg)](releases/HytaleTogether-0.3.1-preview-win-x64.zip)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011%20x64-blue.svg)]()
[![License](https://img.shields.io/badge/License-MIT-orange.svg)](LICENSE.txt)

**Hytale Together** is an unofficial local split-screen solution for 1–4 separately authenticated Hytale players on Windows 10/11 x64. Each player enjoys an isolated game window, private saves, dedicated controller/KBM input mapping, and automatic launcher orchestration.

---

## ⬇️ Download

Download the ready-to-run package:

📦 **[Download Hytale Together v0.3.1 Preview (Windows x64 .ZIP)](https://github.com/REXCRAFT88/Hytale-Together/releases/download/v0.3.1-preview/HytaleTogether-0.3.1-preview-win-x64.zip)**  
*(SHA-256 Checksum: `releases/HytaleTogether-0.3.1-preview-win-x64.zip.sha256`)*

Source archive:
📁 **[Download Source Package (.ZIP)](https://github.com/REXCRAFT88/Hytale-Together/releases/download/v0.3.1-preview/HytaleTogether-0.3.1-preview-source.zip)**

---

## ✨ Features

- **Up to 4 Players**: Seamless split-screen gaming on a single PC across single or multiple monitors.
- **Dedicated Controller Isolation**: Prevents background game instances from sharing controller inputs. Each controller exclusively controls its assigned game client.
- **Keyboard & Mouse (KBM) Isolation**: Play alongside controller players. One client can use Keyboard & Mouse without interference from gamepads.
- **PS5 DualSense / PS4 DualShock Touchpad Cursor**:
  - Touchpad acts as an authentic trackpad mouse.
  - Draws an on-screen hardware-accelerated cursor overlay (`HytaleSplitPrivateCursor`).
  - Configurable touchpad mouse sensitivity slider.
- **DualSense Lightbar Colors & Rumble**:
  - Custom lightbar color picker with quick swatches (Electric Cyan, Warm Amber, Neon Emerald, etc.).
  - Integrated controller vibration test button.
- **Auto Launch Accounts**:
  - Automatically selects saved player profiles in the official launcher and presses Play sequentially.
  - Fast, reliable UI Automation orchestration.
- **Screen Layouts & Multi-Monitor**:
  - Horizontal split, vertical split, 3-player, and 4-player grid layouts.
  - **Maintain 16:9 ratio**: Keeps standard widescreen proportions regardless of monitor geometry.
  - Borderless fullscreen and resizable window options.
- **Non-Invasive Architecture**:
  - Does NOT modify game executable or core asset files.
  - Uses standard SDL3 injection hooks via MinHook.

---

## 🚀 Quick Start

1. **Extract the ZIP**: Unpack `HytaleTogether-0.3.1-preview-win-x64.zip` into a writable folder (such as your `Documents` folder). *Do not run directly from inside the ZIP.*
2. **Launch**: Double-click `Hytale Together.exe`.
3. **Setup Accounts**:
   - In the **Setup & more** section, open the official launcher and start an account to its main menu.
   - Click **Add running accounts** (or use the automatic launcher setup).
   - Repeat for each player account.
4. **Assign Controllers**:
   - Each player card has an **Assign Input** button. Click it or press any button on the controller to assign it to that player.
   - If a controller is reassigned, assignments automatically swap cleanly between players.
5. **Start Session**:
   - Click the green **Play** button to begin the session.
   - Windows will automatically arrange according to your selected layout and monitor configuration!

---

## 🛠️ Building from Source

### Prerequisites
- Visual Studio 2022 (with Desktop Development with C++ and Windows 10/11 SDK)
- CMake 3.20+
- Windows PowerShell 5.1 or PowerShell 7

### Build Steps
1. **Build Native Adapter & Host**:
   ```powershell
   cd native
   ./Build.ps1 -ClientDirectory "C:\Path\To\Hytale\Client"
   ```
2. **Build C# Launcher**:
   ```powershell
   cd ../launcher
   ./Build-TogetherLauncher.ps1 -AppDirectory ..
   ```
3. Run `Hytale Together.exe`.

---

## 📄 License & Third-Party Credits

- **Hytale Together** is released under the MIT License. See [LICENSE.txt](LICENSE.txt).
- **MinHook**: Copyright (c) Tsuda Kageyu. Licensed under 2-clause BSD. See [MinHook-LICENSE.txt](MinHook-LICENSE.txt).
- **SDL3**: Simple DirectMedia Layer licensed under zlib. See [SDL-LICENSE.txt](SDL-LICENSE.txt).

*Disclaimer: Hytale Together is an independent community project and is not affiliated with, endorsed by, or associated with Hypixel Studios or Riot Games.*
