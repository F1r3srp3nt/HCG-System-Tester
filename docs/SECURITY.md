# Security & privacy

| Requirement | Implementation |
|---|---|
| Read-only discovery by default | IOKit registry reads only (`IORegistryEntryCreateCFProperties`, matching notifications). No device is opened or claimed |
| Explicit device authorisation | `AuthorizationStore.authorizeDevice`, a per-physical-unit toggle on the device page, audited |
| Capability-based permissions | `AdapterPermission`. Privileged permissions need a per-device, per-adapter grant **and** device authorisation (`PermissionDecision`) |
| Secure credential storage | Secret configuration fields may not have defaults and require `useStoredCredential`; the Keychain is planned for the first adapter that needs one. No credentials exist in 0.1.0 |
| Validated adapter manifests | `ManifestValidator`: schema, IDs, reserved namespace, known protocols, host-only operations, impact consistency, effects text, permission/lifecycle coupling, configuration typing, health-check limits |
| No untrusted code | Imported adapters are declarative only, stored untrusted and disabled, and never executed until approved |
| Redacted logs and reports | `Redactor`: the Device Link `hcg.redaction/1` credential rules, plus serial numbers, MAC/IP, e-mail, user paths and host name |
| Privacy controls for identifiers | Settings → Privacy (mask serials in the UI; redact in exports). Lab keys are salted fingerprints |
| Safe error handling | Disconnections become *aborted* results; unknown tests become *error* results; nothing crashes on unexpected registry values |
| Auditable operations | `AuditLog` (append-only JSON Lines) records every permitted or denied diagnostic and every authorisation or adapter decision |
| Experimental indicators | `experimental` adapters show an EXPERIMENTAL marker; planned interfaces are labelled *Planned* |
| Reversible configuration | No configuration changes are made to devices in 0.1.0 |
| Inbound URLs | `hcgsystemtester://open/<route>` only. Queries, fragments, credentials, extra segments and unknown routes are rejected; nothing is executed |
| Outbound URLs | Allow-listed Terminal and Sentinel destinations only; no data from devices or manifests is ever forwarded |
| Entitlements | Development builds are not sandboxed (IOKit registry access). No `root`, no helper tools, no kernel or DriverKit extensions |

Production security changes (sandboxing for distribution, Developer ID, notarisation, credential storage) need the founder's
manual approval.
