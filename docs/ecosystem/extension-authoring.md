# LaunchDeck extension SDK (schema 1)

A `.launchdeckextension` file is UTF-8 JSON, not a ZIP archive or executable plugin. Its manifest declares stable action IDs, typed parameters, supported applications/services, exact HTTP hosts, and a recipe of ordinary LaunchDeck steps. The checked-in [Home Assistant extension](../../Samples/Ecosystem/org.launchdeck.home-assistant.launchdeckextension) is a complete installable example. The structural [JSON schema](extension.schema.json) is supplemented by the app's semantic validation.

Use **Extensions → Install or Update from File**, then assign **Extension Action** to a control or macro and choose its parameters. Installed extensions can be disabled or removed. Removal retains profile references; reinstalling the same extension/action IDs repairs them. Content Library provides catalog installation and update discovery. Packages are validated without running their actions.

## Manifest

All nonoptional fields must appear in JSON, including empty arrays. Required metadata:

| Field | Contract |
| --- | --- |
| `schemaVersion` | `1` |
| `id` | Stable reverse-domain identifier; letters, digits, `.`, `_`, `-`; max 160 characters |
| `name`, `author`, `license` | Nonempty display name, author, and license identifier |
| `version` | Three nonnegative numeric components, such as `1.2.0` |
| `supportedApplications` | Application bundle identifiers; empty means no declared restriction |
| `supportedServices` | Human-readable service names used by discovery |
| `allowedHosts` | Exact host names without schemes, ports, paths, or wildcards |
| `actions` | 1–64 actions, each with a stable unique ID |
| `symbolName` | Optional SF Symbol for the installed-extension list |

An action contains `id`, `name`, `parameters` (empty array permitted), and `recipe` (1–128 steps). Each parameter contains `id`, `name`, `type`, `required`, `choices` (empty except for choices), and optional `defaultValue`. Types are `string`, `choice`, `boolean` (`true`/`false`), `number` (finite), `url` (HTTP/HTTPS, without credentials), and `secretReference`. Invocation values are strings; unknown parameters are rejected and required values must be present or have defaults. Values are limited to 32,768 characters.

Recipes cannot invoke another extension or contain a nested macro/navigation action. Every expanded sequence is limited to 512 steps. Incompatible updates are rejected: existing action and parameter IDs remain, parameter types remain, choices may expand, and a new required parameter needs a default. An update is stored atomically only after complete validation, retaining the previous version and enabled state on failure. New incompatible APIs need a new extension ID.

## Recipe serialization

Recipes use Swift's existing Codable representation for `MacroStep`. A payload with an unnamed associated value uses `_0`:

```json
[
  { "text": { "_0": "Hello {{name}}" } },
  { "delay": { "milliseconds": 100 } },
  { "openWebsite": { "_0": "https://example.org/help" } },
  { "launchApplication": { "bundleIdentifier": "com.apple.TextEdit" } }
]
```

Other supported cases are `shortcut`, `openFile`, `openFolder`, `httpRequest`, and `script`. Shortcut payloads contain `keyCode`, `modifiers`, and `keyLabel`. Bookmarked file targets contain base64 `bookmark` and absolute `displayPath`; they depend on local file access and are less portable than website/text actions. Export a profile from LaunchDeck to inspect complete serialization, or use Swift `JSONEncoder` with `ExtensionManifest`/`ExtensionAction`/`MacroStep` when authoring programmatically.

`{{parameterID}}` substitutions are allowed in text, website URLs, application identifiers, HTTP URL/header/body values, and structured script arguments. Unknown or malformed substitutions fail validation. Secret references are permitted only in HTTP `secretHeaders`. Values interpolated inside HTTP body strings receive JSON string escaping, so an entity name cannot add JSON fields. Keep body placeholders inside quoted JSON string values; template interpolation is not a generic JSON expression language.

## HTTP requests and secrets

```json
{
  "httpRequest": {
    "_0": {
      "url": "{{baseURL}}/api/",
      "method": "GET",
      "headers": {},
      "allowedHosts": ["localhost", "127.0.0.1"],
      "secretHeaders": {"Authorization": "{{token}}"},
      "timeoutSeconds": 30
    }
  }
}
```

`body` is optional. Methods are GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS; timeout is 1–300 seconds. Request hosts must be a subset of manifest hosts, and the final expanded URL must match one exactly. HTTPS is required for remote hosts; HTTP is allowed for `localhost`, `127.0.0.1`, and IPv6 loopback. URL user/password fields and fragments are rejected. Redirects must keep the exact origin and declared host, protecting credentials from cross-origin redirects. Cookies and system credential storage are disabled. Responses are streamed with a 1 MB cap, support cancellation/timeouts, and non-2xx statuses fail the action. Response bodies are not returned as UI messages.

Authorization, Proxy-Authorization, Cookie, and X-API-Key belong in `secretHeaders`; literal values for these headers in `headers` are rejected. Secret headers map to local Keychain references. In **Extensions → Local HTTP Credentials**, save the complete header value, for example `Bearer <token>`, under the reference used by the action. Secrets are never inserted into stored profiles, catalogs, or manifests. Exported data contains only the reference string. LaunchDeck does not request or display existing Keychain values in this panel.

## Shell and AppleScript

A `script` step contains the same `ScriptAction` used by native controls: stable UUID `id`, `language` (`shell` or `appleScript`), `source` (an `inline` string or bookmarked `file`), `arguments`, `timeoutSeconds`, and `targetBundleIdentifiers`.

```json
{
  "script": {
    "_0": {
      "id": "A7E04285-F772-4D84-A199-E69381FB362D",
      "language": "shell",
      "source": {"inline": {"_0": "printf '%s\\n' \"$1\""}},
      "arguments": ["{{message}}"],
      "timeoutSeconds": 30,
      "targetBundleIdentifiers": []
    }
  }
}
```

Parameter templates in script source are forbidden. Arguments remain separate process arguments, even if a value contains quotes, command substitutions, or shell operators. The shell source itself is trusted executable code requiring local enabling before execution. Installing/importing/updating a package does not approve it; actual expanded script content and arguments participate in the local approval fingerprint. AppleScript targets declare the apps whose Automation permission may be needed. Keyboard/text steps still use the shared permission and focus checks.

## Home Assistant example

The bundled integration implements documented `GET /api/` and `POST /api/services/light/toggle` actions. Its default server is `http://localhost:8123`, and its exact allowed hosts are `localhost` and `127.0.0.1`. It becomes usable with a local Home Assistant instance and a locally stored `home-assistant-authorization` Keychain value containing the complete `Bearer …` header. Configure the light entity ID in the assignment before using Toggle Light.

For an instance on another machine, configure HTTPS, edit both manifest/request `allowedHosts` to that exact host, and update the `baseURL` default/assignment. LaunchDeck deliberately requires HTTPS outside loopback. The app does not fabricate a remote service or invoke this sample during installation/tests. The automated tests use an isolated local HTTP fixture and synthetic credential value.

Primary reference: [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/), inspected 2026-10-06. The API uses an Authorization bearer header; the sample endpoints and body follow that documentation.
