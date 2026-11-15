# Native app screens

Date: 2026-11-14. Status: approved by the owner on 2026-11-14 (milestone 3, subtask A2). Amended for milestone 4
(subtask R0, 2026-11-15): names and icons, the item list, inspector header, Statistics tab, previews (warnings, image
copy and save), menus, and accessibility; approved by the owner on 2026-11-15.
Behavior and acceptance criteria: [native app spec](Native-App.md) (criterion IDs below refer to it).
Plans: [milestone 3](../planning/Milestone-3.md), [milestone 4](../planning/Milestone-4.md).

Owner decisions for this document (2026-11-14): books are browsed like folders in the item list, and the
inspector keeps the preview on top with tabs below it. Dark mode uses a darker content background and a stronger
checkerboard than the system defaults, for slightly higher contrast.

Also approved with this document: subfolders listed above items in the item list; sortable
columns; dropping TXT files opens the Import sheet instead of importing at once (a deliberate reading of IMP-2, so
the owner can choose the folder and book handling); New Folder creates "New Folder" and starts renaming it; Cancel
as the default button in destructive confirmations; 2-second confirmations for copy and export; the shortcut table;
and the exact values of the two color tokens.

## Conventions

- **Platform:** Apple Human Interface Guidelines, system controls, SF Symbols, and system text styles so text follows
  the macOS text-size settings. The only custom colors are the two tokens in Color and contrast.
- **Kinds:** each kind has one label and one symbol, used everywhere: Folder (`folder`), Blueprint
  (`square.grid.3x3`), Book (`books.vertical`), Upgrade Planner (`arrow.up.square`), Deconstruction Planner
  (`xmark.square`). Symbols always appear next to their label or inside a row that states the kind, never alone.
- **Dates:** the Mac's time zone and format, medium date with short time (for example "14 Nov 2026 at 14:03").
- **Sizes:** decimal B/KB/MB (`ByteCountFormatter`, file style); exact bytes are always visible in the inspector,
  never only in a tooltip.
- **Names:** item, folder, and entry names as stored. Rich-text tags with an icon in the release draw as that icon
  in place (ICN-5): 24 points in list rows, 20 in the sidebar and path bar, 28 in the inspector title (owner,
  2026-11-15); every other tag stays as written (ICN-6). Where icons can't be drawn (window
  titles, suggested file names, sort order) the text form is used (ICN-7). Statistics item names are the prototype
  names as text (for example `fast-inserter`), matching `fb-native statistics`, with the item's icon before them.
- **Icons:** Factorio icons come only from the configured asset release and are drawn at their own colors on every
  background; they are never the only carrier of meaning, because the kind label, name text, or VoiceOver name says
  the same. Quality badges sit in the bottom-left corner of the icon, as in the game.
- **Feedback:** every action changes something visible at once. Library operations taking longer than 0.5 s show
  an indeterminate spinner in the toolbar and disable actions that would queue behind them; renders show their own
  state (Previews below). Successful copy and export show a short confirmation at the bottom of the window for
  2 seconds, also announced to VoiceOver.
