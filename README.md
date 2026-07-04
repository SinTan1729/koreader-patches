<!-- SPDX-FileCopyrightText: 2026 Sayantan Santra <sayantan.santra689@gmail.com> -->
<!-- SPDX-License-Identifier: GPL-3.0 -->

## KOReader Patches

This is a collection of the [KOReader](https://koreader.rocks) patches that I've written. A short description for each patch
is provided below. This is only tested on a Kobo Clara BW, but should work on all devices supporting KOReader.

1. Calibre Collections

   This automatically creates KOReader collections using a custom collection from calibre. By default, a custom column called
   `#collections` is used. But the script can easily be edited to use any other column name. It can also work with multiple
   columns if an array is provided instead. Colliding collection names are merged into one collection.

   It does not touch already existing collections. So please don't create any collections with the same name an entry in `#collections` (or
   the chosen column) manually. Collections are created/updated at startup.

   Automatically managed collections are marked with a ⚡ in the viewer. This is also customizable.

   [Read this to learn about custom columns.](https://wiki.mobileread.com/wiki/Kobo_Shelves_and_Collections#Driver_.2F_calibre_Configuration)

1. Clean Header

   This adds a clean looking header on top of KOReader reader view.

   It shows the author name on left, book title on right, and time in the middle. The time is automatically refreshed.
   Customization is possible, but I don't intend to provide much support.

   It's heavily inspired by https://github.com/joshuacant/KOReader.patches, please use his patches instead if you want more customization.
   This is simply a highly optimized version for my specific setup, along with auto refresh for the clock.

   Note: I use custom metadata columns in calibre called `#orig_title` and `#orig_author` to store the original title and author names, in
   the original script, for non-English languages that I can read. I prefer to use the English names for search etc. but original script in
   the header looks better to my eyes. Anyway, you can also use this if you want,otherwise it just falls back to the title and author
   metadata provided by KOReader.

1. Kobo Style Sleep screen banner.

   It's a modified version of [this patch](https://github.com/zenixlabs/koreader-frankenpatches-public/blob/main/2-kobo-style-sleepscreen-banner.lua).
   Please take a look there for details.

1. Progress Popup

   It's a modified version of [this patch](https://github.com/zenixlabs/koreader-frankenpatches-public/blob/main/2-cvs-receipt-frankenpatch.lua).
   Please take a look there for details. Note that it's been renamed from CVS Receipt to Progress Popup.

1. Reading Insights Popup

   It's a modified version of [this patch](https://github.com/zenixlabs/koreader-frankenpatches-public/blob/main/2-reading-insights-popup.lua).
   Please take a look there for details.

## Installation

Just copy the corresponding patch into your `<koreader>/patches/` directory.

## Bonus

The script `kobo_backup.sh` backs up the important configs from a plugged in Kobo device, which of course includes stuff related to
KOReader. Again, this is only tested on a Kobo Clara BW, but should work on all Kobo devices. You might need to edit the `SRC_DIR`
and `BK_DIR` to your liking. Also, it assumes a `*nix` OS with `rsync` installed on it.
