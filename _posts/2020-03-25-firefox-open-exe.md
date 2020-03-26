---
title: "Open Executables Without Saving In Firefox 57+"
subtitle: "%pub"
date: 2020-03-25
commentid: 3
---

Since Firefox 57, extensions such as OpenDownload² can no longer modify the Download dialog, removing the option to run executables without manually saving them first. Here is a PowerShell script to fix that.

### Before

![Download dialog before the patch.](/assets/img/firefox-open-exe/before.png)

### After

![Download dialog after the patch.](/assets/img/firefox-open-exe/after.png)

# How to Use

1. [Download the script](/assets/download/firefox-open-exe/FirefoxOpenExePatch.ps1)
2. Close Firefox
3. Open PowerShell in the folder with the downloaded script
    - If you installed Firefox into a protected location (such as Program Files), you will need to run PowerShell as Administrator, and navigate to the script folder using `cd "<folder>"`
    - Otherwise, you can simply open the script folder in Windows Explorer and type `powershell` into the address bar
4. Type `.\FirefoxOpenExePatch.ps1 "<firefox-folder>"` into PowerShell and press Enter
    - For ex.: `.\FirefoxOpenExePatch.ps1 "C:\Program Files\Mozilla Firefox"`
5. After the patching completes, make sure it says `Applied 4 patches`
    - If it's fewer, it may still work but not 100%
    - If it's more, it probably touched something it shouldn't have
6. Delete `compatibility.ini` from your Firefox profile folder to regenerate the download dialog
    - For non-portable installs, your profile is in `%APPDATA%\Mozilla\Firefox\Profiles\<profile-id>`
    - For portable installs, your profile is in `<installation-folder>\Data\profile`
7. Repeat when Firefox updates

If you cannot run PowerShell scripts, follow [this guide](https://social.technet.microsoft.com/wiki/contents/articles/38496.unblock-downloaded-powershell-scripts.aspx).

If you see an error message, read it, most times you should be able to figure out what's wrong. If the patch succeeds but Firefox doesn't work, revert the patch by renaming `omni.ja.old` to `omni.ja`.

Please let me know in the comments if a Firefox update breaks the patch. If this guide works for you, I'd appreciate if you [bought me a coffee](https://ko-fi.com/chylex).

# How it Works

In the Firefox installation folder, `omni.ja` is a ZIP file with no compression. The archive contains `modules\HelperAppDlg.jsm` (or `components/nsHelperAppDlg.js` in older versions) with JavaScript logic for the download dialog.

The patch does 2 things:

1. It replaces `this.mLauncher.targetFileIsExecutable` with `false` in 3 places to make executables pretend they are normal files, so they will not trigger the "simple" download dialog.
2. It modifies a condition that checks which option (`Open with` or `Save File`) is checked by default, to make executables default to `Open with`.

Because the ZIP file has no compression, the script treats it as a binary file and simply searches it for byte sequences to replace. The replacement bytes are written so that they don't affect the file size. Changing the ZIP file bytes *corrupts* it because the CRC checksum no longer matches the contents, but Firefox doesn't care.
