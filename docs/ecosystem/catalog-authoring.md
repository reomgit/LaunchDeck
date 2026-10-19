# Content catalogs and icon packs

Content Library accepts a user-configured HTTPS catalog URL. HTTP loopback is supported for local development/testing. The app includes actual offline starter packages for all three content types and does not depend on a hosted marketplace. Use **Bundled Starter** to return to them. A successfully loaded catalog URL is remembered; reopening the library initially presents offline starters, and **Load Catalog** fetches the saved URL.

See the [catalog schema](catalog.schema.json), [icon pack schema](icons.schema.json), and [working sample catalog](../../Samples/Ecosystem/catalog.json).

## Catalog schema 1

The JSON object has `schemaVersion: 1` and an `entries` array. Every entry includes:

| Field | Meaning |
| --- | --- |
| `id` | Stable content ID, using letters, numbers, `.`, `_`, `-` |
| `type` | `profile`, `iconPack`, or `extensionPackage` |
| `name`, `author`, `license`, `description` | Display and authoring information |
| `version` | Three numeric components, e.g. `1.2.0` |
| `supportedApplications` | Application bundle identifiers (empty for general content) |
| `supportedDeviceModels` | `miniMK3`, `launchpadX`, `proMK3`, `virtual`; empty for general content |
| `supportedServices` | Service names indexed by search |
| `artifactURL` | Absolute HTTPS URL, or HTTP loopback during development |
| `size` | Exact artifact size in bytes; 1–50,000,000 |
| `sha256` | SHA-256 of exact downloaded bytes; 64 hexadecimal characters |

All fields above are mandatory, including empty arrays. IDs must be unique. Catalogs support at most 2,000 entries and are downloaded with a 2 MB cap. Artifact downloads enforce their declared size while streaming; exact size/digest are checked before package decoding or installation. Redirects retain the same origin and secure transport requirement. A catalog is trusted author metadata, not a signature: use an HTTPS host you trust and review packages before enabling executable scripts.

For extension/icon entries, the artifact's ID and version must exactly match the catalog entry. Update discovery compares the three numeric version components with the currently installed package. Missing/removed packages become available to install again. Profile entries track imported versions and offer **Import Again**; every import creates independent IDs and calls the editor's ordinary import/undo path, without overwriting an existing profile.

Create profiles with LaunchDeck's profile export. Current `.launchdeckprofile` schema 2 includes configuration schema/model compatibility metadata, all independent model layouts, and embedded PNG artwork. Legacy schema 1 packages remain supported by the normal importer. Avoid hand-editing bookmarked file or script references if portability matters.

## Icon pack schema 1

A `.launchdeckicons` file is JSON with `schemaVersion`, `id`, `name`, `version`, `author`, `license`, and `images`. The images object maps human-readable names to base64 PNG/JPEG bytes:

```json
{
  "schemaVersion": 1,
  "id": "org.example.icons",
  "name": "Example Icons",
  "version": "1.0.0",
  "author": "Your Name",
  "license": "CC0-1.0",
  "images": {"Home": "<base64 PNG bytes>"}
}
```

Use 1–256 images and names up to 100 characters. Each decoded image must be PNG or JPEG, a single frame, no larger than 4096×4096 pixels or 20 MB. The package must fit in 50 MB including base64 encoding. All imported images are normalized to PNG and get fresh local artwork IDs. Malformed images roll back the complete install/update and its new files. An update creates fresh IDs while retaining prior artwork files used by existing bindings. Removing a pack removes its library metadata and retains artwork already assigned to profiles.

Installed icons appear in the artwork picker. The installer preserves author/license metadata in the installed-pack index; attribute artists according to their license when redistributing exported profiles.

## Serve the checked-in examples locally

From the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Samples/Ecosystem
```

Enter `http://127.0.0.1:8765/catalog.json` in Content Library, then load and install all three entries. The sample artifact URLs point to that local server; they are not advertised as a public marketplace. For a hosted catalog, replace each URL with its actual HTTPS URL. Recompute `size` and `sha256` whenever any package byte changes:

```sh
wc -c Samples/Ecosystem/org.launchdeck.home-assistant.launchdeckextension
shasum -a 256 Samples/Ecosystem/org.launchdeck.home-assistant.launchdeckextension
```

Regenerate the checked-in starter packages/catalog after intentionally changing the embedded factories:

```sh
LAUNCHDECK_EXPORT_SAMPLE_CONTENT=1 swift test --filter EcosystemTests/testCheckedInSampleContentIsValidAndPortable
```

Routine tests read the checked-in packages and validate their digests, compatibility, extension installation, and icon normalization. Transport tests consume a real HTTP-served fixture catalog, including a newer version and a corrupt digest, and confirm rollback to the installed version.
