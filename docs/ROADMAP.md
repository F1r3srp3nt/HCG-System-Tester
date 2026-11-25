# Roadmap & milestones

> No System Tester epic or quests existed in HCG-LifeOS when 0.1.0 was built. The bundled *Sovereign Technology*
> expansion has related tools (Network Diagnostics Suite, Universal Electronics Workbench, Robot Diagnostic Interface,
> Open Hardware Controller) but no System Tester entry. The roadmap below is proposed as a LifeOS backlog import
> ([`docs/lifeos/hcg-system-tester.backlog.json`](lifeos/hcg-system-tester.backlog.json), `hcg.lifeos.backlog` schema 2,
> realm *Sovereign Technology*). It has **not** been imported, and nothing awards XP. Import it yourself if you agree; it is idempotent by key.

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M1 — 0.1.0 MVP** (this release) | Real USB/Thunderbolt discovery, identification, five-layer assessment, adapter SDK, diagnostics, laboratory, visualizer, studio, reports, ecosystem panel, CLI | [Physical checklist](PHYSICAL-TESTING.md) completed on the M4 Max with reports exported |
| **M1.5 — 0.2.0 Device Intelligence** (this release) | Apple Device Intelligence Adapter, 13-state ladder, workspace, Live Monitor, USB Inspector, Visualizer 2.0 | [iPhone acceptance test](IPHONE-ACCEPTANCE.md) passed on iPhone 16 Pro Max and iPad Pro M4 |
| **M2 — Serial sessions** | Authorised, read-only serial port open; loopback/echo; measured round-trip latency | The first real device reaches **Connected** with evidence |
| **M3 — Network & Bluetooth** | Network framework path monitoring, DNS-SD for documented services, Core Bluetooth discovery; Local Network and Bluetooth permission texts | Network nodes in the Visualizer; reachability and latency diagnostics |
| **M4 — Storage health** | SMART/health through bridges that expose it via supported APIs | Health reported where available, limitation reported otherwise |
| **M5 — Console research** | PlayStation/Xbox: documented network presence, controller diagnostics over Bluetooth, compatibility reports | Evidence-backed compatibility matrix, no security bypass |
| **M6 — IoT / appliances** | Matter, MQTT (read-only), manufacturer APIs with explicit authorisation | Read-only measurements from at least one real appliance |
| **M7 — HCG Server** | Device Link pairing and `hcg.diagnostic-report/1` sync, service health | A report shared to a paired server |
| **M8 — HCG Connect** | Client registration, then PKCE sign-in, licensing and feature permissions | Sign-in optional; local use unaffected |
| **M9 — Nexus** | System Tester entry in HIP (Nexus project) | Nexus shows availability, version and routes |
| **M10 — Signal Contractor** | Shared adapter specification | Both products consume one discovery stack |
| **M11 — Adapter SDK v2** | Signed adapter packages built with Executable Maker | Signature verified before approval |
| **M12 — Distribution** | Developer ID, notarisation, DMG/pkg | Publication remains a manual founder decision |
