# Keep LaunchDeck Controls Bright When the Window Is Inactive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep LaunchDeck's editor and hosted titlebar controls in active visual appearance while their window is unfocused.

**Architecture:** Override SwiftUI's `appearsActive` environment value on the main editor root and the separate titlebar status controls. The override changes view styling only; existing enabled state and action logic remain the source of truth for interaction.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, macOS 26.

## Global Constraints

- Keep enabled editor controls visually active while LaunchDeck is unfocused.
- Existing `.disabled(...)` rules continue to control interaction availability.
- Native window chrome remains managed by macOS.
- Keep changes limited to the editor and hosted titlebar status control views.

---

### Task 1: Preserve Active Appearance for LaunchDeck Controls

**Files:**
- Modify: `LaunchDeck/EditorView.swift` — apply the appearance override to the main editor view hierarchy.
- Modify: `LaunchDeck/LaunchDeckApp.swift` — apply the appearance override to the separate titlebar status controls.

**Interfaces:**
- Consumes: SwiftUI's `EnvironmentValues.appearsActive` environment property.
- Produces: Editor and titlebar controls that prefer active appearance regardless of window focus; no new APIs or state.

- [x] **Step 1: Apply the environment override to the editor root**

Add this modifier to the root `HStack` in `LaunchDeckEditor.body`, immediately before its existing `.onAppear` modifier:

```swift
.environment(\.appearsActive, true)
```

- [x] **Step 2: Apply the environment override to titlebar controls**

Add this modifier to the `HStack` in `TitlebarStatusControls.body`, immediately after its closing brace and before `.padding`:

```swift
.environment(\.appearsActive, true)
```

- [x] **Step 3: Inspect the focused diff**

Run:

```bash
git diff --check
git diff -- LaunchDeck/EditorView.swift LaunchDeck/LaunchDeckApp.swift
```

Expected: `git diff --check` prints no diagnostics. The new changes are the two environment modifiers. Pre-existing edits in `LaunchDeck/LaunchDeckApp.swift` remain intact, and existing `.disabled(...)` rules and actions remain unchanged.

No automated tests are added or run for this appearance-only change.
