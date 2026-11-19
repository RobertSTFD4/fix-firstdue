# Fix First Due

A one-click desktop shortcut that resets First Due in Edge and Chrome on Windows. It's for when the First Due web app
hangs, spins forever or shows **RESULT_CODE_HUNG** in a normal window, while it still works in an InPrivate/Incognito window.

Built by a fire district IT shop and shared for other First Due agencies. Not affiliated with or supported by First Due.

First Due stores a lot of data in the browser so it can work offline (cookies, IndexedDB, Cache Storage, a service
worker). When that stored data gets into a bad state, the page stops loading until it's cleared. Clearing it by hand
works: in `edge://settings/content/all`, search "firstdue" and click **Remove all shown**. This tool does the same
thing so users can run it themselves.

## When to use it

- First Due spins, freezes or won't finish loading in Edge or Chrome
- "Page unresponsive" or `RESULT_CODE_HUNG`
- First Due works in InPrivate/Incognito but not in a normal window

> **Warning:** any ePCR that was saved offline and **hasn't uploaded yet is lost.** Make sure open reports are saved and
> uploaded first. The tool's first dialog says this too.

## Quick start (one PC)

1. Download this repo (**Code > Download ZIP**) and extract it.
2. Open PowerShell **as administrator** in the extracted folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\src\Install.ps1
   ```
3. A **Fix First Due** shortcut appears on the desktop and in the Start menu for every user on that PC.

To remove it, run `src\Uninstall.ps1` the same way. To deploy it to many PCs, see [Deploy with Intune](#deploy-with-intune);
any tool that can run `Install.ps1` as SYSTEM also works (NinjaOne, PDQ, GPO startup script, and so on).

## What the user sees

1. They double-click **Fix First Due** on the desktop or in the Start menu.
2. A warning dialog appears. They click **Yes** to continue or **No** to cancel.
3. Edge and Chrome close. The tool asks each window to close (so the browser saves its tabs), then force-closes
   anything still open after 15 seconds.
4. First Due's data is cleared from every Edge and Chrome profile.
5. Edge reopens to `https://sizeup.firstduesizeup.com/` and a **Done** dialog appears. The user signs in to First Due
   again.

If something couldn't be cleared, an error dialog asks them to close all browser windows and run it again. Each run
is logged to `%LOCALAPPDATA%\FirstDueFix\fix.log`.

## What gets cleared

For each profile (`Default`, `Profile N`) under `%LOCALAPPDATA%\Microsoft\Edge\User Data` and
`%LOCALAPPDATA%\Google\Chrome\User Data`:

| Store | Scope |
|---|---|
| Cookies (`Network\Cookies`) | rows whose host contains `firstdue` |
| IndexedDB | `IndexedDB\https_*firstdue*` folders |
| WebStorage buckets (Cache Storage, partitioned storage) | buckets whose storage key contains `firstdue`, plus their `QuotaManager` rows |
| Local Storage, Service Worker, Cache, Code Cache | **all sites**: these stores have no per-site split on disk |

Sign-ins to other sites are kept, because they live in cookies and only First Due's cookies are deleted. Other sites
rebuild their local storage and caches on the next visit.

Why files and not the browser itself: Chrome and Edge 136+ refuse remote debugging on the real user profile, so a
script can't drive the browser's own "clear site data". The browser has to be closed while the files are removed.

## Files

| File | Purpose |
|---|---|
| `src/Fix-FirstDue.ps1` | What the shortcut runs: dialogs, closes the browsers, calls the clear script, reopens Edge |
| `src/Clear-FirstDueSiteData.ps1` | Does the clearing. Can also run on its own |
| `src/Install.ps1` | Intune install (SYSTEM): copies to `C:\ProgramData\FirstDueFix`, creates the shortcuts |
| `src/Uninstall.ps1` | Removes the shortcuts and `C:\ProgramData\FirstDueFix` |
| `src/app.ico` | Shortcut icon. Replace it with your own if you like; keep the file name |
| `Detect.ps1` | Intune detection: the desktop shortcut exists and `version.txt` matches |
| `Upload-FixFirstDue.ps1` | Creates the Win32 app in Intune through Graph and assigns it as Required |

## Deploy with Intune

### 1. Build the package

```powershell
IntuneWinAppUtil.exe -c .\src -s Install.ps1 -o .\out -q
```

### 2. Create the app

Either upload it by hand or use the script.

**By hand** (Intune > Apps > Windows > Add > Windows app (Win32)):

| Setting | Value |
|---|---|
| Install | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Detection | Custom script `Detect.ps1`, 64-bit, no signature check |
| Assignment | Required to your device group, end-user notifications hidden |

**With the script**, connected to the target tenant:

```powershell
Connect-MgGraph -TenantId <tenant-id> -Scopes DeviceManagementApps.ReadWrite.All
.\Upload-FixFirstDue.ps1 -TenantId <tenant-id> -GroupId <device-group-id> -Publisher "Your IT Dept"
```

The script skips the upload if an app named "Fix First Due" already exists. It finishes by printing a `READBACK` line
with the publishing state and the assignments; check that the assignment shows your group.

### Updating

Edit the files in `src`, then bump the version in **both** `src/Install.ps1` (`$Version`) and `Detect.ps1`. Rebuild
the `.intunewin` and upload it as a new content version on the existing app. Devices with the old `version.txt` fail
detection and reinstall.

## Run without Intune

The clear script can run on its own, as the signed-in user, with Edge and Chrome closed:

```powershell
# See what would be removed, change nothing
powershell -ExecutionPolicy Bypass -File .\src\Clear-FirstDueSiteData.ps1 -ReportOnly

# Clear it
powershell -ExecutionPolicy Bypass -File .\src\Clear-FirstDueSiteData.ps1
```

If a browser is still open, that browser is skipped. A browser running only in the background (Edge startup boost,
Chrome background apps) has no window, so it gets stopped instead. Exit code `0` means the data was cleared or there
was nothing to clear; `1` means a browser was skipped or something failed. Output is one line, for example:
`First Due site data cleared for jdoe: Edge/Default: cookies=12 idb=3 buckets=2 shared=4`.

### Testing

| Command | Effect |
|---|---|
| `Clear-FirstDueSiteData.ps1 -UserDataRoots <dir> -SkipProcessCheck` | runs against a copy of a profile folder |
| `Fix-FirstDue.ps1 -Quiet -UserDataRoots <dir>` | runs the whole flow with no dialogs, without closing or opening browsers |

## Requirements

- Windows 10/11 with Windows PowerShell 5.1 (uses the built-in `winsqlite3.dll`; nothing to install)
- Edge and/or Chrome, Chromium-based storage layout (tested on Edge 157)

## License

MIT. See [LICENSE](LICENSE). Use at your own risk: it deletes browser data, including First Due reports that haven't
uploaded yet. "First Due" is a trademark of its owner and is used here only to describe what the tool works with.
