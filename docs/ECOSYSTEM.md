# HCG ecosystem integration

Every integration below is based on contracts found in the sibling repositories on 24 Nov 2026. Where no contract exists,
System Tester **does not invent** endpoints, credentials or URL schemes. It records the gap instead.

| Product | Contract found | 0.1.0 behaviour | Next step |
|---|---|---|---|
| **HCG Server** | Device Link `hcg.devicelink/1` (vendored in HCG-Nexus `HCGDeviceLink/`, client 1.0.0): signed requests (P-256, `HCG-Link-*` headers), pinned TLS 1.3, invitation codes `hcg1-…`, reports `hcg.diagnostic-report/1`, redaction `hcg.redaction/1`. Admin API `127.0.0.1:7600`, peer API `:7610` | Exports **`hcg.diagnostic-report/1`** (wire-compatible mirror of `DiagnosticReport`, validated with Device Link's local rules: schema, redaction marker, title length, 256 KiB) | Pairing and report sync through Device Link ([roadmap](ROADMAP.md) M7). Never remote command execution |
| HCG Server "System Tester workload" | **Not found** on HCG-Server `main` (the only minimal hosting experiment there is `test-counter`). It may live on another branch | Left untouched, and kept separate from this native product | Confirm where the experiment lives |
| **HCG Terminal** | Deep links `hcgterminal://open/<destination>` (Standard) and `hcgterminal-unleashed://open/<destination>` (Unleashed). One segment, no query, navigation only. Terminal currently ships for iOS/iPadOS | Allow-listed navigation links only (`TerminalDeepLink`). Disabled with an explanation when no app handles the scheme on this Mac | A macOS Terminal build that registers the scheme |
| **HCG Sentinel** | `hcgsentinel://open/<destination>` and `hcgsentinel://report/<uuid>` (local reports only). **No inbound API for findings** | Navigation links. Findings are exported as `hcg.diagnostic-report/1` files | A Sentinel import path for `hcg.diagnostic-report/1` (Sentinel project) |
| **HCG Nexus** | HCG Interchange Protocol v1. The registry is compiled into Nexus and is iOS-only, with no System Tester entry. Apps may only narrow their routes via `HCGInterchange` in Info.plist | System Tester exposes navigation-only routes `hcgsystemtester://open/<route>` (`SystemTesterRoute`, strictly parsed) and stays fully functional without Nexus | Add a System Tester HIP entry in Nexus (Nexus project) |
| **HCG Connect** | No SDK in `HCG--Connect` (stub repo). The real contract is the `hcg-connect` configuration (`contractVersion`, `clientId` UUID, `issuer`, redirect URIs, scopes; PKCE public client; loopback redirect `127.0.0.1:47820-47822`) used by Nexus and Executable Maker. **No client issued for System Tester** | Shown as *Not configured*. No sign-in UI and no invented client. The app is fully usable locally | Register a System Tester client, then add PKCE sign-in |
| **HCG Signal Contractor** | Repository is a stub; no hardware schema | Proposes `hcg.adapter-manifest/1` + `hcg.systemtester.report/1` device summaries as the shared specification | Agree on the shared spec; Signal Contractor consumes System Tester's discovery instead of duplicating it |
| **HCG Executable Maker** | SwiftPM packaging with `AppPackaging.json` (`hcg-app-packaging/1`). `.xcodeproj` macOS projects are recognised but not built | `AppPackaging.json` declares product `HCGSystemTester`, bundle identity, Info.plist template and `.icns`. No helpers or prebuild commands | Package approved adapter projects (SDK v2) |
| **HCG LifeOS** | Backlog import `hcg.lifeos.backlog` (schema 2). **No System Tester quest import existed** | A proposed roadmap import is provided in `docs/lifeos/hcg-system-tester.backlog.json` (realm *Sovereign Technology*). **0.3.0:** Gap Analyzer exports selected development gaps as proposed quests (stable keys `hcg.systemtester.<gap-id>`, dependency closure, status backlog, no XP). Nothing is applied, completed or awarded automatically | You review and import it manually in LifeOS |
| **HCG AI** (0.3.0) | Public handoff `https://ai.hakmicapitalgroup.com/.well-known/hcg-ai-handoff.json` returns `404 not_published` until a native client is issued; central `/chat/completions` returns `501 chat_unavailable`. Companion relay base `…/api/public/companion/v1` requires a product client. **No native client for System Tester** | *Check availability* reads only the public handoff. The assistant in the app is rule-based and labelled *not AI*. Research requests are redacted text you transfer manually | Issue a System Tester native client; then an opt-in assistant that keeps AI suggestions separate from verified facts |
| **HCG Signal Contractor** (0.3.0) | As above | Receive-only SDR is registered as *delegated* to Signal Contractor in the Protocol Registry; System Tester does not duplicate it | Shared spec |
| **HCG Vanguard** (0.3.0) | **No repository or contract found** | Listed as *Awaiting contract*; nothing integrated or assumed | Publish a contract |

## Report formats

- `hcg.systemtester.report/1`: System Tester's native JSON (devices + layers + runs), redacted.
- `hcg.diagnostic-report/1`: the Device Link format. Findings come from warning, failed, error and aborted results. Checks
  cover every test, `notTested` lists diagnostic categories without host tests, and synthetic content is stated in
  `limitations`.
- Markdown: a human-readable report with a SYNTHETIC banner when applicable.
