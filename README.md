# Hytale Together — 0.3.2 preview

Unofficial local split-screen helper for 1–4 separately authenticated Hytale players on Windows 10/11 x64. Each player keeps private saves/settings and shares the installed game files. This is a community preview, not an official Hytale feature or a guaranteed stable release.

## Start here

1. Install Hytale and sign in through the official launcher. This package contains no game, accounts, or authentication credentials.
2. Extract the ZIP into a writable folder (for example Documents). Do not run it inside the ZIP or put it under Program Files.
3. Double-click **Hytale Together.exe**. Setup finds the standard game install or asks you to locate `HytaleClient.exe`. It uses SDL from your installed game; it does not modify game binaries.
4. Expand **Accounts & controllers**. Open the launcher, start an account to its main menu, then choose **Add running accounts**. Repeat for each account. Account preparation copies existing saves/mods/settings once and may take time for large worlds.
5. Select one controller icon per player. Icons are numbered; hover to see the exact device. **Assign by button** listens for the bottom face button: A on Xbox, Cross on PlayStation, B on a Nintendo-layout pad. Use one device representation per physical controller; emulator mirrors can produce two answers. The tool never disables devices system-wide.
6. Close the initial game clients. Select a monitor icon and layout, then **Start session**. Leave **Auto launch accounts (preview)** checked to select saved accounts and press Play in sequence. Keep the official launcher visible while it selects accounts. If login, an update, a branch mismatch, or a covered control needs attention, complete that step manually. Uncheck Auto launch for the previous manual workflow. Windows are arranged and controllers attached when every selected account is ready.

The numbered monitor previews show resolution and device name in their tooltips. Fill screen covers the taskbar. Resizable windows restores window borders. Three/four players use a 2×2 arrangement. Setup and diagnostic controls are collapsed after accounts have been added.

Automatic startup is experimental: the controls were inspected in the installed official launcher and the worker/state logic is tested, but a complete automatic multi-account launch has not yet been verified. It uses fresh official launches, not stored session tokens. It does not promise fully hidden/background operation; unsupported or covered account controls require a visible launcher.

## Play in one local world

Host a world on one account and enable LAN sharing. Click **Refresh local worlds**, choose the host, and **Copy join address**. In the other game use **Servers > Direct Connect** and paste the address. Refresh after the host restarts: the port changes. `127.0.0.1` is for players on this same PC; players on another PC need the host's LAN address.

Same-PC friend invites can reject local candidates and fall back to an unreliable internet relay. Direct Connect avoids that route. Input isolation does not intercept or rewrite network traffic. Retrying has been required in local testing; reliable first-attempt world joining is not yet certified.

## Controller support and limits

| Controller | Input support in this preview | Extras |
| --- | --- | --- |
| DualSense / DualSense Edge | SDL gamepad path; standard DualSense tested on the development PC | Vibration, RGB, touchpad when reported by SDL |
| DualShock 4 | SDL gamepad path; hardware verification pending | Features enabled only if reported |
| Xbox / XInput | SDL gamepad path; mixed-family assignment no longer excludes Xbox | Vibration when reported; normally no RGB/touchpad |
| Switch Pro / compatible third-party pads | Only when SDL recognizes the device as a gamepad; hardware verification pending | Driver/connection dependent |
| Raw joysticks / wheels | Not supported unless SDL already maps them as gamepads | No automatic custom mappings |

USB/Bluetooth reconnection may change device identity. Re-select the pad if its icon is missing or disconnected. Mirrored physical/virtual devices can appear separately; select only one. RGB, vibration, and touchpad controls are disabled when unsupported. Guide/PS or Share/Back-to-Escape mapping depends on what the driver exposes; Steam or another app may reserve Guide.

This adapter is deliberately restricted to **SDL 3.2.26**. Other SDL versions need an adapter update; bypassing this check is unsupported. Four-player layout/configuration is tested, but a live four-account/four-controller session is not yet verified. Multi-client gameplay can require substantial RAM/VRAM. This release retains the existing native input implementation; it does not claim to resolve every previously observed client crash.

## Data and troubleshooting

- Account data stays under `%APPDATA%\Hytale\SplitScreen\Accounts\<profile UUID>\<branch>\UserData`. Your original saves stay in place. Removing the helper does not delete those directories.
- The extracted helper folder becomes personal after use: `profiles.json`, `sessions.json`, `install-paths.json`, `studio.log`, and other state appear there. Share the original clean release ZIP, never your used folder.
- **Session tools** contains attach, pause/resume, and cancel. **Stop & restore** restores placement; restart clients before reattaching after Stop. Closing the helper leaves games running.
- If the native helper is blocked or quarantined, attachment cannot work. The package includes no exclusions, security-disabling scripts, or trusted-certificate installer. Do not disable antivirus globally. Source is supplied separately for review; the binaries are not publisher-trusted signed releases.
- Start with **Activity log** for errors. Game logs may contain account/session details; redact sensitive information before sharing them publicly.
- Authentication is owned by the official launcher. This helper cannot turn an expired/offline account session into a valid online session.

## Distribution

Portable preview; no administrator privileges, Python, Visual Studio, or terminal setup needed for normal use. Windows PowerShell 5.1/.NET Framework and an installed compatible Hytale client are required. No automatic updates or telemetry are added by this helper. Hytale itself may use its own online services and telemetry.

The accompanying source ZIP includes the application scripts, native adapter/launcher sources, third-party headers/libraries' source, and build instructions. `MANIFEST.json` lists SHA-256 hashes for release files. No public upload has been performed by preparing this package.

Keep the executable and its supporting files together in the extracted folder. The orange H icon identifies this unofficial community helper.

## Switching game branches
Close all Hytale clients. In Hytale Together choose `release` or `pre-release` in **Game branch**, then click **Switch branch**. Select the same branch in the official launcher's Settings, then start the session. Controller bindings are retained. Existing branch save folders are reused; a branch without a prepared folder starts empty. Worlds are never moved between versions automatically. A backup of the previous profile catalog is retained beside profiles.json.

If startup fails, the dialog now identifies the failing stage. Diagnostic logs are saved in `%LOCALAPPDATA%/HytaleTogether/Diagnostics`. Only a failed write check recommends another writable folder. SDL versions other than 3.2.26 still require an adapter update; this release does not bypass that compatibility check.

