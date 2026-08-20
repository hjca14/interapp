# InterApp — Communication Implementation Status

## Fase 2C — implementada no app

O backend Fase 2B DEV foi implantado e validado com usuário confirmado e primeiro Device + membership OWNER/ACTIVE registrados atomicamente. O app autentica por e-mail/senha no User Pool existente usando Amplify/`USER_SRP_AUTH`, com refresh e armazenamento seguro nativo gerenciados pelo SDK. A API recebe o access token; o ID token nunca é usado como credencial HTTP. Estão conectadas somente as três rotas GET de dispositivos. Identity Pool, IoT direto, BLE, claim, commands, MQTT, eventos, realtime e voz estão adiados.

O bloqueio biométrico opcional usa a biometria nativa somente para liberar localmente uma sessão Cognito ainda válida. Ele é desativado por padrão, possui timeout de background configurável, nunca armazena senha e sempre oferece retorno ao login. Passkeys/WebAuthn permanecem uma solução futura para login biométrico real.


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
| Command timestamp encoding | Implemented | `issued_at`/`expires_at` are Unix epoch seconds on the wire (§14/§18) — `dateTimeToEpochSeconds`/`epochSecondsToDateTime`, `DeviceCommand.toJson`/`fromJson`. Backend-authoritative: the app never stamps these itself, only `command_id` |
| Error code taxonomy | Implemented | `DeviceProtocolError` covers all 18 v1 codes (aligned from an earlier, incomplete 13-code copy) + `unknown` fallback; app-side `origin` (device/backend/connectivity) for handling, without altering the wire codes |
| Device status model | Implemented | `DeviceStatus`, `IntercomState`, `DeviceStatus.fromReportedShadow` — tested against the protocol's shadow example |
| Intercom state vocabulary | Implemented | `IntercomState` recognizes all 5 defined values (`IDLE`/`RINGING`/`OFF_HOOK`/`IN_CALL`/`ERROR`, §22.1); anything else becomes a safe unknown state preserving the raw string |
| Realtime backend | Defined | `Stream<DeviceStatus> watchDeviceStatus(...)` contract exists; no real delivery mechanism (WebSocket/AppSync/etc.) chosen or built |
| `OPEN_DOOR` flow | Implemented (app-side) | Full `idle → sending → accepted/completed/failed/rejected/timedOut` state machine + UI in `DeviceDetailPage`; double-tap guarded; never auto-retries a timeout. Real execution is Stub — see "Backend API abstraction" |
| `RESTART` flow | Stub | Modeled in `DeviceCommandType`/`DeviceBackendRepository`; no dedicated UI — stays behind the existing "Reiniciar" placeholder in `DeviceSettingsPage` |
| QR claim model | Implemented | `DeviceClaim`/`DeviceClaimResult`, `parseDeviceClaimQrPayload` for the `interbridge://claim?v=1&device_id=...&claim_code=...` URI scheme (§4), full validation (scheme/host/version/device_id format/duplicate params/non-empty claim_code), `claimCode` redacted from `toString()` and never persisted after a claim |
| QR scanner | Not implemented | No scanner/camera package added (per protocol §37, don't add dependencies before they're needed); `AddInterBridgePage`'s QR fallback step accepts the scanned payload as manual text entry; `parseSetupCodeQrPayload`/`parseDeviceClaimQrPayload` both take a plain `String` so a scanner can be wired in later without changing either parser |
| Onboarding coordinator | Implemented (app-side) | `OnboardingCoordinator` — single state machine (`OnboardingState`/`OnboardingPhase`, 17 phases) driving `AddInterBridgePage`; converges BLE-primary (`scanningBle → deviceFound → confirmingDevice → connectingBle → selectingWifi → sendingWifi → startingClaim → claimActive → awsProvisioning → verifyingDevice → success`) and QR/manual fallback (`scanningQr`/`enteringSetupCode → resolvingSetupCode`) onto the same claim/provisioning tail; no provisioning logic lives in the screens. Real BLE/claim execution is Stub — see the two rows below |
| BLE provisioning abstraction | Stub | `BleOnboardingTransport` + `NotImplementedBleOnboardingTransport` (production) — `checkAvailability()` honestly reports `unsupported` and every action throws `UnimplementedError` instead of hanging or faking success; `MockBleOnboardingTransport` (debug-only, `kDebugMode`-gated) provides a working fake device for local dev/testing |
| BLE real provisioning | Needs validation | No real `BleOnboardingTransport` implementation exists; per `docs/communication-protocol.md` §7, verify a Flutter BLE/ESP-provisioning package's compatibility with ESP-IDF Unified Provisioning / Protocomm (Security 1, encrypted), pinned to the exact firmware ESP-IDF version, before adding one. Plaintext Wi-Fi credential transmission must never be implemented |
| Claim session API | Stub | `OnboardingClaimRepository` + `LocalOnboardingClaimRepository` (production) — every method throws `OnboardingClaimException(backendUnavailable)` instead of faking a session; `MockOnboardingClaimRepository` (debug-only) fakes a working `/devices/claim/{start,resolve-code,complete,cancel}` session for local dev/testing. The app never receives permanent AWS IoT X.509 credentials or AWS admin credentials through this path — only temporary onboarding material, never persisted longer than the flow needs |
| Wi-Fi provisioning | Not implemented | `OnboardingCoordinator.submitWifi(ssid, password)` accepts credentials and would pass them through `BleOnboardingTransport.sendWifiCredentials(...)` (local BLE session only, never sent to the backend, never logged/persisted), but there is no real transport yet to actually transmit them |
| Fleet provisioning backend | Not implemented | Depends on AWS real backend + BLE real provisioning |
| Onboarding analytics | Implemented (app-side) | `OnboardingAnalytics` + `DebugPrintOnboardingAnalytics`; `OnboardingCoordinator` fires all 12 required events (`onboarding_started` … `fallback_manual_used`) at the right transitions; Wi-Fi password/full `setup_code`/claim token/private keys are never included in event properties (`SetupCode.maskedForLogging` for the one case a code is logged) |
| Events | Stub | `DeviceEvent`, `DeviceEventType` (full v1 vocabulary + `unknown` fallback), `dedupeDeviceEvents`, `deviceEventsProvider` wired into "Eventos recentes" — backend always returns empty, so the UI still (correctly) shows "Nenhum evento recebido" |
| Push notifications | Not implemented | Out of scope for this task; unrelated to the existing local-only incoming-call notification (see PROJECT_CONTEXT.md §19, "Chamada recebida") |
| OTA UI | Not implemented | Deliberately deferred — see `docs/communication-integration.md`/PROJECT_CONTEXT.md for the scoping call; `OTA_STARTED`/`OTA_COMPLETED`/`OTA_FAILED` exist in `DeviceEventType` only |
| OTA backend | Not implemented | AWS IoT Jobs + S3 + signing, per §29 — none of it exists |
| Local LAN | Reserved | `DeviceConnectionRepository` can host a future `LocalLanDeviceConnectionRepository` alongside `CloudDeviceConnectionRepository` without UI changes; no local discovery/pairing/contract defined (§27.1 is explicit that this needs its own contract first) |
| Audio | Not implemented | Explicitly outside the control-plane protocol (§1); not touched by this task |

## What changed in the v1 contract alignment pass

This pass corrected the app's models/parsers to match the official v1
contract precisely — it did not activate any new real integration. Notably:

- `CloudDeviceConnectionRepository` is still **not** the active
  `deviceConnectionRepositoryProvider` (see restriction in the task that
  produced this pass) — `LocalDeviceConnectionRepository` remains active.
- No AWS SDK, Cognito SDK, or MQTT client was added.
- The app still only reaches a **future authenticated HTTPS application
  API** — never AWS IoT Core/MQTT directly — and the backend, not the app,
  creates and publishes the final command envelope.
