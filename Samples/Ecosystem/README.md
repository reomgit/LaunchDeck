# Working starter catalog

These are real installable samples of all three content types. The same factories are embedded in Swift for offline use. See [catalog authoring](../../docs/ecosystem/catalog-authoring.md) and [extension SDK](../../docs/ecosystem/extension-authoring.md).

Serve this directory with `python3 -m http.server 8765 --bind 127.0.0.1 --directory Samples/Ecosystem` from the repository root and load `http://127.0.0.1:8765/catalog.json` in Content Library. All artifact URLs deliberately point to that loopback server.

The Home Assistant extension requires a real configured local server and local Keychain authorization before use. Installation is validation only and sends no service request. Home, Play, and Folder artwork is created with CoreGraphics and licensed GPL-3.0-only with the app.
