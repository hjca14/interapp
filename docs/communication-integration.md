# InterApp — Communication Integration

**Scope:** how the InterApp Flutter code implements/consumes InterBridge Communication Protocol **v1.1** (`docs/communication-protocol.md`).

This document does **not** redefine the firmware/cloud protocol. `docs/communication-protocol.md` is the single source of truth for topics, commands, event names, error codes, Device Shadow shape, provisioning, OTA, and security. This document only explains how the app-side code is structured around it, and what is real vs. scaffolding today. See `PROJECT_CONTEXT.md` for the app's broader architecture (Feature First, Riverpod, repository pattern) that all of this follows.

---

## 1. Architecture the app implements

```text
InterApp
   ↓ HTTPS / application APIs
ApplicationBackendRepository (DeviceBackendRepository)
   ↓
AWS application backend (Cognito / API / Lambda / storage)
   ↓
AWS IoT Core
   ↓ MQTT over TLS, X.509/mTLS
InterBridge
```

**The app never connects to AWS IoT Core directly and never holds a
permanent device X.509 certificate/private key.** MQTT + X.509 is strictly
the `AWS IoT Core ↔ InterBridge` channel. The app only calls authenticated
application APIs.

In code:

```text
DeviceDetailPage / DeviceSettingsPage
        ↓
Riverpod provider/controller
        ↓
DeviceConnectionRepository        (features/devices/domain/repositories)
        ↓
LocalDeviceConnectionRepository   — active today, no hardware/backend
CloudDeviceConnectionRepository   — delegates to DeviceBackendRepository, not wired as active yet
        ↓
DeviceBackendRepository           (features/devices/domain/repositories)
        ↓
LocalDeviceBackendRepository      — active today, honestly reports CLOUD_UNAVAILABLE
(future) RemoteDeviceBackendRepository — real HTTPS client, not implemented
```

`DeviceConnectionRepository` and `DeviceBackendRepository` are deliberately
two different contracts:

- `DeviceConnectionRepository` answers "how does the app talk to *a*
  device, regardless of transport" — this is what screens/providers depend
  on. Its local implementation also carries a debug-only
  `simulateIncomingCall` hook used during development (see
  `IncomingCallListener` in `PROJECT_CONTEXT.md`).
- `DeviceBackendRepository` answers "what does the AWS application backend's
  API expose" — claim, device list, status, commands, events. A future
  `CloudDeviceConnectionRepository` (already implemented, not yet wired as
  the active provider) is the adapter between the two.

Swapping from local to cloud, once a real backend exists, is a one-line
change in `features/devices/presentation/providers/devices_providers.dart`
— no presentation code changes, by design.

## 2. Provisioning (the one direct app ↔ device path)

```text
InterApp
   ↓ BLE (ESP-IDF Unified Provisioning / Protocomm Security 1)
InterBridge
   ↓ Wi-Fi
AWS IoT Fleet Provisioning
   ↓
AWS IoT Core
```

This is the **only** protocol-defined direct communication between the app
and a physical InterBridge. Everything else goes through the backend.

Code layout (`features/pairing/`):

```text
PairingPage → PairingController → ProvisioningRepository → ProvisioningTransport → (future) real BLE
                                         ↑
                              StubProvisioningRepository (active today)
```

`ProvisioningTransport` has no implementation yet. **Before adding a
Flutter BLE/ESP-provisioning package**, verify it is actually compatible
with ESP-IDF Unified Provisioning / Protocomm Security 1 for the pinned
ESP-IDF version the firmware build uses (`docs/communication-protocol.md`
§7) — do not adopt an outdated or incompatible package.

`docs/communication-protocol.md` §6.1 for product claim:

```text
InterApp (signed-in user)
   ↓ scans QR (device_id + claim_code)
DeviceBackendRepository.claimDevice(...)
   ↓
Backend validates + associates ownership
   ↓
Backend requests temporary AWS IoT Fleet Provisioning claim
   ↓
Temporary provisioning material → physical device, over the secure BLE session
```

No QR scanner package is included yet (see §7 below). `PairingPage` accepts
`device_id`/`claim_code` typed manually as a stand-in.

## 3. What the app never receives or stores

Per `docs/communication-protocol.md` §5, §6.1, §27, and the wider security
baseline:

- permanent device private key (generated on-device, never leaves it);
- permanent device X.509 certificate (not needed by the app; the backend/
  AWS IoT relationship is between the backend, AWS, and the device);
- AWS administrative/service credentials;
- the IoT fleet-wide device secret (there is none — every device is
  unique);
- firmware signing private key.

