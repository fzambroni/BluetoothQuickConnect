# Bluetooth Quick Connect

**Bluetooth Quick Connect** is a lightweight Windows tray utility for quickly connecting, disconnecting, removing, and refreshing paired Bluetooth devices without opening the full Windows Bluetooth Settings page every time.

It is designed mainly for Bluetooth audio devices such as headphones, earbuds, headsets, and speakers. The app stays in the Windows tray and opens a small floating popup near the taskbar when you click the tray icon.

---

## Features

- **Tray-based workflow**  
  Keep the app running quietly in the Windows notification area.

- **Floating quick-connect popup**  
  Click the tray icon to open a compact Bluetooth device panel anchored near the taskbar.

- **Paired device list**  
  Lists paired, remembered, authenticated, and connected Bluetooth devices detected by Windows.

- **Connected device highlighting**  
  Connected devices are visually highlighted in the list.

- **Quick actions**
  - Connect selected device
  - Disconnect selected device
  - Remove selected paired device from Windows
  - Open Windows Bluetooth pairing page
  - Refresh device list

- **Keyboard shortcuts**
  - `Enter` — connect selected device
  - `Delete` — remove selected device
  - `F5` — refresh devices
  - `Esc` — hide popup
  - Double-click a device — toggle connect/disconnect

- **Start with Windows**  
  Enable or disable autostart from the tray menu. The app uses the current user's Windows registry startup key, so administrator rights are not required.

- **Modern dark UI**  
  Borderless popup with a custom dark palette and compact controls.

- **Update support**  
  Includes support for update checks through the bundled updater helper and local/shared update folder logic.

---

## How it works

Windows does not provide a simple public API to generically connect every possible Bluetooth device type. Because of that, Bluetooth Quick Connect uses the Windows Bluetooth API through AutoIt DLL calls and toggles common Bluetooth audio service profiles.

The app currently attempts to connect or disconnect the following Bluetooth service profiles:

| Profile | GUID | Typical use |
|---|---:|---|
| Handsfree | `{0000111e-0000-1000-8000-00805f9b34fb}` | Headsets, hands-free audio |
| Audio Sink | `{0000110b-0000-1000-8000-00805f9b34fb}` | Speakers, headphones, earbuds |
| Headset | `{00001108-0000-1000-8000-00805f9b34fb}` | Legacy headset profile |

This approach works well for many Bluetooth audio devices, but it is not a universal Bluetooth connection method.

---

## Limitations

Bluetooth Quick Connect is intentionally small and focused. A few limitations are expected:

- It works best with **Bluetooth audio devices**.
- Pure BLE devices, sensors, smart home devices, keyboards, mice, or vendor-specific devices may not connect through this method.
- Some devices may appear in the list but cannot be connected or disconnected by this app.
- Pairing new devices is handled by Windows Settings, not directly inside the app.
- Windows Bluetooth behavior can vary depending on drivers, device firmware, and the Bluetooth adapter.

If a device does not connect from this app but works from Windows Settings, the device probably does not expose one of the supported audio service profiles in a way that can be toggled through `BluetoothSetServiceState`.

---

## Requirements

### Runtime requirements

- Windows 10 or Windows 11
- A working Bluetooth adapter
- At least one paired Bluetooth device
- The compiled `BluetoothQuickConnect.exe`

### Development requirements

To build from source:

- AutoIt v3
- SciTE4AutoIt3 or AutoItWrapper
- Windows SDK is not required; the app calls native Windows DLLs directly

---

## Repository structure

Recommended repository layout:

```text
.\BluetoothQuickConnect
├── BluetoothQuickConnect.au3
├── Updater_lib2.au3
├── Updater.exe
├── FileUpdate.exe
├── bt1.ico
├── settings.ini
├── README.md
└── LICENSE
```

### Main files

| File | Purpose |
|---|---|
| `BluetoothQuickConnect.au3` | Main AutoIt source code |
| `Updater_lib2.au3` | GitHub/update helper library used by the main app |
| `Updater.exe` | Helper executable used to replace the running app during updates |
| `FileUpdate.exe` | Optional post-build/update helper, depending on your build workflow |
| `bt1.ico` | Application/tray icon |
| `settings.ini` | Local configuration file |
| `README.md` | Project documentation |
| `LICENSE` | Project license file |

---

## Installation

### Option 1 — Use a release build

1. Download the latest release package.
2. Extract the files to a local folder, for example:

   ```text
   .\BluetoothQuickConnect
   ```

