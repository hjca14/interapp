# InterApp — Communication Implementation Status

## Fase 3 — experiência do dispositivo e do usuário

The device list (`HomePage`'s Dispositivos tab) and details
(`ApiDeviceDetailPage`) already existed and are unchanged in their reading of
`listDevices`/`getDeviceDetails` (still the three GET routes from Fase 2C).
What's new: both now sit behind the `DeviceRepository` interface instead of
depending on `HttpDeviceRepository` directly. The everyday summary keeps only
the personal name and daily-use status/actions; hardware, friendly
configuration state (all official backend values translated) and the initially masked support identifier live in
Diagnostics. The full identifier is revealed on request and copied only by a
separate explicit action. Settings shows the friendly membership role and
whether sharing management is permitted, without offering a fake sharing
action while that feature remains unimplemented. A personal-name edit screen
(`EditDeviceNamePage`) lets
OWNER, ADMIN and MEMBER with an ACTIVE membership rename or clear their own
`DeviceMembership.display_name`. This is not a physical/global Device
property, and one user's update does not affect what another user sees. No
room/location field was added. The literal
"InterBridge" as the single fallback used everywhere (`deviceDisplayName`) —
`device_id` is never shown as a title. See the "Device rename" row below for
the confirmed contract and deployment status.

O `PATCH /v1/devices/{device_id}` e o hotfix do backend estão implantados em
DEV, com CloudFormation em `UPDATE_COMPLETE`. O teste real no Android salvou
`Casa` e confirmou o mesmo valor depois de sair e retornar à tela, validando
`app → API → DynamoDB → nova leitura`. A primeira tentativa havia falhado no
cold start da Lambda sem gravar dados; o backend foi corrigido, reimplantado e
o reteste funcionou. O incidente não é um bloqueio atual.

Esta experiência inaugura a Fase 3. A sequência decidida é: documentação,
alteração de senha da conta, preferências reais de notificação, FCM e onboarding
BLE real. Compartilhamento funcional não foi implementado.

## Fase 2D — concluída e encerrada

O backend da Fase 2D está implantado em DEV e o ESP32 real está conectado ao
AWS IoT Core por mTLS e inscrito no tópico real de comandos com QoS 1. A UI
agora compõe o transporte autenticado, idempotência e polling assíncrono já
existentes e os conecta ao botão “Abrir porta” da tela de detalhes. Somente a
membership `OWNER` pode confirmar e enviar `OPEN_DOOR`; demais papéis permanecem
bloqueados localmente, sem POST.

Um HTTP 202/`PENDING` significa apenas que o backend aceitou a solicitação para
processamento. Apenas `COMPLETED` permite à UI confirmar abertura. Polling é
limitado a 30 segundos e cancelado ao sair da tela, descartar o provider,
encerrar/inutilizar a sessão ou quando o app entra em `paused`, `inactive`,
`hidden` ou `detached`. O retorno ao app não retoma polling nem reenvia comando;
na mesma tela, uma nova confirmação explícita cria tracker e chave novos.
Timeout de criação
oferece retry explícito com a mesma chave de idempotência após o `Retry-After`;
uma nova ação confirmada gera uma nova chave.

O botão respeita as preferências locais por dispositivo: a confirmação aparece
somente quando `confirmBeforeOpeningDoor` está ativa e a autenticação segura do
aparelho ocorre antes de cada novo POST quando
`requireDeviceAuthenticationToOpenDoor` está ativa. Essa autenticação usa uma
política `local_auth` separada que aceita biometria ou credencial segura da
plataforma sem alterar o bloqueio biométrico global da sessão. Preferências
carregando ou com erro mantêm a ação indisponível.

O firmware continua propositalmente fail-closed (`DISABLED`). O resultado
esperado dessa etapa era `PENDING → ACCEPTED →
REJECTED/CAPABILITY_DISABLED`, exibido de forma amigável e sem alegar abertura.
Nenhuma ação física está implementada: relé, GPIO, DTMF e configuração de
abertura continuam adiados. Nenhuma chamada AWS, MQTT ou comando real foi feita
durante aquela integração. O roteiro manual registrado na época era:

`App → API → IoT → ESP32 → ACCEPTED → REJECTED/CAPABILITY_DISABLED → Basic Ingest → GET → App`.

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
| Device directory (list/details) | Implemented | `DeviceRepository.listDevices`/`getDeviceDetails`, backed by `HttpDeviceRepository` — same three deployed GET routes as before, now behind an abstract interface (`devices_providers.dart`'s `deviceRepositoryProvider`) |
| Device personal name (`display_name`) | Validated in DEV | Fase 3. Contract confirmed by interBackend PR #18: GET list/detail return the authenticated user's `DeviceMembership.display_name`; `PATCH /v1/devices/{device_id}` accepts a string of at most 60 characters or `null`, derives the user from the JWT, and lets ACTIVE OWNER/ADMIN/MEMBER memberships update only their own value. PATCH + backend hotfix are deployed in DEV (`UPDATE_COMPLETE`); Android saved `Casa` and loaded it again after leaving/returning, validating app → API → DynamoDB → read. |
| Authenticated password change | Implemented; DEV validation partial | Implemented in PR #17 under general account settings. One Android/Cognito DEV scenario was confirmed; the remaining scenarios still require end-to-end validation. Password recovery remains a separate flow. |
| Notification preferences | App integration complete; DEV pending | GET/PATCH contract from interBackend PR #21 is implemented with one global alert mode and quiet schedule per authenticated user + device. Tests use fakes; DEV deploy/E2E and actual filter application remain pending. No network-presence behavior remains. |
| FCM / Firebase | Not implemented | FCM is not configured and no Firebase project exists. No setup is required in this documentation PR. |
| Generic command/event repository abstraction | Implemented | `DeviceBackendRepository` + `LocalDeviceBackendRepository`; the local implementation remains active only for specific generic providers and honestly reports `CLOUD_UNAVAILABLE`. It is distinct from `HttpDeviceRepository` and from the deployed asynchronous command API. |
| Human auth abstraction | Implemented | `AuthRepository` + `LocalAuthRepository` (always signed-out; `signIn()` throws rather than faking a session) |
| Generic command/event provider migration | Pending | The asynchronous command API is deployed and used by the Fase 2D flow. What remains is migrating providers that still depend on `LocalDeviceBackendRepository`—not implementing the backend as a whole. |
| Command timestamp encoding | Implemented | `issued_at`/`expires_at` are Unix epoch seconds on the wire (§14/§18) — `dateTimeToEpochSeconds`/`epochSecondsToDateTime`, `DeviceCommand.toJson`/`fromJson`. Backend-authoritative: the app never stamps these itself, only `command_id` |
| Error code taxonomy | Implemented | `DeviceProtocolError` covers all 18 v1 codes (aligned from an earlier, incomplete 13-code copy) + `unknown` fallback; app-side `origin` (device/backend/connectivity) for handling, without altering the wire codes |
| Device status model | Implemented | `DeviceStatus`, `IntercomState`, `DeviceStatus.fromReportedShadow` — tested against the protocol's shadow example |
| Intercom state vocabulary | Implemented | `IntercomState` recognizes all 5 defined values (`IDLE`/`RINGING`/`OFF_HOOK`/`IN_CALL`/`ERROR`, §22.1); anything else becomes a safe unknown state preserving the raw string |
| Realtime backend | Defined | `Stream<DeviceStatus> watchDeviceStatus(...)` contract exists; no real delivery mechanism (WebSocket/AppSync/etc.) chosen or built |
| `OPEN_DOOR` flow | Implemented through the asynchronous API | Full `idle → sending → accepted/completed/failed/rejected/timedOut` state machine + UI in `DeviceDetailPage`; double-tap guarded; never auto-retries a timeout. HTTP acceptance does not prove execution. Physical opening remains disabled in firmware/hardware and was not validated; the safe applicable outcome is rejection such as `CAPABILITY_DISABLED` or the contract-equivalent state. |
| `RESTART` flow | Stub | Modeled in `DeviceCommandType`/`DeviceBackendRepository`; no dedicated UI — stays behind the existing "Reiniciar" placeholder in `DeviceSettingsPage` |
| QR claim model | Implemented | `DeviceClaim`/`DeviceClaimResult`, `parseDeviceClaimQrPayload` for the `interbridge://claim?v=1&device_id=...&claim_code=...` URI scheme (§4), full validation (scheme/host/version/device_id format/duplicate params/non-empty claim_code), `claimCode` redacted from `toString()` and never persisted after a claim |
| QR scanner | Not implemented | No scanner/camera package added (per protocol §37, don't add dependencies before they're needed); `AddInterBridgePage`'s QR fallback step accepts the scanned payload as manual text entry; `parseSetupCodeQrPayload`/`parseDeviceClaimQrPayload` both take a plain `String` so a scanner can be wired in later without changing either parser |
| Onboarding coordinator | Implemented (app-side) | `OnboardingCoordinator` — single state machine (`OnboardingState`/`OnboardingPhase`, 17 phases) driving `AddInterBridgePage`; converges BLE-primary (`scanningBle → deviceFound → confirmingDevice → connectingBle → selectingWifi → sendingWifi → startingClaim → claimActive → awsProvisioning → verifyingDevice → success`) and QR/manual fallback (`scanningQr`/`enteringSetupCode → resolvingSetupCode`) onto the same claim/provisioning tail; no provisioning logic lives in the screens. Real BLE/claim execution is Stub — see the two rows below |
| BLE provisioning abstraction | Stub | `BleOnboardingTransport` + `NotImplementedBleOnboardingTransport` (production) — `checkAvailability()` honestly reports `unsupported` and every action throws `UnimplementedError` instead of hanging or faking success; `MockBleOnboardingTransport` (debug-only, `kDebugMode`-gated) provides a working fake device for local dev/testing |
| BLE real provisioning | Not started | No real `BleOnboardingTransport` implementation exists. It follows FCM in the current work order; an older physical Android device is available for future testing. Before choosing a package, verify compatibility with ESP-IDF Unified Provisioning / Protocomm Security 1, pinned to the firmware version. |
| Claim session API | Stub | `OnboardingClaimRepository` + `LocalOnboardingClaimRepository` (production) — every method throws `OnboardingClaimException(backendUnavailable)` instead of faking a session; `MockOnboardingClaimRepository` (debug-only) fakes a working `/devices/claim/{start,resolve-code,complete,cancel}` session for local dev/testing. The app never receives permanent AWS IoT X.509 credentials or AWS admin credentials through this path — only temporary onboarding material, never persisted longer than the flow needs |
| Wi-Fi provisioning | Not implemented | `OnboardingCoordinator.submitWifi(ssid, password)` accepts credentials and would pass them through `BleOnboardingTransport.sendWifiCredentials(...)` (local BLE session only, never sent to the backend, never logged/persisted), but there is no real transport yet to actually transmit them |
| Fleet provisioning/claim integration | Not implemented | This onboarding-specific integration still depends on its claim API and real BLE provisioning; it does not mean the AWS application backend is generally absent. |
| Onboarding analytics | Implemented (app-side) | `OnboardingAnalytics` + `DebugPrintOnboardingAnalytics`; `OnboardingCoordinator` fires all 12 required events (`onboarding_started` … `fallback_manual_used`) at the right transitions; Wi-Fi password/full `setup_code`/claim token/private keys are never included in event properties (`SetupCode.maskedForLogging` for the one case a code is logged) |
| Recent-events provider | Stub | `DeviceEvent`, `DeviceEventType` (full v1 vocabulary + `unknown` fallback), `dedupeDeviceEvents`, `deviceEventsProvider` wired into "Eventos recentes". This provider still uses `LocalDeviceBackendRepository` and returns an empty list; that local binding does not characterize the deployed directory, status, personal-name or asynchronous command APIs. |
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