The app also must never persist or log, beyond the moment they're used:

- the product `claim_code`, after the claim flow completes;
- the BLE Proof of Possession;
- Wi-Fi credentials (only ever held in memory for the duration of the BLE
  provisioning call — see `ProvisioningRepository.provision`'s doc
  comment);
- the temporary AWS Fleet Provisioning material.

`DeviceClaim.toString()` redacts `claimCode` specifically because a naive
logger calling `toString()` on a caught exception/object is a realistic way
for a secret to leak by accident.

## 4. MQTT is not implemented in the UI

No widget, controller, or provider talks MQTT. The only place an MQTT-
shaped concept exists in this codebase is the **modeling** of what a
command/response/event *would* look like once the backend relays it — see
`features/devices/domain/entities/device_command.dart`,
`device_command_result.dart`, `device_event.dart`, `device_protocol_error.dart`.
These mirror the wire shapes from `docs/communication-protocol.md` §14/§16/
§18/§19/§21 so parsing/mapping logic can be written and tested today, but
none of it is wired to a real transport.

## 5. Commands (`OPEN_DOOR`, `RESTART`)

```text
User taps "Abrir porta"
        ↓
DeviceCommandController (features/devices/presentation/providers/device_command_provider.dart)
        ↓
DeviceConnectionRepository.openDoor(deviceId)
        ↓
(future) CloudDeviceConnectionRepository → DeviceBackendRepository → backend
        ↓
backend creates and publishes the final OPEN_DOOR envelope (stamps
issued_at/expires_at, assigns/validates command_id), correlates the response
        ↓
DeviceCommandResult { status: ACCEPTED → COMPLETED / FAILED / REJECTED }
```

The app is not the source of the command envelope. `DeviceCommand`
(`features/devices/domain/entities/device_command.dart`) models that
envelope for **parsing what the backend hands back**, not for the app to
build and send — `issued_at`/`expires_at` are backend-authoritative
timestamps, encoded on the wire as Unix epoch **seconds** (not ISO-8601,
not milliseconds — see `DeviceCommand.toJson`/`dateTimeToEpochSeconds` in
`core/protocol/protocol_constants.dart`). The phone's own clock is never
treated as a security authority; the app only contributes the command
intent and a client-generated `command_id` (`generateCommandId()`) as an
idempotency key for the future "create command" API call.

Error handling now covers the full v1 code list — including the
timestamp/expiry-specific codes `COMMAND_EXPIRED`, `CLOCK_NOT_TRUSTWORTHY`,
`INVALID_TIMESTAMP`, and `PAYLOAD_TOO_LARGE`/`PROVISIONING_FAILED` — via
`DeviceProtocolError` (`features/devices/domain/entities/device_protocol_error.dart`).
Each code also has an app-side-only `origin` (`device`/`backend`/
`connectivity`) used purely for diagnostics/handling; it does not alter or
reinterpret the wire codes themselves.