3. Run:

   ```text
   .\BluetoothQuickConnect\BluetoothQuickConnect.exe
   ```

4. The Bluetooth Quick Connect icon should appear in the Windows tray.
5. Right-click the tray icon and enable **Start with Windows** if desired.

### Option 2 — Run from source

1. Install AutoIt v3.
2. Clone or download this repository.
3. Open `BluetoothQuickConnect.au3` in SciTE4AutoIt3.
4. Run the script from SciTE for testing.

Important: when running the `.au3` directly, the automatic GitHub update check is skipped by design. The update check runs only when the script is compiled as an `.exe`.

---

## Building from source

Open the project folder:

```powershell
cd .\BluetoothQuickConnect
```

Compile the main script using SciTE4AutoIt3 or AutoItWrapper.

A typical manual compile command looks like this:

```powershell
Aut2Exe.exe /in ".\BluetoothQuickConnect.au3" /out ".\BluetoothQuickConnect.exe" /x64 /icon ".\bt1.ico"
```

If you use AutoItWrapper directives, keep paths relative so the project can be built on another machine without editing local installation paths. For example:

```autoit
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_UseUpx=n
#AutoIt3Wrapper_Icon=bt1.ico
#AutoIt3Wrapper_Res_File_Add=.\Updater.exe
#AutoIt3Wrapper_Run_After=.\FileUpdate.exe
```

Make sure `Updater.exe`, `FileUpdate.exe`, and `bt1.ico` exist in the project folder before compiling.

---

## Configuration

The app reads local configuration from:

```text
.\BluetoothQuickConnect\settings.ini
```

Current update-related setting:

```ini
[Update]
path=.\updates
```

The `path` value points to the folder where a newer compiled version of the app may be placed for local/shared-folder updates.

Example local update layout:

```text
.\BluetoothQuickConnect
├── BluetoothQuickConnect.exe
├── settings.ini
└── updates
    └── BluetoothQuickConnect.exe
```

The updater compares the file version of the local running executable with the file version of the executable found in the configured update folder. If the update folder contains a newer version, the app copies it as a temporary file and launches the updater helper to replace the running executable.

---

## Update behavior

Bluetooth Quick Connect has two update-related paths in the current codebase.

### 1. GitHub update helper

When the app is running as a compiled executable, it calls:

```autoit
_CheckGitHubUpdate()
```

This function is provided by `Updater_lib2.au3`. It is skipped when running the `.au3` source directly from SciTE or development mode.

The app name used by the update helper is:

```autoit
Global $GitHubAppName = "BluetoothQuickConnect"
```

### 2. Local/shared-folder update check

The app also checks the folder configured in `settings.ini`:

```ini
[Update]
path=.\updates
```

It compares:

```text
Configured update folder executable version
vs.
Currently running executable version
```

If the update folder version is higher, the app:

1. Copies the newer executable to the local app folder as a temporary file.
2. Extracts or prepares `Updater.exe`.
3. Runs `Updater.exe` from the temporary folder.
4. Exits the current running process so the update helper can replace it.

---

## Versioning notes

The update logic depends on the executable file version, not only the version displayed in the UI.

Keep these version values aligned whenever possible:

```autoit
#AutoIt3Wrapper_Res_Fileversion=1.1.2.1
#AutoIt3Wrapper_Res_ProductVersion=1.1.2.1
Global Const $APP_VERSION = "1.1.2.1"
```

Recommended rule:

> Every release should increase `Fileversion`. The updater will not install a build with the same or lower file version.

If the update is not happening, the first thing to check is whether the available update executable really has a higher `Fileversion` than the installed executable.

---

## Troubleshooting updates

If the app is not updating, check the following items first.

### The app is being run as `.au3`

The GitHub update check is intentionally skipped when running the source file directly.

Build and run the `.exe` to test the full update flow.

### The remote or update-folder version is not higher

The updater compares executable file versions.

Example:

```text
Installed version: 1.1.2.1
Available version: 1.1.1.8
Result: no update
```

That is expected behavior because the available version is lower than the installed version.

### `settings.ini` points to the wrong update folder

Confirm this value:

```ini
[Update]
path=.\updates
```

The folder must contain a compiled executable with the same file name as the running app.

### Missing updater helper

Make sure the release package includes:

```text
.\BluetoothQuickConnect\Updater.exe
```

The running app uses this helper to replace itself during an update.

### File permissions

