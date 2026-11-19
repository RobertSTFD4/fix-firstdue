# Fix First Due

**A free, one-click fix for First Due freezing or not loading on Windows computers.**

Built by a fire district IT shop and shared with other First Due departments. Not affiliated with or supported by First Due.

---

## Is this your problem?

Use this if First Due, in **Edge or Chrome**:

- spins forever or never finishes loading
- freezes, or shows **"Page unresponsive"** or **RESULT_CODE_HUNG**
- works in a private (InPrivate/Incognito) window but **not** in a normal window

**Why it happens:** First Due stores a lot of data inside the web browser so it can work offline. Sometimes that stored
data gets stuck, and First Due won't load until it's cleared. This tool clears it.

## What your crews do

1. Make sure any open report is **saved and uploaded**.
2. Double-click **Fix First Due** on the desktop.
3. Click **Yes**.
4. Wait a few seconds. The browser closes and reopens on First Due.
5. Sign in to First Due again. Done.

> **Important:** a report that was saved offline and **has not uploaded yet will be lost.** The tool reminds them
> before it runs.

## Put it on a computer

1. Click the green **Code** button at the top of this page, then **Download ZIP**.
2. Open the downloaded file and drag the folder inside it to the desktop.
3. Open that folder and double-click **Install.cmd**.
   - If Windows says "Windows protected your PC", click **More info** and then **Run anyway**.
   - Click **Yes** when Windows asks for administrator permission.
4. The **Fix First Due** shortcut appears on the desktop for everyone who uses that computer.

To remove it later, double-click **Uninstall.cmd** in the same folder.

**Lots of computers?** Send this page to whoever handles your IT. The section below has what they need to push it
to every computer at once.

---

## For IT staff

### What it does

The shortcut runs `Fix-FirstDue.ps1`, which:

1. shows a Yes/No warning
2. closes Edge and Chrome: it asks each window to close, so the browser saves its tabs, then force-closes anything still
   open after 15 seconds
3. runs `Clear-FirstDueSiteData.ps1` against every Edge and Chrome profile
4. reopens `https://sizeup.firstduesizeup.com/` in Edge and shows "Done", or shows an error asking the user to close
   all browser windows and try again

Each run is logged to `%LOCALAPPDATA%\FirstDueFix\fix.log`.

### What gets cleared

For each profile (`Default`, `Profile N`) under `%LOCALAPPDATA%\Microsoft\Edge\User Data` and
`%LOCALAPPDATA%\Google\Chrome\User Data`:

| Store | Scope |
|---|---|
| Cookies (`Network\Cookies`) | rows whose host contains `firstdue` |
| IndexedDB | `IndexedDB\https_*firstdue*` folders |
| WebStorage buckets (Cache Storage, partitioned storage) | buckets whose storage key contains `firstdue`, plus their `QuotaManager` rows |
| Local Storage, Service Worker, Cache, Code Cache | **all sites**: these stores have no per-site split on disk |

Sign-ins to other sites are kept, because only First Due's cookies are deleted. Other sites rebuild their local storage
and caches on the next visit.

This is the file-level equivalent of `edge://settings/content/all` > search "firstdue" > **Remove all shown**. It works
on the files because Chrome and Edge 136+ refuse remote debugging on the real user profile, so a script can't drive the
browser's own "clear site data".

### Files

| File | Purpose |
|---|---|
| `Install.cmd` / `Uninstall.cmd` | Double-click installers for a single PC; they ask for admin rights and run the `.ps1` |
| `src/Fix-FirstDue.ps1` | What the shortcut runs: dialogs, closes the browsers, calls the clear script, reopens Edge |
| `src/Clear-FirstDueSiteData.ps1` | Does the clearing. Can also run on its own |
| `src/Install.ps1` | Install (run as SYSTEM or admin): copies to `C:\ProgramData\FirstDueFix`, creates the shortcuts on the Public Desktop and the all-users Start menu |
| `src/Uninstall.ps1` | Removes the shortcuts and `C:\ProgramData\FirstDueFix` |
| `src/app.ico` | Shortcut icon. Replace it with your own if you like; keep the file name |
| `Detect.ps1` | Intune detection: the desktop shortcut exists and `version.txt` matches |
| `Upload-FixFirstDue.ps1` | Creates the Win32 app in Intune through Graph and assigns it as Required |

### Deploy with Intune

The [latest release](https://github.com/RobertSTFD4/fix-firstdue/releases/latest) has a ready-built `.intunewin` and
`Detect.ps1`. Or build the package yourself:

```powershell
IntuneWinAppUtil.exe -c .\src -s Install.ps1 -o .\out -q
```

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

Add `-IntuneWin <path>` if the package isn't at `out\Install.intunewin`. The script skips the upload if an app named
"Fix First Due" already exists. It finishes by printing a `READBACK` line; check that the assignment shows your group.

**Other tools:** anything that can run `src\Install.ps1` as SYSTEM works, such as NinjaOne, PDQ or a GPO startup
script.

### Updating

Edit the files in `src`, then bump the version in **both** `src/Install.ps1` (`$Version`) and `Detect.ps1`. Rebuild
the `.intunewin` and upload it as a new content version on the existing app. Devices with the old `version.txt` fail
detection and reinstall.

### Run the clear on its own

As the signed-in user, with Edge and Chrome closed:

```powershell
# See what would be removed, change nothing
powershell -ExecutionPolicy Bypass -File .\src\Clear-FirstDueSiteData.ps1 -ReportOnly

# Clear it
powershell -ExecutionPolicy Bypass -File .\src\Clear-FirstDueSiteData.ps1
```

If a browser is still open, that browser is skipped. A browser running only in the background (Edge startup boost,
Chrome background apps) has no window, so it gets stopped instead.

Exit code `0` means the data was cleared or there was nothing to clear; `1` means a browser was skipped or something
failed. Output is one line, for example:
`First Due site data cleared for jdoe: Edge/Default: cookies=12 idb=3 buckets=2 shared=4`.

**Testing options:**
- `Clear-FirstDueSiteData.ps1 -UserDataRoots <dir> -SkipProcessCheck` runs against a copy of a profile folder.
- `Fix-FirstDue.ps1 -Quiet -UserDataRoots <dir>` runs the whole flow with no dialogs, and doesn't close or open
  browsers.

### Requirements

- Windows 10/11 with the built-in Windows PowerShell 5.1. Nothing to install; it uses Windows' own `winsqlite3.dll`.
- Edge and/or Chrome (tested on Edge 157).

## License

MIT. See [LICENSE](LICENSE). Use at your own risk: it deletes browser data, including First Due reports that haven't
uploaded yet. "First Due" is a trademark of its owner and is used here only to describe what the tool works with.
