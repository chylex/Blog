---
title: "JetBrains Writerside EAP Expiration Bypass"
subtitle: "%pub"
date: 2025-04-22
commentid: 5
---

JetBrains has [discontinued the Writerside IDE](https://blog.jetbrains.com/writerside/2025/03/sunsetting-writerside-ide/) in favor of the Writerside plugin. Since the IDE has always been in the Early Access Program (EAP), its builds expire after 30 days, meaning they can’t be used indefinitely. Personally, I prefer a separate IDE for writing documentation, and the plugin has some UX annoyances I don't want to deal with, so let's bypass the EAP expiration!

I’m using Writerside 2024.3 EAP (243.22562.371), but the guide should give you enough information to adapt to changes in other versions.

# Finding the Expiration Check

![Dialog shown when opening an expired build of Writerside EAP]({{ '/assets/img/jetbrains-writerside-eap-expiration-bypass/expiration-dialog.png' | relative_url }})

Writerside, like other JetBrains IDEs, uses Java Swing. That makes it easy to find the code used to show a modal dialog — such as the one warning you that the EAP build expired. Every modal dialog spawns an event loop, which will appear in the stack trace.

Once Writerside is running and the "Writerside EAP Build Expired" dialog is visible, find the process ID (PID) and run `jstack <pid>` to dump the stack trace. You can use `jstack` from Writerside's installation directory:

```cmd
%LOCALAPPDATA%\Programs\Writerside\jbr\bin\jstack.exe 12345
```

Look for the `AWT-EventQueue-0` thread. I highlighted the important parts of the stack trace with arrows.

```stacktrace
"AWT-EventQueue-0" #72 [21032] prio=6 os_prio=0 cpu=1031.25ms elapsed=323.16s tid=0x0000019c1a2f3c40 nid=21032 waiting on condition  [0x0000009afb8fc000]
   java.lang.Thread.State: WAITING (parking)
        (unimportant lines)
        at java.awt.EventQueue.getNextEvent(java.desktop/EventQueue.java:573)
        at com.intellij.ide.IdeEventQueue.getNextEvent(IdeEventQueue.kt:466)
        at java.awt.EventDispatchThread.pumpOneEventForFilters(java.desktop/EventDispatchThread.java:194)
        at java.awt.EventDispatchThread.pumpEventsForFilter(java.desktop/EventDispatchThread.java:128)
        at java.awt.EventDispatchThread.pumpEventsForFilter(java.desktop/EventDispatchThread.java:121)
        at java.awt.WaitDispatchSupport$2.run(java.desktop/WaitDispatchSupport.java:191)
        at java.awt.WaitDispatchSupport$4.run(java.desktop/WaitDispatchSupport.java:236)
        at java.awt.WaitDispatchSupport$4.run(java.desktop/WaitDispatchSupport.java:234)
        at java.security.AccessController.executePrivileged(java.base@21.0.5/AccessController.java:778)
        at java.security.AccessController.doPrivileged(java.base@21.0.5/AccessController.java:319)
        at java.awt.WaitDispatchSupport.enter(java.desktop/WaitDispatchSupport.java:234)
    --> at java.awt.Dialog.show(java.desktop/Dialog.java:1079)
        at com.intellij.openapi.ui.impl.DialogWrapperPeerImpl$MyDialog.show(DialogWrapperPeerImpl.java:890)
        at com.intellij.openapi.ui.impl.DialogWrapperPeerImpl.show(DialogWrapperPeerImpl.java:472)
        at com.intellij.openapi.ui.DialogWrapper.doShow(DialogWrapper.java:1772)
        at com.intellij.openapi.ui.DialogWrapper.show(DialogWrapper.java:1721)
        at com.intellij.ui.messages.AlertMessagesManager.showMessageDialog(AlertMessagesManager.kt:70)
        at com.intellij.ui.messages.MessagesServiceImpl.showMessageDialog(MessagesServiceImpl.java:54)
        at com.intellij.openapi.ui.Messages.showDialog(Messages.java:274)
        at com.intellij.openapi.ui.Messages.showDialog(Messages.java:290)
        at com.intellij.openapi.ui.Messages.showDialog(Messages.java:305)
    --> at com.intellij.ide.V.a.VP.p(VP.java:320)
    --> at com.intellij.ide.V.a.VP.H(VP.java:308)
        at com.intellij.ide.V.a.VP$$Lambda/0x0000019ba1c3ab78.run(Unknown Source)
        (unimportant lines)
```

The top of the stack trace is processing an event queue spawned by `java.awt.Dialog.show`. A few lines below is the main point of interest — two methods related to the expiration check, that made the dialog appear: `com.intellij.ide.V.a.VP.p` and `com.intellij.ide.V.a.VP.H`.

# Patching the Expiration Check

To remove the expiration check, I will use [Recaf](https://github.com/Col-E/Recaf) 2.21.4.

To save you some time, the `VP` class is found inside `Writerside/lib/product.jar`. On Windows, this would be in `%LOCALAPPDATA%\Programs\Writerside\lib\`.

Open `product.jar` in Recaf and search for `com/intellij/ide/V/a/VP`.

![Screenshot of Recaf with the searched class]({{ '/assets/img/jetbrains-writerside-eap-expiration-bypass/recaf-class.png' | relative_url }})

Opening the class will attempt to decompile it. Due to heavy obfuscation, the decompiled code or line numbers from the stack trace are mostly useless, so right-click the `VP` tab and switch to the Table view.

The `p` method that calls `Messages.showDialog` can be difficult to find since its name is shared with several other methods, but the `H` method is unique.

![Screenshot of Recaf with the searched method]({{ '/assets/img/jetbrains-writerside-eap-expiration-bypass/recaf-method.png' | relative_url }})

Right-click the `H` method, select "Edit with assembler", and replace everything after the first line with `RETURN`. Press `Ctrl+S` to save, and close the editor.

```
DEFINE PRIVATE SYNTHETIC H()V
RETURN
```

> In Recaf 4, you can use the "Edit - Make no-op" option in the context menu instead.

Use "File - Export program" to export the patched `product.jar`, and replace the original file. You should now be able to use Writerside forever!

# Addendum: Fixing the Git Tool Window

The 243.22562.371 build of Writerside has an annoying bug, where the Git tool window doesn't show a diff preview depending on its location. This was caused by [commit c456622](https://github.com/JetBrains/intellij-community/commit/c4566222c3c4ca2bb08080ae3d476d65331a8ec4), and is also easy to fix using Recaf.

The buggy code is in `Writerside/lib/modules/intellij.platform.vcs.impl.jar`, in these two classes:
- `com/intellij/openapi/vcs/changes/ChangesViewManager$ChangesViewToolWindowPanel`
- `com/intellij/openapi/vcs/changes/shelf/ShelvedChangesViewManager$ShelfToolWindowPanel`

Both classes have an `updatePanelLayout` method that calls `ChangesViewContentManager.isToolWindowTabVertical`, stores the result in a local variable, and hides the preview diff if the variable is `true`.

```java
boolean isVertical = isToolWindowTabVertical(myProject, LOCAL_CHANGES);
boolean hasSplitterPreview = !isVertical;
```

Edit each `updatePanelLayout` method with assembler and search for the `isToolWindowTabVertical` call. The surrounding bytecode instructions are almost the same in both classes.

```
ALOAD this
GETFIELD com/intellij/openapi/vcs/changes/ChangesViewManager$ChangesViewToolWindowPanel.myProject ...
LDC "Local Changes"
INVOKESTATIC com/intellij/openapi/vcs/changes/ui/ChangesViewContentManager.isToolWindowTabVertical(...)Z
ISTORE isVertical
```

Replace these instructions — except for the `ISTORE` instruction — with `ICONST_0`, and save.

```
ICONST_0
ISTORE isVertical
```

This forces the `isVertical` variable to always be `false`, preventing the preview diff from being hidden.
