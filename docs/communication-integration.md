# InterApp — Communication Integration

## Integração móvel da Fase 2C

`e-mail/senha → Cognito User Pool (SRP) → access token → HTTPS API → três rotas de leitura`. O Amplify configura em runtime o User Pool existente a partir de dart-defines, faz persistência segura e refresh; widgets recebem apenas sessão sem tokens. Em 401 o cliente força refresh uma vez, repete uma vez e encerra a sessão após o segundo 401. Cursors são opacos e não persistidos. Não há Identity Pool nem chamada direta do app ao AWS IoT Core.


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
LocalDeviceConnectionRepository   — active for this generic provider; no hardware transport
CloudDeviceConnectionRepository   — delegates to DeviceBackendRepository, not wired as active yet
        ↓
DeviceBackendRepository           (features/devices/domain/repositories)
        ↓
LocalDeviceBackendRepository      — active only for generic command/event providers; reports CLOUD_UNAVAILABLE
(future) RemoteDeviceBackendRepository — HTTPS adapter for those providers, not implemented
```

`DeviceConnectionRepository` and `DeviceBackendRepository` are deliberately
two different contracts:

- `DeviceConnectionRepository` answers "how does the app talk to *a*
  device, regardless of transport" — this is what screens/providers depend
  on. Its local implementation also carries a debug-only
  `simulateIncomingCall` hook used during development (see
  `IncomingCallListener` in `PROJECT_CONTEXT.md`).
- `DeviceBackendRepository` is the older generic abstraction for claim,
  connection, commands and events. It is distinct from `HttpDeviceRepository`,
  which already consumes the deployed Cognito-authenticated device directory,
  status and personal-name routes. A future
  `CloudDeviceConnectionRepository` (already implemented, not yet wired as
  the active provider) is the adapter between the two.

Wiring the remaining generic providers from their local implementations to
their remote adapters is separate from the real backend capabilities already
used by the app. The provider boundary keeps that migration out of presentation
code.

## 2. Onboarding / provisioning (the one direct app ↔ device path)

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

Three entry paths converge into one coordinator — nearby BLE discovery is
primary (no QR needed for the normal case); QR/manual `setup_code` entry
are fallbacks that resolve *which* device, then re-enter the same BLE
sequence (they never skip physically talking to the device):

```text
AddInterBridgePage → OnboardingCoordinator → BleOnboardingTransport → (future) real BLE
                            │
                            └──────────────→ OnboardingClaimRepository → (future) real claim API
```

`BleOnboardingTransport` has no production implementation yet — only a
debug-only `MockBleOnboardingTransport` used to exercise the flow before
real BLE exists (`NotImplementedBleOnboardingTransport` is what production
builds get). **Before adding a Flutter BLE/ESP-provisioning package**,
verify it is actually compatible with ESP-IDF Unified Provisioning /
Protocomm Security 1 for the pinned ESP-IDF version the firmware build uses
(`docs/communication-protocol.md` §7) — do not adopt an outdated or
incompatible package.

The onboarding claim API is conceptually:

```text
POST /devices/claim/start          — BLE-primary path, once a device_id is known
POST /devices/claim/resolve-code   — QR/manual fallback, resolves a setup_code
POST /devices/claim/complete       — after BLE delivers provisioning material
POST /devices/claim/cancel
```

`setup_code` (`SetupCode`, `features/pairing/domain/entities/setup_code.dart`)
is **not** the same secret as `DeviceClaim.claimCode` from the product QR
(§4) — see PROJECT_CONTEXT.md, "setup_code vs. claim_code", for why a
12-digit human-typeable session code and a ≥128-bit permanent ownership
secret have to be two different things. No QR scanner/camera package is
included yet; `AddInterBridgePage`'s QR fallback accepts pasted text as a
stand-in.

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
- Wi-Fi credentials (only ever held in memory for the duration of
  `OnboardingCoordinator.submitWifi`, cleared from the UI's text field
  right after);
- the temporary AWS Fleet Provisioning material;
- the full onboarding `setup_code` in logs/analytics — use
  `SetupCode.maskedForLogging` (last 4 digits only) instead.

`DeviceClaim.toString()` redacts `claimCode` specifically because a naive
logger calling `toString()` on a caught exception/object is a realistic way
for a secret to leak by accident. `SetupCode.toString()` deliberately does
**not** redact — the user actively sees/types that value in the UI, so
hiding it there would break normal display code; only logging/analytics
call sites are required to use the masked form.

## 4. MQTT is not implemented in the UI

No widget, controller, or provider talks MQTT. The only place an MQTT-
shaped concept exists in this codebase is the **modeling** of what a
command/response/event *would* look like once the backend relays it — see
`features/devices/domain/entities/device_command.dart`,
`device_command_result.dart`, `device_event.dart`, `device_protocol_error.dart`.
These mirror the wire shapes from `docs/communication-protocol.md` §14/§16/
§18/§19/§21 so parsing/mapping logic can be written and tested. The generic
MQTT-shaped model/provider path described here is not itself wired to a remote
transport; separately, the Fase 2D UI uses the deployed authenticated HTTPS
command API. The app still never connects to MQTT directly.

## 5. Commands (`OPEN_DOOR`, `RESTART`)

```text
User taps "Abrir porta"
        ↓
DeviceCommandController (features/devices/presentation/providers/device_command_provider.dart)
        ↓
DeviceConnectionRepository.openDoor(deviceId)
        ↓
generic provider path still to wire remotely → command API
        ↓
backend creates and publishes the final OPEN_DOOR envelope (stamps
issued_at/expires_at, assigns/validates command_id), correlates the response
        ↓
