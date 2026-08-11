# InterApp — Communication Implementation Status

Companion to `docs/communication-integration.md`. This is a status snapshot,
not a design document — see that file (and `PROJECT_CONTEXT.md`) for the
"why" behind each row.

**Vocabulary** (same as `docs/communication-protocol.md` §38):

```text
Defined            Shape/contract exists in code, nothing calls it for real yet
Implemented        Working app-side logic, exercised by tests and/or the UI
Stub                A concrete implementation exists but honestly reports
                    "not available" instead of doing the real thing
Provisional         Working, but based on an assumption that needs confirming
Not implemented     No code for this yet
Hardware-dependent  Blocked on physical hardware/manufacturing decisions
Needs validation    Needs an explicit check before proceeding
Reserved            Named/modeled in the protocol for the future; intentionally untouched
```

Having an interface/class for something below does **not** mean it works in
production — that distinction is the entire point of this table.

| Area | Status | Notes |
|---|---|---|
| Backend API abstraction | Implemented | `DeviceBackendRepository` + `LocalDeviceBackendRepository` (honestly reports `CLOUD_UNAVAILABLE`) |
| Human auth abstraction | Implemented | `AuthRepository` + `LocalAuthRepository` (always signed-out; `signIn()` throws rather than faking a session) |
| AWS real backend | Not implemented | No AWS project/account/API exists yet; see `docs/communication-protocol.md` §37.1 |
| Device status model | Implemented | `DeviceStatus`, `IntercomState`, `DeviceStatus.fromReportedShadow` — tested against the protocol's shadow example |
| Realtime backend | Defined | `Stream<DeviceStatus> watchDeviceStatus(...)` contract exists; no real delivery mechanism (WebSocket/AppSync/etc.) chosen or built |
| `OPEN_DOOR` flow | Implemented (app-side) | Full `idle → sending → accepted/completed/failed/rejected/timedOut` state machine + UI in `DeviceDetailPage`; double-tap guarded; never auto-retries a timeout. Real execution is Stub — see "Backend API abstraction" |
| `RESTART` flow | Stub | Modeled in `DeviceCommandType`/`DeviceBackendRepository`; no dedicated UI — stays behind the existing "Reiniciar" placeholder in `DeviceSettingsPage` |
| QR claim model | Implemented | `DeviceClaim`/`DeviceClaimResult`, `parseDeviceClaimQrPayload`, `claimCode` redacted from `toString()` |
| QR scanner | Not implemented | No scanner package added (per protocol §37, don't add dependencies before they're needed); `PairingPage` accepts `device_id`/`claim_code` as manual text entry |
| BLE provisioning abstraction | Stub | `ProvisioningRepository`, `ProvisioningState` (all 13 phases from the protocol), `StubProvisioningRepository` — the stub honestly fails at `deviceFound` instead of hanging or faking success |
| BLE real provisioning | Needs validation | `ProvisioningTransport` has no implementation; per `docs/communication-protocol.md` §7, verify a Flutter BLE/ESP-provisioning package's compatibility with ESP-IDF Unified Provisioning / Protocomm Security 1 (and the firmware's pinned ESP-IDF version) before adding one |
| Wi-Fi provisioning | Not implemented | `wifiSsid`/`wifiPassword` are accepted and passed through `ProvisioningRepository.provision(...)`, held only in memory, but never actually transmitted anywhere real |
| Fleet provisioning backend | Not implemented | Depends on AWS real backend + BLE real provisioning |
| Events | Stub | `DeviceEvent`, `DeviceEventType` (full v1 vocabulary + `unknown` fallback), `dedupeDeviceEvents`, `deviceEventsProvider` wired into "Eventos recentes" — backend always returns empty, so the UI still (correctly) shows "Nenhum evento recebido" |
| Push notifications | Not implemented | Out of scope for this task; unrelated to the existing local-only incoming-call notification (see PROJECT_CONTEXT.md §19, "Chamada recebida") |
| OTA UI | Not implemented | Deliberately deferred — see `docs/communication-integration.md`/PROJECT_CONTEXT.md for the scoping call; `OTA_STARTED`/`OTA_COMPLETED`/`OTA_FAILED` exist in `DeviceEventType` only |
| OTA backend | Not implemented | AWS IoT Jobs + S3 + signing, per §29 — none of it exists |
| Local LAN | Reserved | `DeviceConnectionRepository` can host a future `LocalLanDeviceConnectionRepository` alongside `CloudDeviceConnectionRepository` without UI changes; no local discovery/pairing/contract defined (§27.1 is explicit that this needs its own contract first) |
| Audio | Not implemented | Explicitly outside the control-plane protocol (§1); not touched by this task |
