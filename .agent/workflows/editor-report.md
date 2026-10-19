# Editor workflow delivery

Implemented in owned files only: `LaunchDeck/EditorView.swift`, `LaunchDeck/Views/ProfileWorkflowViews.swift`, `LaunchDeck/Views/PadInspector.swift`, `LaunchDeck/Services/ArtworkComposer.swift`, `LaunchDeck/Info.plist`.

- Profile sidebar supports manual/application creation, rename, duplicate-as-manual, protected Global deletion/rename, import/export. Existing native application icons preserved.
- Runtime header shows activation/profile/page description, Auto and manual activation menu, permissions status, persistence error, dismissible execution feedback.
- Preview picker displays full folder paths. View manager creates root/nested folders and pages, renames/reorders/deletes using coordinator protection rules. Selection changes editor preview through selectPage.
- Scrollable drag palette covers shortcuts/macros/application/file/folder/website/text/disabled and all navigation actions. Native file/folder pickers construct FileTarget bookmarks before creating drag payloads.
- Inspector edits displayed effective inherited values and explains override creation. Action mutations delegate to coordinator to preserve appearance. Full RGB ColorPicker, SF Symbol entry/common symbol menu, artwork native chooser/composition/clear, and PNG preview on both inspector and physical controls.
- Mixed macros allow per-step shortcut recording, delay, bundle ID/native application selection, persistent file/folder native selection, URL, and multiline text, with reorder/remove/add controls. Picker errors are surfaced in main inspector and macro/step editor.
- Missing folder navigation destination shown. Disabled controls identified. Assignment payload preserves symbol and artwork; explicit optional icon clears use dedicated coordinator setters.
- Composer renders native AppKit PNG at 256×256 with raw background RGB initialization (avoids AppKit color-profile conversion), optional symbol and centered label; missing symbols fall back to label.
- Exported `.launchdeckprofile` UTI conforms to public.data, matches package agent's self-contained single-file JSON format; document type registered.

Verification: final arm64 Debug `xcodebuild` against integrated coordinator **BUILD SUCCEEDED**, code signing disabled, derived data `/tmp/LaunchDeck-editor-build`; build log `/tmp/editor-build.log`. Standalone compiled AppKit probe verified PNG decode, exactly 256×256, raw [255,0,0,255] background corner for red, valid/no/invalid symbols. Root adding lasting composition tests in owned tests.

Native UI/hardware interaction not performed. No commits. Preserved existing titlebar/window setup, glass Launchpad, physical 80-control arrangement and preview-only control selection. No focus-triggering test execution button added.

## Review corrections

- Activation now exposes Activate Selected Profile plus every Global, application, and manual profile, alongside Auto.
- Header shows Grant Keyboard Access when permissions are missing; its help text explains Accessibility requirement for shortcut/text actions.
- Application palette, inspector Change Action, and macro Add Step all use native .application chooser before storing a valid bundle identifier.
- Website defaults are valid `https://example.com`. Website editing buffers incomplete draft text with an inline warning and persists only a complete HTTP(S) URL; selecting another profile/page/control resets draft state.
- Removing the sole macro step is disabled to avoid invalid empty macros.
- Final incremental arm64 Debug build after these corrections: **BUILD SUCCEEDED** (`/tmp/editor-build.log`).