DeviceCommandResult { status: ACCEPTED → COMPLETED / FAILED / REJECTED }
```

This diagram describes the generic `DeviceConnectionRepository` path that
still needs a remote adapter. The implemented Fase 2D path already calls the
deployed asynchronous HTTPS command API directly; HTTP acceptance alone does
not establish device execution or physical opening.

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
- implement `RemoteDeviceBackendRepository` for commands/events
  (`LocalDeviceBackendRepository` remains the active implementation for that
  abstraction, honestly reporting `CLOUD_UNAVAILABLE`; this does not refer to
  the real directory/name HTTPS APIs already used by `HttpDeviceRepository`);
- activate `CloudDeviceConnectionRepository` as the default
  `deviceConnectionRepositoryProvider` (still exists, still not wired in —
  see `devices_providers.dart`);
- implement real BLE provisioning, a QR scanner, or a camera reader.

For commands/events, the app still depends on a **future authenticated HTTPS
application API** — never on AWS IoT Core/MQTT directly — and it is the
backend, not the app, that will create and publish the final command
envelope. This statement does not include the real device directory and
personal-name HTTPS routes already deployed in DEV. All of the above remains Fase 1 AWS work; see
`docs/APP_COMMUNICATION_STATUS.md` for the up-to-date status of every area.
# Registro histórico da Fase 2D — concluída e encerrada

A interface de detalhes compõe a camada HTTPS assíncrona de `OPEN_DOOR` e a
expõe exclusivamente para membership `OWNER`, com confirmação explícita,
idempotência, polling limitado e cancelamento por sessão, descarte ou estados
de lifecycle `paused`/`inactive`/`hidden`/`detached`. O retorno ao app não
retoma nem reenvia o comando; uma confirmação explícita posterior, inclusive
na mesma tela, usa controller, tracker e chave novos. Um
202/`PENDING` nunca é sucesso; somente `COMPLETED` confirma abertura. O hardware
continua sem relé, GPIO, DTMF ou qualquer ação física, e o primeiro teste manual
em DEV deveria terminar em `REJECTED/CAPABILITY_DISABLED`. No momento em que
este registro foi escrito, a validação ponta a ponta ainda estava pendente para
depois do merge. Isso preserva o histórico daquela integração e não reabre a
Fase 2D nem classifica o trabalho posterior de `display_name` como parte dela.

As preferências locais `confirmBeforeOpeningDoor` e
`requireDeviceAuthenticationToOpenDoor` controlam, respectivamente, o diálogo
e a autenticação segura do aparelho antes do POST. A política da porta é
separada do bloqueio biométrico global e pode aceitar biometria ou credencial
segura suportada pela plataforma. Falha, cancelamento, indisponibilidade ou
preferências ainda não carregadas impedem o envio.

# Fase 3 — experiência do dispositivo e do usuário

A Fase 3 atual começa depois do encerramento da Fase 2D. Sua primeira entrega
funcional foi o nome pessoal por `DeviceMembership`: edição/limpeza via
`PATCH /v1/devices/{device_id}`, já implantado em DEV e validado no Android com
o valor `Casa` persistindo após sair e retornar à tela. O hotfix do backend foi
reimplantado com CloudFormation em `UPDATE_COMPLETE`; a primeira tentativa no
cold start da Lambda não gravou dados, e o reteste posterior validou
`app → API → DynamoDB → nova leitura`.

A reorganização entre Resumo, Diagnóstico e Configurações também pertence a
esta fase. Alteração de senha, preferências reais de notificação, FCM e BLE real
seguem, nessa ordem. Os modelos e mocks existentes de onboarding preservam
decisões anteriores, mas não significam que a implementação BLE real começou.


## Notification preferences (interBackend PR #21)

The final contract was merged in interBackend PR #21. The app integrates authenticated `GET`/`PATCH /v1/devices/{device_id}/notification-preferences` through `InterBridgeApiClient`. Preferences are per authenticated user and device, use one global alert mode and a quiet schedule, and are separate from local door preferences.

The backend is deployed in **DEV** (`InterBridge-Dev-ApiStack`, CloudFormation `UPDATE_COMPLETE`), and the integration has been validated end to end with a real call from the app: the app issued a real `PATCH`, and the resulting `notification_preferences` item was confirmed directly in DynamoDB (`app → API → Lambda → DynamoDB`). `alert_mode: NOTIFICATION_ONLY` was validated, as was `quiet_schedule.enabled: false` — disabling the quiet schedule preserves (does not clear) the previously saved days/times/timezone/behavior, which reappear on reactivation.

The UI was reorganized: alert/schedule settings moved out of the general device settings screen into a dedicated `NotificationPreferencesPage`, reached from a single "Notificações" entry on the main settings screen — opening that entry is what triggers the remote `GET`; the main screen never fetches remote preferences just to render its own summary. The page's manual "Salvar" button was replaced with autosave: valid edits start a debounced (700ms), coalesced, single-flight PATCH cycle, backed by a local per-user/per-device outbox that survives the app being killed mid-edit. Manual validation of this new autosave UI (distinct from the already-validated GET/PATCH/DynamoDB contract above) is still pending the next `flutter run` on a real device.

FCM/push and filter enforcement are not part of this integration; Android killed-state calls, later iOS calls, and audio remain separate work — none of that changed here. Network presence is only an undefined future possibility. Android and iOS obtain the current IANA identifier through a native channel without location or Wi-Fi permissions; the iOS implementation has not yet been validated in a macOS build or real device.
