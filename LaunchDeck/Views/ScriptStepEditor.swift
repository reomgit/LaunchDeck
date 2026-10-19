// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

struct ScriptStepEditor: View {
    @Environment(AppCoordinator.self) private var coordinator
    let script: ScriptAction
    let update: (ScriptAction) -> Void
    var readOnly = false
    @State private var error: String?
    private func change(_ mutation: (inout ScriptAction) -> Void) { var copy = script; mutation(&copy); update(copy) }
    var body: some View {
        Group {
        Picker("Interpreter", selection: Binding(get: { script.language }, set: { value in change { $0.language = value } })) {
            ForEach(ScriptLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        switch script.source {
        case let .inline(code):
            TextEditor(text: Binding(get: { code }, set: { value in change { $0.source = .inline(value) } })).font(.body.monospaced()).frame(minHeight: 100, maxHeight: 160)
        case let .file(target): Text(target.displayPath).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button("Inline") { change { $0.source = .inline(script.language == .shell ? "printf 'Hello\\n'" : "return \"Hello\"") } }
            Button("Choose Script…") {
                let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do { let target = try FileTarget(url: url); change { $0.source = .file(target) } } catch { self.error = error.localizedDescription }
            }
        }
        TextField("Arguments (one per line)", text: Binding(get: { script.arguments.joined(separator: "\n") }, set: { value in change { $0.arguments = value.isEmpty ? [] : value.components(separatedBy: "\n") } }), axis: .vertical)
            .lineLimit(1...4)
        TextField("Timeout (seconds)", value: Binding(get: { script.timeoutSeconds }, set: { value in change { $0.timeoutSeconds = max(1, min(3600, value)) } }), format: .number)
        if script.language == .appleScript {
            TextField("Target bundle IDs (one per line)", text: Binding(get: { script.targetBundleIdentifiers.joined(separator: "\n") }, set: { value in change { $0.targetBundleIdentifiers = value.split(separator: "\n").map(String.init) } }), axis: .vertical)
                .lineLimit(1...4)
            Text("macOS may ask for Automation access to each declared app when dispatched. Manage access in System Settings → Privacy & Security → Automation.").font(.caption)
        }
        }.disabled(readOnly)
        Toggle("Enable this exact script on this Mac", isOn: Binding(get: { coordinator.scriptApprovals.isEnabled(script) }, set: { enabled in
            do { try coordinator.scriptApprovals.setEnabled(script, enabled: enabled) } catch { self.error = error.localizedDescription }
        }))
        Text("Review the command before enabling. Changing its contents or arguments requires enabling it again. Imported scripts start disabled.").font(.caption).foregroundStyle(.secondary)
        if let output = coordinator.scriptExecutor.lastOutput {
            DisclosureGroup("Latest script output") {
                ScrollView { Text(String((output.standardOutput + output.standardError).prefix(4000))).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 130)
                if output.outputTruncated { Text("Output truncated at the capture limit.").font(.caption) }
            }
        }
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
        if let error = coordinator.scriptApprovals.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
    }
}

struct ExtensionActionMenu: View {
    @ObservedObject var registry: ExtensionRegistry
    let select: (MacroStep) -> Void
    var body: some View {
        ForEach(registry.installedExtensions) { installed in
            Menu(installed.manifest.name) {
                ForEach(installed.manifest.actions) { action in
                    Button(action.name) { select(.extensionAction(ExtensionInvocation(extensionID: installed.id, actionID: action.id))) }.disabled(!installed.enabled)
                }
            }
        }
    }
}
