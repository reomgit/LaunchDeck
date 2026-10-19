# Independent final review

Reviewed the approved workflow contract, delivery reports, tracked/untracked change inventory, and implementations for persistence, packages, resolution/navigation, coordinator, execution and editor. Read-only source review; no suite repetition, native UI exercise, hardware exercise, or source modifications. Reported test/build evidence is supplied by the caller, not independently rerun here.

## [P1] Remove inherited page IDs from application order when deleting a Global folder

Location: `LaunchDeck/AppCoordinator.swift:339-341`.

Reproduction: create a Global folder with two pages; create an application profile; reorder those inherited pages in the application profile (this writes all effective page IDs into `pageOrder`, without copying the pages locally); select Global and delete the folder. The deletion calculates `removedPages` independently from each profile's local `pages`. Consequently the application's inherited page IDs remain in `pageOrder` even though the Global pages disappeared. `ProfileStore.validate` rejects these stale IDs, so the deletion and subsequent unrelated edits cannot be persisted. The UI continues with the modified in-memory configuration, while restarting restores the previously saved state. Capture removed Global page IDs before mutation and remove them from every affected application's order, along with its locally removed descendants. Add a regression covering reordered inherited pages with no local overlay.

## [P2] Preserve local bindings when renaming an overlaid application page

Location: `LaunchDeck/AppCoordinator.swift:245-250`.

Reproduction: assign a Global Home binding, create an application profile with no binding overrides, rename that application's Home page, then change the original Global binding. Renaming starts from `editorPages`, which contains merged Global and local bindings. Home already exists in every application profile, so the conditional binding clear does not run, and the entire merged binding array is written into the local page. The rename silently converts every inherited control to a local override; future Global edits no longer propagate. The same happens on any inherited page already containing one local override. Rename the existing local page's metadata while retaining its local binding array; create an empty overlay only when no local page exists. Add a regression for Home and a partial non-Home overlay.

No other substantial findings identified in this pass. Native foreground/Unicode behavior and physical 80-control LED/input behavior remain outside this review's exercised evidence.

## Resolution review

Both findings are resolved in the current source. `renamePage` now preserves the selected profile's existing local binding array (or an empty array for a new overlay). `deleteFolder` captures removed Global page IDs before any mutation and removes their union with local removed page IDs from affected page orders. These changes address the reported causes without changing manual profile independence or local overrides.

Read the added `renameDoesNotMaterializeInheritedBindings` and `deletedFolderOrdering` coordinator regressions. They directly cover Global Home propagation after application rename and persistence/reload after removing reordered inherited folder pages. The root reports both reproduced failures before the fixes and all 48 tests passing afterward; this reviewer did not rerun them.

No additional concrete issues introduced by the fixes were identified, and no important review findings remain open. Native UI, keyboard delivery, and physical device verification limitations remain as described above.