- **Messages:** a title saying what happened, a sentence saying what the owner can do, and buttons named verb +
  object ("Try Again", "Move to Trash", never "OK" for a choice). Internal codes and errno values never appear in the
  title or text; they are in a collapsed **Details** disclosure for support (spec GEN-3). Errors from a sheet appear
  inside it, next to the affected field, and keep everything entered; errors from direct actions appear as a sheet
  alert on the window. Message wording per error code is in the [appendix](#appendix-message-wording).
- **Confirmation:** every destructive action asks first; in those alerts the safe button (Cancel) is the default.

### Color and contrast

Custom tokens (owner request for slightly higher contrast in dark mode, 2026-11-14):

| Token | Light | Dark | Applies to |
| --- | --- | --- | --- |
| `contentBackground` | system `controlBackgroundColor` | `#121212` (system: `#1E1E1E`) | Item list, inspector, preview window, sheets' content areas, and the Transparent preview background |
| `checkerboardTiles` | `#FFFFFF` / `#E5E5E5` (1.26:1) | `#444444` / `#222222` (1.63:1) | Checkerboard preview background, 8-point tiles |

The sidebar keeps the system sidebar material, and selected rows keep the system selection colors (white text on
`#0059D1` in dark mode). Light mode uses system colors only.

Measured on macOS 27.2 (sRGB, WCAG 2.x formula). Light values are against the system window background
(control and text backgrounds gave the same values); dark values are against `contentBackground` `#121212`, with the
system `#1E1E1E` in parentheses.

| Color | Light | Dark | Use |
| --- | --- | --- | --- |
| `labelColor` | 14.94:1 | 13.59:1 (12.23) | All app-drawn text the owner reads, including dates, sizes, and messages |
| `secondaryLabelColor` | 3.95:1 | 6.20:1 (5.89) | Not for text (fails 4.5:1 in light mode); allowed for decorative separators |
| `tertiaryLabelColor` | 1.88:1 | 2.22:1 (2.26) | Not used |
| `linkColor` | 5.26:1 | 6.62:1 (5.89) | Text links (path bar components, "Open Settings…" links) |
| `systemRed` | 3.57:1 | 5.46:1 (4.86) | Error symbols only (non-text, needs 3:1), always beside text |
| `systemOrange`, `systemYellow` | 2.31:1, 1.51:1 | 7.47:1, 11.81:1 (system background) | Not used for text or as the only cue; warning symbols use multicolor `exclamationmark.triangle.fill` beside text |
| `controlAccentColor` | 4.02:1 | 5.14:1 (4.15) | Selection and prominent buttons as drawn by the system; not for text |

Hierarchy comes from font weight and size, not from lighter text. The rule covers text the app draws; text drawn by
system controls (table headers, disabled items, search field placeholder) keeps its system styling.
This check is partial: it covers window, control, and text backgrounds in light and dark mode. Sidebar materials,
selected rows, the material panel over previews, and Increase Contrast (the probe returned unchanged values, so it
measured nothing) must be checked on the running app in A16 (done 2026-11-15: see the
[validation](../validation/App.md#accessibility-2026-11-15)). Color is never the only signal: every state
has text, and every status symbol has a text label. The app follows Increase Contrast and Reduce Transparency
through system colors and materials.

Preview backgrounds (not text): Checkerboard uses `checkerboardTiles`; Transparent shows `contentBackground`; Solid
uses the chosen color.
State text over the preview area sits on a system material panel, never directly on the image or checkerboard.

## Window inventory

| Window | When | Notes |
| --- | --- | --- |
| Library selection | No library is open | Also hosts open failures and recovery |
| Main window | A library is open | One per app; closing it closes the library (LIFE-1) |
| Preview windows | Opened from an item or entry | Any number; close with the library |
| Settings | ⌘, | One pane: Assets |
| Sheets and alerts | Import, replace, move, confirmations, messages | Attached to their window |

## Library selection

User goal: open the library they work with, or create one.
Primary action: Open Library… (default button).
Secondary actions: New Library…; open a recent library (double-click or Return); remove a recent entry
(Delete key or context menu "Remove from Recents").

Layout: app name and symbol at the top, the two buttons, then the recent list (name, folder path below it, last
opened date). An unavailable entry shows "Unavailable" with an `exclamationmark.triangle.fill` symbol and cannot be
opened (LIB-4).

States:
- Loading: after choosing a library, its row (or the buttons area) shows "Opening…" with a spinner after 0.5 s;
  other controls are disabled until the open finishes. Recovery of a committed operation happens here silently.
- Empty: no recent libraries (LIB-1): "Open an existing library or create a new one in an empty folder." with
  both buttons.
- Error: shown in place of the recent list, with the library's folder name, until dismissed with "Back":
  - In use (LIB-8): "“Trains Library” is in use" / "Another app or an `fb-native` command has it open. Close it,
    then try again." Buttons: Try Again (default), Back.
  - Not a library and not empty (LIB-5), synchronized location (LIB-6), unsupported version or malformed controls
    (LIB-7): wording from the appendix; button Back. Nothing is written.
  - Recovery required (REC-2, REC-3, REC-4): see Recovery required below.
- Success: the selection window closes and the main window opens on the library root (LIB-3); the library moves to
  the top of the recent list.

New Library… opens a folder panel titled "Choose an Empty Folder for the New Library" with a New Folder button
(LIB-2); choosing a folder that already holds a library opens it. Open Library… opens a folder panel; choosing an empty folder asks "Create a library in “Folder”?" with
Create Library (default) and Cancel.

At launch, the last library reopens without showing this window when it is available (LIB-11).

Keyboard: focus starts on the recent list when it has entries, otherwise on Open Library…; Tab moves list →
Open Library… → New Library…; Return opens the selected recent library; ⌘O and ⌥⌘N work here too; Esc on an error
view is Back.

### Recovery required

User goal: get a library that cannot open back into a usable state.
Primary action: Recover.
Secondary actions: Copy Command for each listed operation; Try Again; Back.

Content: title "“Trains Library” needs recovery", the text "An interrupted change couldn't be completed
automatically. Recover tries again. If it still fails, set the change aside with the command below in Terminal,
then choose Try Again.", then the list of committed pending operations (kind and ID; unpublished staging and
other entries are not shown) each with a read-only, selectable
command `fb-native recover '<library path>' --quarantine <id>` and a Copy Command button.

States:
- Loading: "Recovering…" with a spinner; buttons disabled.
- Empty: not applicable (the view appears only when an operation is pending).
- Error: Recover still refused (REC-3): the view stays, with "Recovery couldn't complete the change. Nothing was
  moved or deleted." above the list.
- Success: the library opens (REC-4).

Keyboard: focus on Recover; Tab through each Copy Command, Try Again, Back; Esc is Back.

## Main window

User goal: find a blueprint and act on it.
Primary action: Import (toolbar button with label, `square.and.arrow.down`).
Secondary actions: toolbar Open in Window, Copy String, New Folder, filter field; menus and context menus for the
rest (Menus and shortcuts).

Layout, left to right:

```text
┌ Sidebar ─────┬ Path bar: Library › Trains › Rail Book ───────┬ Inspector ─────────────┐
│ ▾ Library    │ #  Name                 Kind       Updated  Size│ Header                │
│   ▸ Smelting │    ▢ Stations           Folder                   │ Preview               │
│   ▾ Trains   │    ▤ ◆◆ Rail Book       Book      12 Nov  41 KB  │ [Statistics|Details|  │
│              │    ▦ ◆ Loop             Blueprint  3 Oct   4 KB  │  Comments]            │
│ ⚠ 2 issues   │                                                  │ Tab content           │
└──────────────┴──────────────────────────────────────────────────┴───────────────────────┘
```

- **Sidebar:** the folder tree, starting at "Library" (the root), including empty folders (BRW-1). Books do not
  appear in the sidebar. A footer row "2 items can't be used" with a warning symbol appears when the listing has
  issues and opens the Listing issues sheet (BRW-8). Collapsible with the system sidebar command (⌃⌘S).
- **Path bar:** above the item list; every component is a link to that folder or book (BRW-4, BOOK-3).
- **Item list:** a table showing the current folder's subfolders first, then its items, sorted by name (column
  headers sort). Folder columns: Name (kind symbol, then the entry icons, then the name; ICN-1, ICN-3), Kind,
  Updated, Size. In the sketch, ▢ ▤ ▦ are kind symbols and ◆ entry icons. Entry icons are drawn 24 points high
  (scaled with the text size) in stored order with 2-point gaps; up to four, so names keep most of the column. Every
  row is tall enough for them, with icons or without, so rows stay one height, and the kind symbol takes the same
  24-point square (owner, 2026-11-15). Thumbnails are not shown
  (BRW-9, milestone 4 decision S1). Inside a book, columns are # (stored index), Name, Kind (BOOK-1, BOOK-2).
  Double-click or ⌘↓ opens a folder or book; ⌘↑ goes to the enclosing folder or book.
- **Inspector:** described below; toggled with the system inspector command (⌃⌘I) and resizable.
- **Banners:** one line across the top of the item list for window-wide conditions (below).

States:
- Loading: opening the main window shows the sidebar and list only when the listing is ready (0.24 s for 888 roots
  in a release build); if it takes longer than 0.5 s, the list area shows "Loading library…" with a spinner.
- Empty:
  - Library with no items (BRW-3): "This library is empty" / "Import a blueprint string from the clipboard or a TXT
    file." with Import… and Import from Clipboard buttons.
  - Folder with no items or subfolders (BRW-2): "“Folder” is empty" / "Import here, or drag items onto this
    folder in the sidebar." with Import….
  - Book with no entries (BOOK-4): "This book has no entries."
  - Filter with no matches (BRW-6): "No items named “text”" / "Check the spelling or clear the search." with
    Clear Search.
- Error:
  - Listing too large (BRW-10): the list area shows "This library is too large to list" / "It exceeds the
    100,000-entry or 256 MB listing limit. Close it, create a second library, and move some folders into the new
    library's `library` folder in Finder." No partial list.
  - Session blocked (REC-5): a red-symbol banner "A change failed and the library needs recovery. Recover to
    continue." with Recover; every library command is disabled until it succeeds. If Recover fails, the banner says
    "Recovery couldn't complete the change." and offers Close Library, which closes the library and shows the
    Recovery required view with its CLI commands (the CLI cannot run while the app owns the library).
  - Item failures appear as sheet alerts (appendix).
- Success: after import, move, rename, or folder creation, the affected item or folder is selected and scrolled
  into view.
- Notice: after an open that completed an interrupted change (REC-1): banner "A change was interrupted when the
  library was last used (folder move). It has been completed." with a Dismiss button; it does not return on the
  next open.

Filter: the toolbar search field (⌘F) searches item names in the whole library (BRW-5). While it has text, the path
bar reads "Search results in Library", the list adds a Folder column, and folders are not listed; Esc or the clear
button empties it and restores the previous folder and selection.

Drag and drop: dragging TXT files onto the list or a sidebar folder opens the Import sheet with those files and
that destination (IMP-2, IMP-4). Dragging items or folders onto a sidebar folder moves them (ORG-6); invalid
targets (itself, a descendant, a book) do not highlight. Entries inside a book cannot be dragged.

Keyboard: focus order sidebar → item list → inspector (preview → tab picker → tab content) → back to sidebar; the
toolbar is reachable with full keyboard access. Arrow keys move the selection; type-ahead selects by name; Return
starts renaming the selected item or folder (not entries); ⌘↓/⌘↑ open and go up; Space opens the selection in a
preview window; ⌘F focuses search; Esc in the search field clears it, otherwise cancels an in-progress rename.

### Listing issues sheet

User goal: understand which stored items are unusable and why.
Primary action: Done.
Content: "2 items can't be used" / "They are left out of the library until fixed. Close the library before
changing files in Finder." and a table of path and message (wording from the appendix for each code). Read-only.
States: Loading and Empty not applicable (opened only when issues exist); Error not applicable; Success: Done
closes it. Keyboard: focus on the table; Esc or Return is Done.

## Inspector

User goal: see what the selected item or entry is and act on it.
Primary action: depends on kind: Open in Window for blueprints and planners, Open Book for books.
Secondary actions: Copy String, Save As TXT…, and for root items Rename, Move To…, Replace Source…, Move to Trash
(BOOK-7: not for entries).

Header: the entry icons tile on the left (ICN-2: 64 × 64 points, one icon filling it or two to four in a 2 × 2 grid;
the kind symbol at the same size when there are no entry icons or no release, ICN-3), then the name (title style,
with rich-text icons), kind label with symbol, saved Factorio version (BOOK-5a, "Version unknown" when
invalid). Root items add Updated, Created, and size with exact bytes ("4.2 KB (4,213 bytes)"); entries add
"Entry 5.0 in Rail Book" instead.
The header shows all of its lines at ordinary window heights: it may take up to 45% of the inspector's height
(at most 420 points) and scrolls only when the window is shorter (owner, 2026-11-15).

Preview area (blueprints and planners), a fixed-height region under the header with the states listed under
Previews. A book shows "Books have no preview" with its entry count and an Open Book button instead.

Folders: a selected folder row (or a sidebar folder with no item selected) shows the folder name, "Folder", the
number of items and subfolders directly inside, and its description (BRW-7), with Open, Rename, Move To…, and
Delete Folder; there is no preview and no tabs.

Inside an open book with no row selected, the inspector shows that book (the root book or the nested book entry), so
its description and comments stay reachable.

Tabs (⌘1–⌘3), the same positions for every kind:

| Tab | Blueprint | Planner | Book |
| --- | --- | --- | --- |
| Statistics | Statistics tab | "Statistics don't apply to planners." (STA-5) | "Statistics don't apply to books. Open the book to see its blueprints." |
| Details | Description (BOOK-5) | Settings, mappings or filters, and description as text (BOOK-6) | Description |
| Comments | Comments tab | Comments tab | Comments tab |

States:
- Loading: decoding the selected item shows the header immediately from the listing and "Loading…" in the tab
  area after 0.5 s.
- Empty: nothing selected in the library root: "Select an item to see its details."
- Error: the item can't be read (for example it changed on disk): message from the appendix in place of the
  header, with Reload.
- Success: not applicable (read-only view).

Keyboard: Tab order header actions → preview → warnings button (when shown) → tab picker → tab content; ⌘1–⌘3 switch tabs from anywhere in the
window.

### Statistics tab

Content: entity and tile counts; footprint "83 × 43 tiles" ("Footprint incomplete, at least 202 × 79 tiles" when
incomplete, STA-3); Construction items (total), then Placement, Modules, Equipment, Other inserted, and Equipment
requests (reported, not included in the total) as lists of icon and name, quality (icon and name, only when not
normal), and count (ICN-9; without an icon, the name alone); then
Warnings, each one line worded from its code with the name and count, for example "8 × ee-infinity-loader: not in
the game data; requirements and footprint are incomplete." Empty groups are omitted.

States:
- Loading: "Calculating…" with a spinner after 0.5 s (the prototype map loads once per session, SET-5).
- Empty: an empty blueprint shows "This blueprint has no entities or tiles." with a 0 × 0 footprint.
- Error: no assets (STA-4): "Statistics need the game data from an asset release." with an Open Settings… link;
  unsuitable map (STA-6): "The selected asset release can't provide statistics." with Open Settings…; invalid data:
  appendix wording.
- Success: results as above; each value is selectable for copying.

Keyboard: Tab moves through the groups; arrow keys move within a list; ⌘C copies the selected rows as text (the
Edit menu shows Copy while this tab has focus).

### Comments tab

Content: comments for the current scope (root or this entry), oldest first, each with its local date and text with
line breaks (COM-1); below them a labeled multi-line field "New comment" and an Add Comment button (⌘↩).

States:
- Loading: not applicable (comments come with the item).
- Empty: "No comments yet." (COM-2).
- Error: Add Comment is disabled while the field is empty or whitespace (COM-4); text over 64 KiB shows "Comments
  can be up to 64 KB." under the field, with the text kept (COM-5); save failures appear under the field with the
  text kept.
- Success: the new comment appears at the end and the field clears (COM-3).

Deleting: context menu Delete Comment or Delete key on a selected comment asks "Delete this comment?" / "This can't
be undone." with Delete Comment and Cancel (default) (COM-6).

Keyboard: Tab from the list to the field to Add Comment; ⌘↩ adds; Esc in the field returns focus to the list.

## Previews

The inspector's preview area and preview windows share these states (PRV-1 to PRV-13):

| State | Shows | Actions |
| --- | --- | --- |
| No assets configured | "No asset release is configured. Previews need one." | Open Settings… |
| Asset release unusable | "The asset release can't be used: <reason>." (SET-3, SET-4) | Open Settings… |
| Waiting | "Waiting to render…" | none; closing or deselecting drops it |
| Rendering | "Rendering…" with an indeterminate spinner, shown at once | none; closing or deselecting cancels it |
| Ready | The image, fitted; "3 warnings" with a warning symbol below it when the report has warnings (WRN-1) | zoom, pan, background, Copy Image, Save Image As… (IMG-1, IMG-2), warnings list |
| Nothing to draw | "This blueprint has no entities or tiles." (PRV-12) | none |
| Failed | "The preview couldn't be rendered" and the reason in plain words (PRV-10) | Retry (⌘R) |
| Deleted (windows only) | "This item was deleted." or "This entry is no longer in the book." (PRV-11) | Close Window |

Cached previews appear without the Waiting or Rendering states (PRV-2).

Warnings (WRN-1 to WRN-3): the "N warnings" button opens a popover titled "Render warnings" with a scrolling list,
one line per distinct text with its count ("12 × <text>"), most frequent first, at most 100 lines then "and N
more". The popover has no actions; Esc closes it. The preview stays Ready. Keyboard: the button follows the preview
in the focus order; View ▸ Show Render Warnings opens the popover for the focused preview (WRN-2a).

Image copy and save (IMG-1 to IMG-6): Copy Image confirms "Copied preview image" at the bottom of the window;
Save Image As… opens a save panel named "<text form of the name>.png" (" — Entry 5.0" added for an entry). A
destination inside the library shows "Images can't be saved inside the library folder. Choose another location."
and reopens the panel; replacing an existing file asks first as Save As TXT does; a write failure says the image
wasn't saved and why. Success confirms "Saved “name.png”". Both commands are disabled outside the Ready state.

### Preview window

User goal: look at one blueprint in detail and compare it with others side by side.
Primary action: Zoom to Fit.
Secondary actions: Zoom In, Zoom Out, Actual Size, Background (Checkerboard, Transparent, Solid Color…), Retry,
Copy Image, Save Image As…, warnings.

Title: the text form of the item name (ICN-7), plus "— Entry 5.0" for an entry; it follows renames (PRV-11).
Toolbar: zoom out, zoom percentage, zoom in, Fit, Actual Size, Background pop-up, and the warnings button when the
report has warnings. Opening an entry that already has a window brings that
window forward (PRV-4). Windows are not restored at relaunch (PRV-13).

States: as in the table above; Empty is not applicable (a window always shows one entry); Success is the Ready
state.

Mouse and trackpad: scroll or pinch to zoom around the pointer, drag to pan, double-click toggles Fit and Actual
Size. Resizing keeps Fit until the owner zooms or pans (PRV-8). Changing the background keeps zoom and pan and does
not render again (PRV-8a).

Keyboard: focus starts on the image; ⌘+ and ⌘− zoom, ⌘0 Actual Size, ⌘9 Zoom to Fit, arrow keys pan by 10% of the
view (with ⌥ by one screen), ⌘C copies the image, ⌥⇧⌘E saves it, ⌘R retries a failure, ⌘W closes. Esc does
nothing.

## Sheets

### Import

User goal: save a blueprint string into the library exactly as it is.
Primary action: Import (or "Import 3 Files").
Secondary actions: Choose Files…, Cancel.

Content, top to bottom: a Source segmented control (Paste | Files); for Paste, a labeled monospaced text area
"Blueprint string" (prefilled from the clipboard when opened with Import from Clipboard or ⌘V in the list); for
Files, the file list with Choose Files…; "Name (optional)" (a label, not a placeholder; hidden for several files)
(IMP-5; also hidden for "Unpack book into folders", which names folders after the book); "Save in" folder pop-up defaulting to the current folder, or the drop target (IMP-4); and the book choice
"Save as one book" (default) / "Unpack book into folders" with the note "Each blueprint is saved as a new string;
the book's original string isn't kept unless you also save it as one book." (IMP-10).

States:
- Loading: the pasted string or chosen files are checked as soon as they change; the kind ("Book · 12 entries") or
  the problem appears under the source within 0.5 s. Importing shows a spinner on the Import button and disables the
  sheet.
- Empty: no text and no files: Import is disabled, with "Paste a blueprint string or choose TXT files." (IMP-8).
- Error, shown under the source with everything kept: "This isn't a blueprint string." or "This string exceeds the
  <limit> limit." (IMP-7); "Only books can be unpacked." when unpacking a non-book (IMP-11); destination problems
  under "Save in".
- Success: the sheet closes and the new item, or the new top folder for an unpacked book, is selected (IMP-1, IMP-9).
  A duplicate name gets a suffix without a message (IMP-6, IMP-12). With several files, if any failed, a summary
  "Imported 4 of 5 files" lists each failure with its reason and a Done button (IMP-3); with "Unpack book into
  folders", each book file is unpacked and each non-book file is listed as "Only books can be unpacked."

Keyboard: focus starts in the text area (Paste) or on Choose Files… (Files); Tab order source control → source →
name → Save in → book choice → Cancel → Import; ⌘↩ imports; Esc cancels.

### Replace source

User goal: update an item with a newer version of its string without losing its name or comments.
Primary action: Replace.
Content: the same Paste | Files source (one file), and the note "The current string goes to the Trash. Comments on
entries that no longer exist move to the item." (ORG-11).
States: Loading and Empty as Import; Error under the source with the text kept (ORG-13); Success: the sheet closes,
the inspector refreshes, and when comments moved, the confirmation says "Replaced. 2 comments moved to the item."
(ORG-12).
Keyboard: as Import; ⌘↩ replaces; Esc cancels.

### Move to

User goal: put an item or folder in another folder.
Primary action: Move.
Content: the folder tree with the current location marked; the item's own folder and, for a folder, itself and its
descendants are disabled (ORG-7).
States: Loading not applicable (tree comes from the listing); Empty: a library with no other folders shows only
Library; Error: a collision appears under the tree, "“Name” already exists in “Folder”." (ORG-7); Success: the sheet
closes and the moved item is selected in its new folder (ORG-6).
Keyboard: focus on the tree; arrows navigate; Return moves; Esc cancels.

### Rename and new folder

Rename edits the name in place in the list or sidebar (Return or Rename…). New Folder (⇧⌘N) creates "New Folder"
(or "New Folder 2", …) in the current folder and starts renaming it. Return commits, Esc cancels and restores the
old name. States: Loading: none (the field stays until the operation finishes, with the toolbar spinner after
0.5 s); Empty: an empty name cannot be committed; Error: a refused name (collision under GEN-6, or invalid, ORG-5)
keeps the field open with the typed text and shows the reason in a popover under it; Success: the renamed item stays
selected in its sorted position (ORG-2, ORG-3).

### Confirmations

| Action | Title | Text | Buttons |
| --- | --- | --- | --- |
| Move item to Trash (ORG-8) | Move “Name” to the Trash? | Its original string and metadata go to the Trash, with its comments. | Move to Trash, Cancel |
| Delete empty folder (ORG-10) | Delete the folder “Name”? | The folder is empty. | Delete Folder, Cancel |
| Replace an existing export file (EXP-4) | System save panel replace prompt | The previous file goes to the Trash. | Replace, Cancel |
| Delete comment (COM-6) | Delete this comment? | This can't be undone. | Delete Comment, Cancel |

Delete Folder on a folder that isn't empty shows "“Name” isn't empty" / "Move or delete its items first." with an
OK button, and changes nothing (ORG-10). When the Trash refuses removed originals (ORG-9), an alert says "The Trash
couldn't accept the removed files. They were kept in the library's operations-quarantine folder."

### Export

Copy String (⌘C while the item list or inspector header has focus; in text and statistics it is the ordinary
Copy) copies the selected item's exact string, or the selected entry's standalone string inside a book
(EXP-1, EXP-2), and confirms "Copied blueprint string". Save As TXT… (⇧⌘E) opens a save panel named "<name>.txt"
(EXP-3); a destination inside the library shows "Exports can't be saved inside the library folder. Choose another
location." and reopens the panel (EXP-5); a write failure says the file wasn't saved and why (EXP-6). Success
confirms "Saved “name.txt”".

## Settings

User goal: tell the app where the asset release is, so previews and statistics work.
Primary action: Choose….
Secondary actions: Clear.

Content (one pane, Assets): "Asset release" label, the folder path or "None", a status line, Choose… and Clear.
Status: "Verified: <release name>, Factorio <version>" with a checkmark, or the problem with a warning symbol.

States:
- Loading: "Verifying…" with a spinner and Cancel while a chosen folder is checked; the previous setting stays
  active until verification succeeds (SET-1).
- Empty: "No asset release is configured. Previews and statistics are unavailable; everything else works."
  (SET-6, GEN-2).
- Error: "This folder isn't a usable asset release: <reason>." and the previous setting is kept (SET-2); a release
  overlapping the open library: "The asset release can't be inside the library folder, or contain it." (SET-3);
  a configured release that is missing or changed at launch shows its problem here (SET-4).
- Success: status shows Verified; open previews and statistics refresh from the new release (SET-5a).

Keyboard: focus on Choose…; Tab to Clear; Esc or ⌘W closes the window.

## Menus and shortcuts

Every command is in the menu bar (LIFE-4); unavailable commands are disabled rather than hidden.

| Menu | Command | Shortcut |
| --- | --- | --- |
| File | New Library… | ⌥⌘N |
| File | Open Library… | ⌘O |
| File | Open Recent ▸ | |
| File | Close Library (closes the main window) | ⇧⌘W |
| File | Close Window | ⌘W |
| File | Import… | ⇧⌘I |
| File | Import from Clipboard | ⇧⌘V |
| File | Save As TXT… | ⇧⌘E |
| File | Save Image As… (preview Ready) | ⌥⇧⌘E |
| Edit | Copy String (list or inspector header focused), otherwise Copy | ⌘C |
| Edit | Copy Image (preview Ready; in a preview window it is also ⌘C) | ⌥⌘C |
| Edit | Paste (opens Import with the clipboard, list focused) | ⌘V |
| Edit | Rename… | ↩ (list focused) |
| Edit | Move to Trash / Delete Folder | ⌘⌫ |
| Edit | Find (search item names) | ⌘F |
| Library | New Folder | ⇧⌘N |
| Library | Move To… | ⌃⌘M |
| Library | Replace Source… | |
| Library | Open (folder or book) | ⌘↓ |
| Library | Enclosing Folder | ⌘↑ |
| Library | Open in Preview Window | ⌘Y, Space (list focused) |
| Library | Add Comment | ⌥⌘K |
| Library | Show Listing Issues | |
| Library | Recover | |
| View | Show/Hide Sidebar (system command) | ⌃⌘S |
| View | Show/Hide Inspector (system command) | ⌃⌘I |
| View | Statistics, Details, Comments | ⌘1, ⌘2, ⌘3 |
| View | Sort By ▸ Name, Kind, Updated, Size; Ascending, Descending (folders and search results; added in A16 as the keyboard path for the column headers) | |
| View | Zoom In, Zoom Out | ⌘+, ⌘− |
| View | Actual Size, Zoom to Fit | ⌘0, ⌘9 |
| View | Background ▸ Checkerboard, Transparent, Solid Color… | |
| View | Retry Preview | ⌘R |
| View | Show Render Warnings (preview with warnings) | |
| Window | standard items, then the main window and each preview window | |

## Accessibility

- **VoiceOver:** list rows read name, kind, updated date, and size ("Loop, blueprint, updated 3 October 2026,
  4.2 kilobytes"); book rows add "entry 3". Kind symbols are hidden from VoiceOver because the row
  states the kind. Entry icons are read after the name as "icons: iron plate, rare; copper cable"; rich-text icons
  are read in place by name (ICN-7). The warnings button reads "3 render warnings". The preview image is labeled "Preview of <name>"; state changes (waiting, rendering, ready,
  failed) are announced. Banners and confirmations are announced when they appear. Icon-only toolbar buttons have
  labels and help text (zoom, Fit, Actual Size).
- **Keyboard:** every flow above has a keyboard path; full keyboard access reaches the toolbar. The keyboard-only
  walkthrough for A16: open a library, find an item with ⌘F, open a book with ⌘↓, copy an entry with ⌘C, add a
  comment with ⌥⌘K and ⌘↩, open a preview window with Space, zoom with ⌘+ and ⌘9, import from the clipboard with
  ⇧⌘V and ⌘↩.
- **Focus:** the system focus ring is never hidden; after a sheet closes, focus returns to the control that opened
  it, or to the newly selected item. A table draws no focus ring, so keyboard focus entering the item list with
  nothing selected selects the first row (as in Finder); opening or leaving a book keeps focus in the list. In the
  comment field, Tab and Shift-Tab move focus like a text field's and Escape returns it to the list. (A16)
- **Motion:** with Reduce Motion, zoom changes from buttons and shortcuts apply without animation.
- **Text size:** system text styles only; layouts allow names to wrap or truncate with the full name in VoiceOver
  and in the inspector header.

## Appendix: message wording

Main text for each library error (the code goes in Details). Listing issues use the second table, because the
same code means something more specific there. A4 maps every case to these messages and adds
codec, preview, statistics, and asset wording in the same style.

| Code | Title | What to do |
| --- | --- | --- |
| `LIBRARY_IN_USE` | “Name” is in use | Close the other app or `fb-native` command, then try again. |
| `LIBRARY_CLOSED` | The library is closed | Open it again to continue. |
| `UNSUPPORTED_FILESYSTEM` | This location can't hold a library | Choose a folder on a local drive outside iCloud Drive and other synchronized folders. |
| `UNSAFE_PATH` | A file in the library isn't safe to use | Links, aliases, and special files aren't allowed. Close the library and fix it in Finder. |
| `INVALID_LIBRARY_FORMAT` | This folder isn't a library | Choose a library folder, or an empty folder to create one. |
| `UNSUPPORTED_VERSION` | This library needs a newer version of the app | Open it with a version that supports its format. |
| `INVALID_METADATA` | An item's information can't be read | It's left out of the library. Close the library and restore the file, or remove it in Finder. |
| `INTEGRITY_CONFLICT` | Stored files don't match what was expected | Nothing was overwritten. Close the library and check the item in Finder. |
| `RECOVERY_REQUIRED` | The library needs recovery | Choose Recover. |
| `ITEM_NOT_FOUND` | The item no longer exists | It may have been deleted. |
| `LIBRARY_LIMIT` | A library limit was reached | With too many unfinished operations, run `fb-native staging-cleanup '<library>'` (GEN-3b); otherwise the message names the limit. |
| `INVALID_INPUT` | That name or comment can't be used | Names can't be empty, start with a dot, or contain / : and similar characters. |
| `NAME_COLLISION` | “Name” already exists here | Choose a different name. Names that differ only in letter case count as the same. |
| `FOLDER_NOT_EMPTY` | The folder isn't empty | Move or delete its items first. |
| `SOURCE_CHANGED` | The item changed while its preview was rendering | Retry to render the current version. |
| `AMBIGUOUS_ID` | Two items share the same ID | Close the library and remove one of the duplicate files in Finder. |
| `FILESYSTEM_ERROR` | The disk operation failed | Check that the drive is connected and has free space, then try again. |

Listing issues (Listing issues sheet, one line per path):

| Code | Message |
| --- | --- |
| `INTEGRITY_CONFLICT` | Another name in this folder is the same when letter case is ignored, or the item's .txt and .json files don't match. |
| `INVALID_METADATA` | The item's .json file is malformed or from an unsupported version. |
| `INVALID_SOURCE` | The item's .txt file isn't a valid blueprint string. |
| `UNSAFE_PATH` | This is a link, alias, special file, or unsupported name. |
| `AMBIGUOUS_ID` | Another item has the same ID. |
| `FILESYSTEM_ERROR` | The file couldn't be read. |

Each line ends with "Close the library before fixing it in Finder."

## Open questions

None. Later changes to navigation, shortcuts, or colors are made in this document first.