The UI's `OpenDoorRequestPhase` (`idle / sending / accepted / completed /
failed / rejected / timedOut`) exists specifically so a `200`-equivalent
response is never treated as success — only `status ==
DeviceCommandStatus.completed` is. `timedOut` is never sent by the device;
it's synthesized when no terminal response arrives, and does **not**
authorize automatically resending an expired command
(`docs/communication-protocol.md` §20.1) — `DeviceCommandController` never
retries on its own.

`RESTART` has the same modeling but no dedicated UI: the protocol notes a
device may report `ACCEPTED` before actually rebooting, and the
*reconnect* is the real completion signal — something only meaningful once
a live status stream from a real backend exists. Today it stays reachable
only as the disabled "Reiniciar" stub in `DeviceSettingsPage`.

`ANSWER_CALL` / `REJECT_CALL` / `END_CALL` are modeled in
`DeviceCommandType` (so a future response referencing one round-trips
safely) but are never offered anywhere in the UI — protocol v1 reserves
them, they are not implemented.

## 6. Status (Device Shadow, consolidated by the backend)

The app never reads the InterBridge's named Device Shadow (`interbridge`)
directly — the backend is the one that talks to AWS IoT and hands the app a
consolidated `DeviceStatus`. `DeviceStatus.fromReportedShadow` mirrors the
shadow's `reported` shape (`docs/communication-protocol.md` §22) for
parsing/testing, but `isOnline` is always supplied by the caller — the
protocol is explicit that online/offline comes from AWS IoT
lifecycle/connectivity events (§23), never from the shadow document or from
heartbeat timing alone.

`health_interval_s`, `ring_timeout_ms`, `door_open_duration_ms`,
`audio_volume` are Device Shadow **desired** configuration values, modeled
separately in `DeviceHardwareConfig` — see `PROJECT_CONTEXT.md`,
"DeviceSettings vs. Device Shadow config", for why these must never be
merged with the app/user preferences in `DeviceSettings`.

## 7. Events and realtime delivery

`Stream<DeviceStatus> watchDeviceStatus(...)` and `Stream<DeviceEvent>
watchDeviceEvents(...)` on `DeviceBackendRepository` intentionally don't
name a transport. The backend could deliver these over a WebSocket,
AppSync, polling, or something else — the app must not assume one, and
switching later must not require changing `DeviceDetailPage` or any
provider signature.

Events are deduplicated by `event_id` (`dedupeDeviceEvents`, per
`docs/communication-protocol.md` §17 — delivery is at-least-once).

## 8. Audio — explicitly out of scope

`docs/communication-protocol.md` states audio is not part of the MQTT
control plane and needs a separate low-latency transport that is not yet
designed (WebRTC/signaling/TURN are open questions — §37.1). Nothing in
this app sends or receives audio, and no audio interfaces were added by
this integration work.

## 9. Local LAN communication — future, not implemented

`docs/communication-protocol.md` §27.1 allows a future local HTTPS/
WebSocket path when the app and InterBridge share a trusted LAN, but
explicitly requires discovery, pairing, authorization, certificate pinning
and replay protection to be defined in a separate contract first — being on
the same Wi-Fi is not authorization. `DeviceConnectionRepository`'s
abstraction already supports adding a future
`LocalLanDeviceConnectionRepository` alongside `CloudDeviceConnectionRepository`
without touching screens; none exists yet.

## 10. Environment configuration

`AppConfig`/`AppEnvironment` (`lib/core/config/app_environment.dart`)
distinguish `DEV`/`PROD`. The app does not need to know the AWS IoT
endpoint, AWS region, or any AWS-specific identifier — all of that is the
backend's concern. `AppConfig.apiBaseUrl` is read from `--dart-define` at
build time and is empty (not configured) by default; nothing is hardcoded,
and a DEV build must never be able to reach PROD infrastructure.

## 11. Items resolved by the v1 contract alignment pass

Two gaps flagged by the initial integration were resolved once the exact
v1 contract details were confirmed (`docs/communication-protocol.md` §4,
§22.1):

- **`intercom_state` vocabulary** — now the five values `IDLE`, `RINGING`,
  `OFF_HOOK`, `IN_CALL`, `ERROR`. `IntercomState` recognizes exactly these
  and preserves the raw string for any value outside the set (`isKnown`),
  instead of crashing — see `intercom_state_test.dart`.
- **QR payload encoding** — now the URI scheme
  `interbridge://claim?v=1&device_id=ib-<32 hex>&claim_code=<secret>`.
  `parseDeviceClaimQrPayload` validates scheme, host, version, `device_id`
  format, presence/non-emptiness of `claim_code`, and rejects duplicate
  required parameters — see `device_claim_test.dart`.

Also aligned in this pass: `issued_at`/`expires_at` are Unix epoch
**seconds** on the wire (§14/§18, was previously shown as ISO-8601 in this
document by mistake), and the error code list grew from 13 to 18 entries
(`PAYLOAD_TOO_LARGE`, `COMMAND_EXPIRED`, `CLOCK_NOT_TRUSTWORTHY`,
`INVALID_TIMESTAMP`, `PROVISIONING_FAILED` were missing before) — see §5.

## 12. What this alignment did *not* do — still Fase 1 AWS

This pass corrected the app's **models and parsers** to match the v1
contract precisely. It did not, and was explicitly scoped not to:

- add the Cognito SDK, AWS SDK, or an MQTT client to the app;
- implement `RemoteDeviceBackendRepository` (there is still no real HTTPS
  API to call — `LocalDeviceBackendRepository` remains the active
  implementation, honestly reporting `CLOUD_UNAVAILABLE`);
- activate `CloudDeviceConnectionRepository` as the default
  `deviceConnectionRepositoryProvider` (still exists, still not wired in —
  see `devices_providers.dart`);
- implement real BLE provisioning, a QR scanner, or a camera reader.

The app still only ever talks to a **future authenticated HTTPS
application API** — never to AWS IoT Core/MQTT directly, and it is the
backend, not the app, that will create and publish the final command
envelope. All of the above remains Fase 1 AWS work; see
`docs/APP_COMMUNICATION_STATUS.md` for the up-to-date status of every area.