The app must be able to write to its own installation folder during update. If the app is installed under a protected folder such as `Program Files`, Windows may block replacement unless the updater is elevated.

For a simple portable installation, keep the app in a user-writable folder.

### Antivirus or SmartScreen interference

Because the updater replaces an executable, security tools may block or delay the operation. If updates fail silently, check Windows Security, SmartScreen, antivirus logs, or controlled folder access rules.

---

## Using the app

### Open the popup

Click the Bluetooth Quick Connect tray icon.

### Connect a device

1. Open the popup.
2. Select a paired device.
3. Click **Connect** or press `Enter`.

### Disconnect a device

1. Select a connected device.
2. Click **Disconnect**.

### Toggle a device

Double-click a device in the list.

If it is connected, the app attempts to disconnect it. If it is disconnected, the app attempts to connect it.

### Remove a device

1. Select a device.
2. Click **Remove** or press `Delete`.
3. Confirm the removal.

This removes the paired Bluetooth device from Windows.

### Pair a new device

Click **Pair** or use the tray menu option **Pair new device...**.

The app opens the Windows Bluetooth Settings page:

```text
ms-settings:bluetooth
```

### Refresh the device list

Click **Refresh** or press `F5`.

---

## Start with Windows

Right-click the tray icon and select **Start with Windows**.

The app writes a per-user startup entry under:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
```

No administrator rights are required.

To disable autostart, right-click the tray icon again and uncheck **Start with Windows**.

---

## Developer notes

### Single-instance behavior

The app checks for another running instance of the same script/executable. If a duplicate instance is detected, the older process is closed and the app restarts from the current path.

### Bluetooth device discovery

Device discovery uses Windows Bluetooth APIs exposed through `bthprops.cpl`, including:

- `BluetoothFindFirstRadio`
- `BluetoothFindFirstDevice`
- `BluetoothFindNextDevice`
- `BluetoothGetDeviceInfo`
- `BluetoothSetServiceState`
- `BluetoothRemoveDevice`

### UI behavior

The popup is created as a borderless topmost tool window and is automatically hidden when it loses focus. It is not meant to behave like a full desktop application window.

### Color rendering

The ListView uses custom draw handling and converts RGB values to Windows COLORREF/BGR format for row highlighting.

---

## Recommended release checklist

Before publishing a new release:

1. Update `Fileversion`.
2. Update `ProductVersion`.
3. Update the displayed app version, if applicable.
4. Compile the `.exe` in x64 mode.
5. Confirm `Updater.exe` is bundled.
6. Confirm `settings.ini` uses a generic or relative update path.
7. Test running the compiled `.exe`, not only the `.au3` source.
8. Test Connect, Disconnect, Refresh, Pair, Remove, and Start with Windows.
9. Confirm the release package does not contain local development paths.
10. Publish the release package and version metadata used by the updater.

---

## FAQ

### Why does my device appear but not connect?

The device may not expose one of the supported Bluetooth audio profiles. This is common with BLE-only devices, keyboards, mice, sensors, or vendor-specific hardware.

### Why does Windows Settings connect the device but this app does not?

Windows Settings can use internal Windows behavior that is not fully exposed through a simple public API. Bluetooth Quick Connect uses the available Bluetooth service-state API, which is more limited.

### Why does update not run while testing in SciTE?

The source contains a safety check that skips the GitHub update check when the script name contains `.au3`. This prevents development sessions from replacing files unexpectedly.

### Does the app require admin rights?

Normally, no. Bluetooth actions and per-user autostart do not require administrator rights. Updating may require write access to the folder where the app is installed.

### Can this manage non-audio Bluetooth devices?

It may list them, but connect/disconnect is focused on audio service profiles. Non-audio devices are not guaranteed to work.

---

## Roadmap ideas

Possible future improvements:

- Verbose updater log viewer inside the app
- Settings screen for update path and logging options
- Optional toast notifications for update results
- Better detection of unsupported device profiles
- Device pinning or favorites
- Configurable popup size and position
- Installer package
- Signed executable for smoother SmartScreen behavior

---

## License

Add a `LICENSE` file before publishing the repository. If you do not have a preference yet, the MIT License is a common choice for small open-source utilities.

---

## Author

Developed by **Fabricio Zambroni**.

---

## Disclaimer

This project is not affiliated with Microsoft. Bluetooth device behavior depends on Windows, Bluetooth drivers, hardware firmware, and supported service profiles.
