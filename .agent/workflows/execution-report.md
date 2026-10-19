# Action execution implementation

Owned files: Core/ActionPlanner.swift, Core/ActionRunner.swift, Services/ActionExecutor.swift, Tests/LaunchDeckCoreTests/ActionRunnerTests.swift.

## Interfaces

`ActionExecutor.execute(_:targetProcessID:canPostEvents:completion:)` checks focus using the live workspace PID and the runner's expected target PID so launch/open can deliberately hand focus to a different application. The old original-target focus closure was removed. `activeApplicationChanged(processID:)` informs the runner of activation changes. `cancel()` cancels the task and releases keyboard modifiers.

`ActionExecutionResult`: dispatched, rejectedBusy, rejectedPermission, cancelled, failed(String). Dispatched means events/open requests were dispatched, not that a target application confirmed their semantic outcome.

`ActionRunner` is MainActor isolated, async and dependency injected. `Dependencies` supplies live permission/frontmost checks, async resource opening returning its expected foreground PID, shortcut posting, async text posting, and async delay. It serializes runs, stops at the first error, permits expected launch/open handoffs, and rejects unrelated activation during keyboard sequences. Native completion cleanup has a generation guard.

Native application/file/folder/website steps use NSWorkspace async open calls and wait up to two seconds for the expected app to become foreground before continuing. Bookmark failures, missing resources, wrong file/folder type, unavailable apps and malformed URLs report reselect/retry guidance. Keyboard permissions are needed for shortcut/text steps only. Unicode scalars use CGEvents, preserving the clipboard, with per-scalar yield, live focus/permission and cancellation checks. CGEvent/source creation failures report an error. Shortcut modifier releases run on normal dispatch, failure and cancellation.

## Verification

Tests written before runner implementation; initial build failed with missing runner and concurrent in-progress model contract changes. First verification after model additions: original four runner tests passed (permission per step, stop on error, expected handoff, unexpected focus); whole suite then failed only on the core worker's in-progress legacy migration tests.

Further tests added for ordering/delays, busy concurrency, cancellation during suspended delay and resource handoff, permission revocation before later text, activation notifications during delay and handoff, asynchronous text errors, navigation exclusion, resource-only actions without permissions and missing keyboard targets. All 15 execution tests passed in a temporary Core-only SPM package, including a clean second run after concurrency review; the temporary package was removed. Shared-package rerun compiles runner/native/coordinator but is pending the core worker's new red WorkflowTests for pageOrder/folderOrder/MacroStep.displayName. The native service compiled in the shared package. No warnings remain in the execution tests.

No physical MIDI device or native keyboard delivery was exercised by these injected tests.
