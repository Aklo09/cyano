# Factorio Blueprint Library: user guide

The app keeps your Factorio blueprint strings, books, and planners in an ordinary folder on your Mac, exactly as you
imported them, with folders, comments, previews, and construction statistics. Everything works offline; previews and
statistics also need an asset release made from your own copy of Factorio.

## Requirements

- macOS 27 or later on Apple Silicon.
- For previews and statistics: an assembled asset release from Factorio 2.1.24 (see
  [Set up previews and statistics](#set-up-previews-and-statistics)). Everything else works without one.

## Build and open the app

From the repository root:

```sh
just app-build Release
open ".cache/xcode/Build/Products/Release/Factorio Blueprint Library.app"
```

You can copy the app to Applications. The app holds one library at a time; opening another closes the current one.

## Open or create a library

At first launch the app offers **Open Library…** (⌘O) and **New Library…** (⌥⌘N).

- **New Library…** asks for an empty folder and makes it a library.
- **Open Library…** opens a folder that is already a library. Choosing an empty folder offers to create one there.
- Recent libraries are listed below the buttons: select one and press Return. At the next launch the last library
  reopens on its own.

A library in iCloud Drive or another synchronized folder is refused: keep it in an ordinary local folder.

## Find your way around

The main window has the folder **sidebar**, the **path bar** above the item list, the **item list**, and the
**inspector** on the right.

| To | Do |
| --- | --- |
| Search all item names | ⌘F, then type; Tab moves into the results |
| Open a folder or book | Select it and press ⌘↓, or double-click |
| Go back up | ⌘↑, or click a name in the path bar |
| Sort | Click a column header, or View ▸ Sort By |
| Switch inspector tabs | ⌘1 Statistics, ⌘2 Details, ⌘3 Comments |

Books open like folders and list their entries by stored index (the `#` column). The inspector shows the selected
item's or entry's details: kind, game version, dates, size, description, and planner settings.

## Import blueprint strings

- **From the clipboard:** ⇧⌘V, or ⌘V with the item list focused.
- **From TXT files:** ⇧⌘I (File ▸ Import…), then choose files; or drag files onto the item list or a sidebar folder.

In the Import sheet, choose the folder to **Save in**, optionally a **Name**, and, for a book, whether to **Save as one
book** or **Unpack book into folders**. ⌘↩ imports. The exact bytes are kept, including line endings and trailing
whitespace, and the new item is selected.

## Copy and save strings

- **Copy String** (⌘C, or the button in the inspector) copies the selected item's exact original string, or a
  standalone string for an entry inside a book.
- **Save As TXT…** (⇧⌘E) writes it to a file. Saving inside the library folder is refused; replacing an existing file
  asks first.

## Comments

Select an item or a book entry, press ⌥⌘K (Library ▸ Add Comment), type, and press ⌘↩. To delete a comment, select it
in the Comments tab and press Delete, then confirm. In the comment field, Escape returns to the item list.

## Organize

| To | Do |
| --- | --- |
| Create a folder | ⇧⌘N (Library ▸ New Folder), type a name, Return |
| Rename | Select, press Return, type, Return |
| Move | ⌃⌘M (Library ▸ Move To…) and choose a folder, or drag onto a sidebar folder |
| Delete | ⌘⌫ and confirm: the item, with its comments, goes to the Trash; an empty folder is deleted |
| Replace an item's string | Library ▸ Replace Source…, paste or choose a file, ⌘↩ |

Renaming, moving, and replacing keep the item's identity and comments; a replaced string goes to the Trash. Entries
inside a book can't be organized on their own: these commands act on the whole book.

## Set up previews and statistics

Previews and statistics need an assembled asset release. Make one from your Factorio 2.1.24 installation with the
[asset preparation guide](development/Asset-Preparation.md#regenerate), assemble it with the
[preview guide](development/Preview.md#prepare-a-private-release), then open Settings (⌘,) and click **Choose…**.
The app verifies the release and remembers it. Keep the release outside the repository's `.cache/` for everyday use.

## Previews

The inspector renders the selected blueprint or planner on demand (books have no preview). To compare, open items in
their own windows with ⌘Y or Space; several can be open at once, and opening one again brings its window forward.

| In a preview | Do |
| --- | --- |
| Zoom | ⌘+ and ⌘−, ⌘0 Actual Size, ⌘9 Zoom to Fit; pinch or scroll |
| Pan | Drag, or the arrow keys |
| Background | View ▸ Background: Checkerboard, Transparent, or Solid Color… |
| Try a failed render again | ⌘R |

One preview renders at a time; others say they are waiting. Previews are cached, so an item you have viewed appears
at once next time. Preview windows follow their item: a rename changes the title, a replaced string re-renders, and a
deleted item says so. Closing the library closes its preview windows; they are not reopened at the next launch.
Alt-mode details are drawn as in the game, including inserter pickup and drop markers.

## Statistics

The Statistics tab (⌘1) lists a blueprint's entity and tile counts, footprint, and the items needed to build it.
Books and planners have no statistics. Without an asset release, the tab says what it needs.

## When something goes wrong

- **"…is in use":** another app or an `fb-native` command has the library open. Close it and choose Try Again.
- **A change was interrupted:** if the app or the CLI stopped during a change, the library completes it when opened
  and says so. If a change can't be completed, the window shows **Recover**; if recovery still fails, it shows the
  `fb-native recover … --quarantine <id>` command to set the change aside.
- **"N items can't be used":** the sidebar footer lists files the library can't read; nothing is changed.

Every message says what happened and what you can do; the error code is in the details.

## Use the command line alongside

The `fb-native` CLI works on the same library (see the [CLI guide](development/Library-CLI.md)), but only one of them
can hold it at a time: close the library in the app (⇧⌘W) before running a CLI command that changes it. Cache
cleanup, staging cleanup, quarantine, and usage reports are CLI-only.

## Not available yet

Thumbnail grids, copying or saving a preview image, and icons for Factorio rich-text tags in names (tags are removed
from displayed names) are planned for later milestones. List rows show each item's kind symbol, not a thumbnail.

All menu commands and shortcuts are listed in the [screen specs](specs/Native-App-Screens.md#menus-and-shortcuts).
