---
title: "Origin OS Version Bypass"
subtitle: "revision 2, %pub"
date: 2019-11-14
commentid: 1

permalink: /post/origin-os-bypass/revision-2
hidden: true

breadcrumbs:
  - revlatest: /post/origin-os-bypass
  - revcurrent: 2
---

This guide shows how to download and run Need for Speed Heat on Windows 7 or Windows 8, by patching Origin to disable its operating system check.

If this works for you, I'd appreciate if you [bought me a coffee](https://ko-fi.com/chylex).

# Prerequisites

Get a hex editor that can handle big files. I'm using [HxD](https://mh-nexus.de/en/hxd/) (Portable).

**Check your Origin.exe version:**
- For **10.5.55.33574**, this revision should work
- For **10.5.52.32372**, see [previous revision]({% post_url 2019-11-12-origin-os-bypass-r1 %})

Alternatively, you can try the [advanced patching guide]({% post_url 2020-03-06-origin-os-bypass-advanced-patching-guide %}) that should work on any version, but the advanced guide is a lot more involved and there be dragons.

I recommend switching Origin to offline mode, because if the game needs an update, you will have to do this again.

# Edits

Open each file in the hex editor. Go to each offset, make sure the sequence of bytes at that offset is the same as what's in the **Old** column, change it to what's in the **New** column.

In HxD, use *Search - Go to...* (Ctrl+G), paste in the offset, click OK, **make sure your cursor is inside the hex section and not the decoded text section**, and type in the new hex values.

## Origin.exe

| Offset | Old               | New               |
|--------|-------------------|-------------------|
| 1F006  | 75                | EB                |
| 1F077  | 75                | EB                |
| 1F0E1  | 0F 85 92 00 00 00 | E9 93 00 00 00 90 |
| 1F130  | 75                | EB                |
| 28E40  | 0F 8F 07 01 00 00 | E9 08 01 00 00 90 |
| 28F4F  | 74                | EB                |
| 2915C  | 74                | EB                |

## OriginClient.dll

| Offset | Old               | New               |
|--------|-------------------|-------------------|
| 3C81F5 | 0F 84 37 01 00 00 | E9 38 01 00 00 90 |
| 3C837A | 0F 84 4B 01 00 00 | E9 4C 01 00 00 90 |

## OriginClientService.exe

| Offset | Old                  | New                  |
|--------|----------------------|----------------------|
| 2E314  | 75                   | EB                   |
| 33436  | 75 4D 68 4C 03 00 00 | E9 7C 03 00 00 90 90 |
| 334B2  | 75                   | EB                   |
| 3360F  | 0F 84 46 01 00 00    | E9 47 01 00 00 90    |
| 3371F  | 0F 84 79 00 00 00    | E9 7A 00 00 00 90    |

# Explanation

If you want a very brief explanation, hex `74`/`75` are conditional jumps, and we turn them into `EB`, which is a forced jump, to skip over a bunch of code. Sequences `0F 8x` are generally variants of jumps that can jump further, and their forced jump equivalent is `E9` which takes 1 byte less, so whatever follows after the jump destination (4 bytes) is turned into `90`, a no-op instruction that does nothing but prevents shifting everything by a byte.

In all cases, we skip over code that either acts upon the result of an OS version check, or the result of a signature check. Most of it is signature checks that *throw a fit* (technical term) when one of the exe/dll files is modified. It's so effective that you need to modify 3 files instead of 1 to get this working (although it's probably a good idea to be validating exe files because parts of Origin run with SYSTEM level privileges, more privileged than your *poweruser* administrator account).

HxD also has a handy Data Inspector panel where, if you select one or more bytes, you can see the x86-64 instruction it represents.
