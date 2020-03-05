---
title: "Origin OS Version Bypass"
subtitle: "advanced patching guide, %pub"
date: 2020-03-02
commentid: 1

permalink: /post/origin-os-bypass/advanced-patching-guide
hidden: true

breadcrumbs:
  - revlatest: /post/origin-os-bypass
  - revcustom: advanced patching guide
---

This is an advanced version of the guide to disable operating system check in Origin. It might be a bit rough, maybe I'll add some pictures later, but it should work if you carefully follow the instructions.

If this works for you, I'd appreciate if you [bought me a coffee](https://ko-fi.com/chylex).

# Prerequisites

[Ghidra](https://ghidra-sre.org).

# Setup

Open Ghidra, create a new project, drag the following files into the window and confirm:

* Origin.exe
* OriginClient.dll
* OriginClientService.exe

To edit a file, double-click it in the project window, click **Yes** when asked to analyze it, and uncheck `Windows x86 PE Exception Handling` and `Windows x86 PE RTTI Analyzer` because they take forever, and `PDB` because we don't have one. Could probably turn off some other stuff as well, but I didn't check. Then wait until the bottom right thingy finishes. Make yourself some tea or coffee or whatever you like, `OriginClient.dll` takes an eternity.

Follow the guides below. Keep in mind everything is case-sensitive, if the guide tells you to type `NOP`, don't type `nop`.

After editing a file, go to `File -> Export Program...`, open the `Format` drop-down and select `Binary`, and save the file. The file will end up with a `.bin` extension, make sure to remove it.

## OriginClient.dll

Go to `Search -> Program Text...`, type in `checkPrerequisites`, click `Next`.

In the `Decompile` panel, there are 3 occurrences of `if (bVar2 != false) {`. If you click the `if`, the `Listing` panel will scroll down and highlight a line labeled `JZ LAB_...`.

Do this for the first occurrence, then right-click the `JZ LAB_...` line, click `Patch Instruction...`, replace `JZ` with `JMP`, wait, then select `e9 ** ** ** **` (asterisks don't matter, only the beginning). Next line will become `?? 00h`, so do this again but replace `??` with `NOP` and select `90`.

Afterwards, the first 2 occurrences will disappear (sometimes this might take a short while, watch the progress bar in bottom right after patching an instruction). Repeat the same process for the third occurence.

Now that you know the workflow, the rest of the guide will be more brief.

## Origin.exe

### Part 1

Go to `Search -> Program Text...`, check `All Fields`, type in `Problem found in executable`, click `Search All`. Double-click on the first line with `FUN_...` under `Namespace` and close the search results.

In the `Decompile` panel, click the `if` in `if (cVar3 == '\0') {` right above the found text, and patch `JNZ LAB_...` to `JMP` (`eb **`).

Above, click the `if` in `if (hObject == (undefined4 *)0x0) {`, and patch `JNZ LAB_...` to `JMP` (`eb **`).

A little further below, click the `if` in `if (cVar4 == '\0') {`, and patch `JNZ LAB_...` to `JMP` (`e9 ** ** ** **`), then patch `?? 00h` to `NOP` (`90`).

Finally, click the `if` in `if (cVar3 == '\0') {` that just appeared, and patch `JNZ LAB_...` to `JMP` (`eb **`).

### Part 2

Go to `Search -> Program Text...`, check `Program Database` and `Instruction Operands`, type in `WinVerifyTrust`, click `Next`.

In the `Decompile` panel, click the `if` in `if (LVar1 < -0x7ff4feee) {`, and patch `JG LAB_...` to `JMP` (`e9 ** ** ** **`). Then patch the `?? 00h` to `NOP` (`90`).

In the `Decompile` panel, click the `if` in `if (LVar1 == 0) {`, and patch `JZ LAB_...` to `JMP` (`eb ** `).

## OriginClientService.exe

Go to `Seach -> Program Text...`, check `Instruction Operands`, type in `isValidEACertificate`, click `Search All`. The opened panel has 4 occurrences, 2 of which should contain `validateCaller` or `executeProcess`.

For each of the 2 occurrences, first click it. This will highlight a line in the `Listing` panel that contains `CALL Origin::...`, a few lines below there should be a `JNZ LAB_...`, patch it to `JMP` - one of them will be short (`eb **`), the other one will be long (`e9 ** ** ** **`) and will require patching `?? 00h` with `NOP` (`90`) again.
