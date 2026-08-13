# InterBridge — Contexto do Projeto

## 1. Visão do produto

**InterBridge** é um produto de hardware + software para modernizar interfones residenciais convencionais.

A ideia central é criar um **bridge entre um sistema de interfone físico/analógico existente e um aplicativo moderno**, permitindo controlar e acompanhar o interfone pelo celular sem substituir necessariamente toda a infraestrutura do condomínio ou residência.

O produto é composto por:

```text
┌─────────────────────┐
│      Interfone      │
│      físico         │
└──────────┬──────────┘
           │
           │ áudio / sinal
           │
┌──────────▼──────────┐
│     InterBridge     │
│      hardware       │
│                     │
│ comunicação local   │
│ controle do sistema │
└──────────┬──────────┘
           │
           │ rede / internet
           │
┌──────────▼──────────┐
│      InterApp       │
│   aplicativo móvel  │
└─────────────────────┘
```

O aplicativo atualmente é chamado **InterApp** no código/repositório, enquanto **InterBridge** é o nome do produto/ecossistema. O nome comercial definitivo do aplicativo ainda pode mudar.

---

## 2. Objetivos principais

O aplicativo deverá permitir ao usuário:

* cadastrar vários InterBridges;
* visualizar o estado de cada dispositivo;
* acessar um dispositivo específico;
* realizar chamadas pelo discador interno;
* abrir a porta/entrada através do InterBridge;
* receber informações e eventos do dispositivo;
* visualizar informações de firmware e conectividade;
* manter favoritos de discagem separados por dispositivo;
* compartilhar um dispositivo com outros usuários;
* futuramente receber chamadas do interfone no celular;
* futuramente configurar e atualizar o InterBridge;
* futuramente realizar atualizações OTA do firmware.

O objetivo não é criar simplesmente um "controle remoto".

O InterApp deverá ser a interface digital do sistema de interfone.

---

# 3. Conceito de funcionamento

O InterBridge será responsável por fazer a ponte entre o sistema físico e os protocolos digitais.

O fluxo conceitual é:

```text
Interfone convencional
        │
        │
        ▼
   InterBridge
        │
        ├── comunicação com o hardware do interfone
        │
        ├── controle de abertura
        │
        ├── áudio
        │
        ├── detecção de chamada
        │
        └── comunicação digital
                │
                ▼
         InterApp / Cloud
                │
                ▼
             Usuário
```

O hardware específico ainda está em desenvolvimento, mas o **protocolo de comunicação já está definido**: `docs/communication-protocol.md` (InterBridge Communication Protocol v1.1, arquitetura AWS IoT Core) é a fonte da verdade sobre como o InterBridge conversa com o backend/InterApp. Ver seção 26 deste documento para como o app implementa esse protocolo, e `docs/communication-integration.md`/`docs/APP_COMMUNICATION_STATUS.md` para os detalhes e o estado de implementação.

O aplicativo, portanto, **não deve assumir prematuramente uma tecnologia específica** além do que o protocolo já define — e o protocolo é claro que o app **não fala MQTT/AWS IoT Core diretamente**: ele só conversa com o backend de aplicação via APIs autenticadas. A única comunicação direta app↔InterBridge definida é BLE, exclusivamente para provisioning/recovery.

A arquitetura deve permitir trocar a implementação de comunicação sem precisar reescrever as telas.

---

# 4. Estado atual

* O aplicativo ainda não se comunica com um InterBridge físico.
* O hardware do InterBridge está sendo desenvolvido/prototipado separadamente.
* Dados de cadastro atualmente são persistidos localmente com `shared_preferences`.
* Não existem dados fictícios na interface: um dispositivo, perfil ou favorito só aparece depois de ser criado pelo usuário.
* O botão verde do discador é um ponto de integração futuro.
* O botão de discagem **não deve abrir o aplicativo de telefone do sistema nem usar `tel:`**.
* A comunicação real com o hardware ainda será implementada.
* Backend/cloud ainda não está implementado, mas a abstração já existe: `DeviceBackendRepository` (contrato) + `LocalDeviceBackendRepository` (stub honesto, reporta `CLOUD_UNAVAILABLE` em vez de fingir sucesso). Ver seção 26.
* **A seção 15 (Backend futuro) apontava Supabase como candidato — isso conflita com o protocolo v1.1, que define AWS (Cognito/API/Lambda + AWS IoT Core). Esse conflito está documentado, não resolvido silenciosamente — ver seção 26, "Conflito descoberto: Supabase vs. AWS".**
* O app já reage localmente a uma chamada recebida (`DeviceStatus.hasIncomingCall`): notificação do sistema + tela de chamada em tela cheia. Ver seção 19. Isso só funciona com o processo do app vivo; com o app fechado, ainda depende de push/backend (Fase 4).
* Fluxo real de `OPEN_DOOR` (máquina de estados idle/sending/accepted/completed/failed/rejected/timedOut) já existe na tela de detalhe do dispositivo, mas hoje sempre termina em "rejeitado: dispositivo não provisionado" porque não há backend/hardware real. Ver seção 26.

O projeto deve permanecer funcional mesmo sem um InterBridge físico conectado.

---

# 5. Princípios arquiteturais

## Feature First

Cada domínio do aplicativo fica isolado em:

```text
lib/features/<feature>
```

Exemplo:

```text
features/
├── devices/
├── dialer/
├── favorites/
├── pairing/
├── profile/
├── settings/
└── sharing/
```

Não criar uma estrutura global de `screens/`, `services/` ou `models/` que misture diferentes domínios sem necessidade.

---

## Separação entre identidade e estado

`InterBridgeDevice` representa a **identidade persistente/cadastrada** do dispositivo.

Ele contém:

* `id`
* `name`
* `createdAt`

Não adicionar telemetria ou estado temporário ao modelo apenas porque a tela precisa mostrar alguma informação.

O estado dinâmico fica separado em `DeviceStatus`.

---

## DeviceStatus

`DeviceStatus` representa o estado atual conhecido do hardware.

Pode conter informações como:

* conexão online/offline;
* estado da conexão;
* versão do firmware;
* bateria, caso o hardware possua bateria;
* informações de Wi-Fi;
* último contato;
* chamada recebida;
* erros;
* outros dados de telemetria futuros.

O status não deve ser persistido como se fosse a identidade do dispositivo.

Quando existir comunicação real, o status deverá ser atualizado por uma fonte dinâmica por `deviceId`.

---

## DeviceSettings

Existe uma terceira camada, além de identidade (`InterBridgeDevice`) e estado (`DeviceStatus`): as **preferências configuradas pelo usuário** para aquele dispositivo — `DeviceSettings`.

Diferente do status, `DeviceSettings` não vem do hardware: é escrito pelo usuário na tela de configurações e persistido por `deviceId`, com a mesma lógica de repository/provider usada no resto do projeto. Ver seção 25 para o modelo completo, a tela e o que falta implementar.

---

# 6. Contrato de comunicação com o hardware

A comunicação entre o aplicativo e o InterBridge é abstraída através de:

```text
DeviceConnectionRepository
```

Esse contrato define operações relacionadas ao dispositivo, como:

* conexão;
* acompanhamento de status;
* abertura de porta (`openDoor` retorna `DeviceCommandResult`, não apenas `void` — ver seção 26);
* discagem;
* futuramente atendimento/desligamento de chamadas;
* outros comandos específicos do InterBridge.

A tela do aplicativo não deve conhecer detalhes do protocolo físico.

Conceitualmente — **atualizado pelo protocolo v1.1** (o app não fala MQTT/AWS IoT Core diretamente; só o backend e o InterBridge fazem isso):

```text
UI
 │
 ▼
Provider / Controller
 │
 ▼
DeviceConnectionRepository
 │
 ├── LocalDeviceConnectionRepository (hoje, ativa) — sem hardware/backend
 │
 └── CloudDeviceConnectionRepository (já existe, não é a ativa ainda)
      │
      ▼
     DeviceBackendRepository — abstrai a API do backend de aplicação
      │
      ▼
     HTTPS autenticado → AWS application backend → AWS IoT Core → InterBridge
```

Bluetooth só aparece nesse desenho para o **provisioning/pareamento** (feature `pairing`, seção 13), não como uma forma alternativa de enviar comandos do dia a dia. Ver `docs/communication-integration.md` para a arquitetura completa.

A implementação concreta poderá mudar conforme o hardware/backend evoluir — trocar `LocalDeviceConnectionRepository` pela `CloudDeviceConnectionRepository` ativa é uma mudança de uma linha em `devices_providers.dart`.

---

# 7. Device Status Provider

`deviceStatusProvider` é a fonte de estado utilizada pelas telas para conhecer o estado atual de um dispositivo.

A tela de detalhes não deve criar ou manter manualmente um `DeviceStatus`.

Fluxo:

```text
DeviceDetailPage
       │
       ▼
deviceStatusProvider(deviceId)
       │
       ▼
DeviceConnectionRepository
       │
       ▼
InterBridge
```

Enquanto não houver hardware conectado, a implementação local deverá fornecer um estado coerente de ausência de conexão.

A UI não deve inventar que um dispositivo está online ou possui determinado firmware.

---

# 8. Arquitetura atual

A arquitetura utiliza:

### Flutter / Dart

Framework principal do aplicativo.

### Riverpod

Gerenciamento de estado e injeção de dependências.

`main.dart` cria um `ProviderContainer`, inicializa o `IncomingCallNotificationService` (assíncrono) e sobe o app com `UncontrolledProviderScope` — em vez do `ProviderScope` simples — para permitir esse setup antes do primeiro frame.

Repositórios locais são expostos através de:

```text
features/devices/presentation/providers/devices_providers.dart
```

### GoRouter

Navegação do aplicativo.

Rotas ficam em:

```text
lib/core/router/app_router.dart
```

A rota de detalhes é:

```text
/devices/:deviceId
```

No estado atual, o objeto do dispositivo também pode ser encaminhado via `extra`.

Quando houver backend, a rota deverá ser capaz de buscar o dispositivo pelo `deviceId`, em vez de depender do objeto enviado pela navegação.

### Shared Preferences

Utilizado atualmente para persistência local do protótipo.

---

# 9. Estrutura relevante

```text
lib/
│
├── main.dart
│
├── app/
│   ├── app.dart
│   ├── router/
│   └── theme/
│
├── core/
│   ├── config/
│   │   └── app_environment.dart
│   ├── constants/
│   ├── protocol/
│   │   └── protocol_constants.dart
│   ├── router/
│   │   └── app_router.dart
│   └── theme/
│
├── features/
│   │
│   ├── auth/
│   │   ├── data/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   └── repositories/
│   │   └── presentation/
│   │       └── providers/
│   │
│   ├── devices/
│   │   ├── data/
│   │   │   ├── repositories/
│   │   │   └── services/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   └── repositories/
│   │   └── presentation/
│   │       ├── pages/
│   │       ├── providers/
│   │       └── widgets/
│   │
│   ├── dialer/
│   │   ├── data/
│   │   │   └── services/
│   │   └── presentation/
│   │       ├── controllers/
│   │       ├── pages/
│   │       └── widgets/
│   │
│   ├── favorites/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── pairing/
│   │   ├── data/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   ├── repositories/
│   │   │   └── services/
│   │   └── presentation/
│   │       ├── controllers/
│   │       ├── pages/
│   │       └── providers/
│   │
│   ├── profile/
│   │
│   ├── settings/
│   │
│   └── sharing/
│
└── shared/
    └── widgets/
```

---

# 10. Fluxos implementados

## Dispositivos

1. A aba **Dispositivos** exibe os InterBridges cadastrados.
2. O usuário adiciona um dispositivo por nome.
3. O dispositivo recebe um identificador próprio.
4. O usuário pode editar o nome.
5. O usuário pode remover o dispositivo.
6. Tocar em um dispositivo abre `DeviceDetailPage`.
7. O detalhe possui as abas:

   * **Resumo**
   * **Discar**
   * **Favoritos**
8. O cadastro do dispositivo não depende de uma conexão física.
9. Eventos, status e firmware não são simulados.
10. Enquanto não houver conexão, a UI informa que está aguardando conexão/dados.

---

# 11. Discador

O InterApp possui um discador interno.

O discador é destinado à comunicação através do InterBridge.

Ele **não é um discador telefônico do sistema operacional**.

Portanto:

* não usar `tel:`;
* não abrir o aplicativo Telefone;
* não depender de uma linha telefônica celular;
* o botão de chamada é um ponto de integração com o hardware.

Futuramente, o fluxo será aproximadamente:

```text
Usuário
  │
  ▼
Discador
  │
  ▼
DeviceConnectionRepository
  │
  ▼
InterBridge
  │
  ▼
Sistema de interfone
```

---

# 12. Favoritos

Favoritos pertencem a um dispositivo específico.

A persistência local utiliza:

```text
favorites_<deviceId>
```

Portanto, dois InterBridges diferentes podem possuir favoritos diferentes.

Tocar em um favorito:

1. preenche o número no discador;
2. abre a aba **Discar**;
3. futuramente permitirá iniciar a comunicação através do InterBridge.

`FavoriteFormDialog` possui seus próprios `TextEditingController`s para evitar problemas de ciclo de vida durante a abertura/fechamento do diálogo.

---

# 13. Onboarding (pareamento de um novo InterBridge)

Três caminhos de entrada convergem num único coordinator:

```text
1. Descoberta BLE por perto — PRIMÁRIO (não exige QR)
2. QR com setup_code       — FALLBACK
3. Código digitado à mão   — FALLBACK
```

O caminho primário não pede QR: "Adicionar InterBridge" → instrução (luz piscando azul) → escaneia BLE por perto → usuário confirma o aparelho físico → conecta por BLE → escolhe Wi-Fi → sessão de claim autenticada → material de provisioning temporário entregue ao dispositivo por BLE → dispositivo faz o Fleet Provisioning na AWS → verifica online → sucesso. **AWS IoT, MQTT, X.509, CSR, Fleet Provisioning, Thing nunca aparecem para o usuário** — só nos comentários do código.

Arquitetura em `features/pairing/`:

```text
AddInterBridgePage → OnboardingCoordinator → BleOnboardingTransport → BLE real (futuro)
                            │
                            └──────────────→ OnboardingClaimRepository → backend real (futuro)
```

* `OnboardingState`/`OnboardingPhase` (`domain/entities/onboarding_state.dart`) — as 14 fases primárias (idle, checkingSetupMode, scanningBle, deviceFound, confirmingDevice, connectingBle, selectingWifi, sendingWifi, startingClaim, claimActive, awsProvisioning, verifyingDevice, success, error) + 3 de fallback (scanningQr, enteringSetupCode, resolvingSetupCode). `OnboardingFailureKind` classifica o motivo de `error` (bleUnavailable/scanTimeout/connectionFailed/wifiFailed/claimFailed/alreadyOwned/invalidOrExpiredCode/rateLimited/unknown) para a UI escolher a ação de recuperação certa, sem precisar de uma fase por motivo.
* `OnboardingCoordinator` (`presentation/controllers/`) — **a única** máquina de estados; `AddInterBridgePage` só lê `state` e chama métodos nela, sem lógica de provisioning na tela. Os dois fallbacks convergem no mesmo caminho BLE do primário — QR/código manual só respondem "qual dispositivo", nunca pulam a presença física por Bluetooth.
* `SetupCode` (`domain/entities/setup_code.dart`) — código de 12 dígitos, aceita espaços/traços e normaliza. **Não é o mesmo conceito que `DeviceClaim.claimCode`** (ver "setup_code vs. claim_code" abaixo). `maskedForLogging` mostra só os últimos 4 dígitos — nunca logar o código completo.
* `DiscoveredInterBridge` — só expõe `friendlyName` (ex.: `InterBridge-A91C`) pra UI normal; `deviceId` técnico fica reservado para uma futura tela de diagnóstico/desenvolvedor.
* `ClaimSession` (`domain/entities/claim_session.dart`) + `OnboardingClaimRepository` (`domain/repositories/`) — `start`/`resolveSetupCode`/`complete`/`cancel`, espelhando a API conceitual `POST /devices/claim/*`. Falhas viram `OnboardingClaimException` com um motivo genérico (`invalidOrExpiredCode`/`alreadyOwned`/`rateLimited`/`backendUnavailable`) — a UI nunca revela se um código existe, já foi usado ou pertence a outra pessoa.
* `BleOnboardingTransport` (`domain/repositories/`) — scan/connect/secure session/Wi-Fi/material de Fleet Provisioning. **Antes de adicionar um pacote Flutter de BLE/ESP provisioning, validar compatibilidade com ESP-IDF Unified Provisioning/Protocomm Security 1** (protocolo §7) — não adotar pacote obsoleto/incompatível.
* `OnboardingAnalytics` (`domain/services/`) — eventos não sensíveis (`onboarding_started`, `ble_scan_started`, `device_discovered`, `device_confirmed`, `ble_connected`, `wifi_config_sent`, `claim_started`, `provisioning_started`, `onboarding_completed`, `onboarding_failed`, `fallback_qr_used`, `fallback_manual_used`). Nunca inclui senha de Wi-Fi, `setup_code` completo, token de claim ou chave privada.

## Stub (produção) vs. mock (debug)

Igual ao padrão já usado no resto do app (`LocalDeviceConnectionRepository`): produção usa uma implementação honesta que reporta "não implementado"; builds de debug usam um fake funcional pra dar pra testar o fluxo inteiro sem hardware, selecionado automaticamente por `kDebugMode` em `pairing_providers.dart` — nunca manualmente em produção.

* `NotImplementedBleOnboardingTransport` (produção) / `MockBleOnboardingTransport` (debug, simula achar `InterBridge-A91C`).
* `LocalOnboardingClaimRepository` (produção, sempre `backendUnavailable`) / `MockOnboardingClaimRepository` (debug, sempre sucesso).

## setup_code vs. claim_code — não são o mesmo segredo

Achado importante ao implementar esta tarefa: `setup_code` (12 dígitos, ~40 bits de entropia) e `DeviceClaim.claimCode` (seção 26, ≥128 bits exigidos pelo protocolo) **não podem ser o mesmo valor** — 12 dígitos decimais não têm entropia suficiente para ser o segredo de posse permanente do produto. São conceitos complementares, não conflitantes:

* **QR do produto** (`docs/communication-protocol.md` §4): `device_id` + `claim_code` de alta entropia, impresso no aparelho, segredo de posse permanente.
* **`setup_code` de onboarding** (esta tarefa): código curto, de sessão, rate-limited e de vida curta, usado só para o backend correlacionar um scan/digitação a uma tentativa de claim — não concede posse sozinho.

`parseDeviceClaimQrPayload`/`DeviceClaim` (seção 26) continuam existindo para o QR do produto definido no protocolo; o novo fluxo de onboarding usa `parseSetupCodeQrPayload`/`SetupCode` em vez disso. Não foram unificados propositalmente — servem a momentos diferentes do fluxo.

Ver `docs/communication-integration.md` (seção 2) e `docs/APP_COMMUNICATION_STATUS.md` para o estado exato de cada peça.

---

# 14. Compartilhamento entre usuários

Um mesmo InterBridge poderá ser utilizado por várias pessoas.

O modelo inicial de permissões está em:

```text
features/sharing/domain/entities/device_access.dart
```

Papéis previstos:

### owner

Proprietário do dispositivo.

Pode:

* administrar o dispositivo;
* remover o dispositivo;
* compartilhar o dispositivo;
* administrar acessos.

### admin

Pode administrar o dispositivo e favoritos conforme as permissões definidas.

### member

Pode utilizar o dispositivo conforme as permissões concedidas.

O compartilhamento ainda não está implementado.

---

# 15. Backend futuro

**⚠️ Esta seção contém uma decisão desatualizada — ver o aviso abaixo antes de agir sobre ela.**

O protótipo atualmente funciona localmente.

Quando o produto evoluir para múltiplos usuários/dispositivos, será necessária uma camada cloud.

Esta seção originalmente apontava **Supabase Cloud** como candidato inicial (autenticação, PostgreSQL, Row Level Security, APIs, realtime, infraestrutura gerenciada). Isso foi escrito **antes** de existir o InterBridge Communication Protocol v1.1 (`docs/communication-protocol.md`).

## Conflito descoberto: Supabase vs. AWS

O protocolo v1.1 define, sem ambiguidade, uma arquitetura **AWS** para a comunicação com o dispositivo:

```text
InterApp → AWS application backend (Cognito/API Gateway/Lambda) → AWS IoT Core (MQTT/X.509) → InterBridge
```

MQTT sobre AWS IoT Core, Device Shadow, Fleet Provisioning, IoT Jobs (OTA) — tudo isso é específico da AWS. O Supabase não oferece esse lado de "device cloud" (gateway MQTT com mTLS por dispositivo, Shadow, Jobs). Portanto:

* **A comunicação com o InterBridge (status, comandos, eventos, OTA, provisioning) precisa de AWS IoT Core.** Isso não é negociável sem reescrever o protocolo do firmware.
* Se o Supabase ainda fizer sentido para partes do backend de **aplicação** (dados de usuário que não envolvem o dispositivo diretamente, por exemplo), isso é uma decisão separada e explícita — não uma continuação automática da escolha anterior.
* Seguindo a regra de "não inventar solução silenciosamente diante de conflito" (ver seção 26), esta tarefa **não** decidiu isso por conta própria. `DeviceBackendRepository` e `AuthRepository` continuam abstratos; nenhuma implementação real (Supabase, AWS ou híbrida) foi adicionada.

**Próximo passo real:** quem decide a arquitetura do projeto precisa confirmar explicitamente se o backend de aplicação será 100% AWS (Cognito + API Gateway + Lambda, alinhado ao protocolo) ou se haverá alguma combinação com Supabase — e atualizar esta seção com a decisão final.

## O que continua válido

A arquitetura deve permitir trocar as implementações locais por remotas sem modificar a UI — isso já é verdade hoje via `DeviceBackendRepository`/`AuthRepository` (abstrações) e `LocalDevicesRepository`/`LocalFavoritesRepository` (repositórios locais concretos que podem ganhar uma contraparte remota depois).

Não criar um servidor próprio apenas por necessidade arquitetural enquanto o produto ainda estiver em protótipo/MVP — mas note que, para a comunicação com o dispositivo, "servidor próprio" não é a alternativa em disputa: a escolha real é AWS (exigido pelo protocolo) vs. onde hospedar a parte de aplicação que não fala com o dispositivo.

---

# 16. Segurança

Segurança é especialmente importante porque o InterBridge controla uma entrada física.

Nunca confiar somente nas permissões implementadas no aplicativo.

Quando existir backend:

* autorização deverá ser validada no backend;
* usuários só poderão acessar dispositivos aos quais possuem permissão;
* comandos sensíveis deverão ser autenticados;
* convites deverão ser opacos, de uso único e possuir expiração;
* tokens e credenciais não devem ser armazenados em código;
* comunicação deverá utilizar canais seguros;
* firmware deverá possuir mecanismo seguro de atualização;
* o dispositivo deverá validar comandos recebidos;
* não assumir que estar na mesma rede significa estar autorizado.

O comando **abrir porta** deve ser tratado como operação sensível.

O protocolo v1.1 (`docs/communication-protocol.md`) detalha as regras de segurança concretas para essa comunicação — segredos que o app nunca deve guardar/logar, separação entre autenticação humana e autenticação do dispositivo (X.509/mTLS), proibição de factory reset remoto, etc. Ver seção 26 deste documento e `docs/communication-integration.md` (seção 3, "O que o app nunca recebe ou guarda") para o resumo aplicado ao InterApp.

---

# 17. Firmware e hardware

O InterBridge físico será desenvolvido separadamente do aplicativo.

O aplicativo deve considerar que o hardware poderá:

* conectar/desconectar;
* enviar status;
* informar versão de firmware;
* receber comandos;
* detectar chamadas;
* transmitir/receber áudio;
* controlar a abertura da porta;
* receber atualizações de firmware;
* apresentar falhas de comunicação.

A implementação concreta do hardware ainda está em desenvolvimento.

O software não deve criar dependências prematuras de uma placa ou protocolo específico.

---

# 18. Comunicação de áudio

Um dos objetivos futuros do InterBridge é transportar o áudio do sistema de interfone para o aplicativo.

O fluxo conceitual será:

```text
Interfone
   │
   ▼
InterBridge
   │
   │ áudio
   ▼
rede / protocolo seguro
   │
   ▼
InterApp
```

O protocolo v1.1 confirma isso explicitamente: **áudio está fora do control plane MQTT** e precisa de um transporte de baixa latência separado, ainda não definido (WebRTC/signaling/TURN são questões em aberto — `docs/communication-protocol.md` §37.1). Nada de áudio foi implementado por esta tarefa de integração de protocolo.

A arquitetura do aplicativo deve permitir que a implementação seja adicionada futuramente sem reestruturar todo o projeto.

---

# 19. Eventos

O vocabulário de eventos do protocolo v1.1 (`docs/communication-protocol.md` §16) já está modelado em `DeviceEventType` (`features/devices/domain/entities/device_event.dart`):

```text
RING_DETECTED, OFF_HOOK, ON_HOOK, CALL_STARTED, CALL_ENDED,
DOOR_OPENED, DOOR_OPEN_FAILED,
PROVISIONING_STARTED, PROVISIONING_COMPLETED, PROVISIONING_FAILED,
FACTORY_RESET_REQUESTED,
OTA_STARTED, OTA_COMPLETED, OTA_FAILED,
ERROR
```

`DeviceEvent.fromJson` faz o parsing tolerando campos extras desconhecidos e validando `protocol_version` (lança `UnsupportedProtocolVersionException` para uma versão que o app não entende). `dedupeDeviceEvents` remove duplicatas por `event_id` (o protocolo entrega eventos pelo menos uma vez — duplicatas são esperadas).

A aba **Resumo** de `DeviceDetailPage` já consome `deviceEventsProvider(deviceId)` (`features/devices/presentation/providers/device_events_provider.dart`), que carrega o histórico recente e escuta eventos ao vivo via `DeviceBackendRepository`. Hoje o backend é o stub `LocalDeviceBackendRepository`, que sempre devolve uma lista vazia — então a tela continua mostrando:

```text
Nenhum evento recebido
```

em vez de inventar eventos, exatamente como antes. Quando um `DeviceBackendRepository` real existir, eventos verdadeiros aparecem sem precisar mudar a tela.

## Chamada recebida (incoming call)

O evento **chamada recebida** já tem um caminho de reação implementado no app, preparado para quando o hardware existir de verdade:

* `DeviceStatus.hasIncomingCall` é o sinal de "o interfone está tocando" (já fazia parte da entidade).
* `IncomingCallListener` (`features/devices/presentation/widgets/`) observa `deviceStatusProvider(deviceId)` e reage à transição desse campo.
* Quando `hasIncomingCall` vira `true`:
  * uma notificação do sistema é disparada por `IncomingCallNotificationService` (`features/devices/data/services/`, usa o pacote `flutter_local_notifications`);
  * uma tela cheia de chamada (`IncomingCallPage`) abre, com som/vibração em loop e botões Atender/Recusar.
* No Android isso exige `POST_NOTIFICATIONS` no `AndroidManifest.xml` e core library desugaring habilitado em `android/app/build.gradle.kts` (`isCoreLibraryDesugaringEnabled = true` + dependência `coreLibraryDesugaring`) — ambos já configurados.

### Limitações atuais (por design, não são bugs)

* Atender e Recusar apenas dispensam a tela; não existe canal de áudio real ainda (isso é Fase 3).
* O listener só reage enquanto a `DeviceDetailPage` daquele dispositivo está montada — ainda não há um watcher global cobrindo todas as telas do app (exigiria um provider reativo de "todos os dispositivos", que não existe hoje).
* Com o app totalmente fechado (killed), não há como acordar o app sem push remoto de um backend. Isso é Fase 4 e não está implementado; a notificação local só funciona com o processo do app vivo (primeiro ou segundo plano).
* `LocalDeviceConnectionRepository.simulateIncomingCall(deviceId)` é um hook **debug-only** (fora do contrato `DeviceConnectionRepository`) para testar esse fluxo sem hardware — pulsa `hasIncomingCall` por 20s. Só é exposto na UI em `kDebugMode`, via botão no app bar de `DeviceDetailPage`. Não reutilizar esse padrão para simular outros dados fictícios fora de depuração.

### Falta fazer

* [ ] Watcher global de chamada recebida, independente da tela do dispositivo estar aberta.
* [ ] Emitir `hasIncomingCall` de verdade a partir do evento `RING_DETECTED` do protocolo (Fase 2) — o evento já está modelado em `DeviceEventType.ringDetected`, falta a ponte entre ele e `DeviceStatus.hasIncomingCall`/`IncomingCallListener`.
* [ ] Ligar Atender/Recusar a um canal de áudio real (Fase 3).
* [ ] Push notification (FCM/APNs) para acordar o app fechado (Fase 4) — reaproveitar `IncomingCallNotificationService` para renderizar a notificação quando o payload remoto chegar.
* [ ] Fazer a reação a `RING_DETECTED` respeitar `DeviceSettings.calls`/`quietHours` (hoje sempre toca, independente das preferências salvas) — ver seção 25.

---

# 20. Firmware / OTA

O protocolo v1.1 já define a arquitetura de OTA (`docs/communication-protocol.md` §29): **AWS IoT Jobs + S3 + firmware assinado + rollback via partições OTA do ESP32**. O InterApp **não baixa firmware nem envia manualmente para o dispositivo** — ele só consulta/solicita/acompanha através do backend.

```text
InterApp
   │  (consultar versão / solicitar OTA / acompanhar status)
   ▼
AWS application backend
   │
   ▼
AWS IoT Jobs + S3 (firmware assinado)
   │
   ▼
InterBridge
   │
   ├── valida integridade/assinatura
   ├── instala em partição inativa
   └── reinicia + self-test (rollback automático em falha)
```

Eventos relevantes já modelados em `DeviceEventType`: `otaStarted`, `otaCompleted`, `otaFailed`. **AWS IoT Jobs é a fonte autoritativa do estado do job** — o app não deve inventar seu próprio estado de progresso.

**Esta tarefa deliberadamente não implementou UI nem backend de OTA** (nem a interface de `DeviceBackendRepository` ganhou métodos de OTA) — ver `docs/APP_COMMUNICATION_STATUS.md`. É um corte de escopo consciente: OTA depende de decisões de infraestrutura (bucket S3, pipeline de assinatura, Jobs) que não fazem parte desta integração inicial de protocolo. Não implementar OTA antes de existir esse backend.

---

# 21. Design e identidade visual

O aplicativo utiliza uma identidade visual azul.

Tema atualmente configurado em:

```text
lib/app/app.dart
```

Principais referências:

* primária: `#1246A8`;
* fundo: `#F3F7FF`;
* navegação: azul-claro com indicador azul.

A interface deve priorizar:

* simplicidade;
* legibilidade;
* operação rápida;
* feedback claro;
* estados de conexão evidentes;
* ações críticas claramente identificadas.

A abertura da porta deve ser visualmente reconhecível como uma ação importante.

---

# 22. Estado de desenvolvimento

O projeto está sendo desenvolvido como um produto real, não apenas como um exercício de Flutter.

O objetivo é aprender Flutter/Dart durante o desenvolvimento enquanto se mantém uma arquitetura profissional e evolutiva.

O desenvolvimento deve privilegiar:

* código simples;
* separação de responsabilidades;
* testes;
* commits pequenos;
* documentação;
* interfaces bem definidas;
* evitar overengineering;
* evitar dependências desnecessárias;
* não implementar infraestrutura antes de existir uma necessidade real.

---

# 23. Regra importante para futuros agentes/colaboradores

Antes de alterar a arquitetura:

1. Ler este `PROJECT_CONTEXT.md`.
2. Inspecionar o código existente.
3. Verificar se já existe uma abstração para o problema.
4. Reutilizar os padrões existentes.
5. Não criar uma segunda implementação da mesma responsabilidade.
6. Não introduzir dados fictícios apenas para fazer uma tela parecer pronta.
7. Não acoplar a UI ao hardware.
8. Não assumir Bluetooth, Wi-Fi, MQTT ou outra tecnologia sem decisão explícita do projeto.
9. Não adicionar Supabase ou backend apenas por conveniência enquanto a funcionalidade puder permanecer local.
10. Executar `flutter analyze` e `flutter test` após mudanças relevantes.
11. Documentar código novo/alterado com comentários `///` (dartdoc) no momento em que ele é escrito — classes, métodos e campos não óbvios explicando o *porquê*, não só repetindo o nome. Não deixar para depois: acumular código sem documentação obriga uma varredura gigante mais tarde (já aconteceu — ver `git log`) em vez de manter o hábito a cada mudança.

---

# 24. Roadmap

## Fase 1 — Aplicativo base

* [x] Projeto Flutter
* [x] Feature First
* [x] Tema
* [x] Riverpod
* [x] GoRouter
* [x] Cadastro local de dispositivos
* [x] Perfil local
* [x] Discador
* [x] Favoritos por dispositivo
* [x] Estrutura inicial de compartilhamento
* [x] Separação `InterBridgeDevice` / `DeviceStatus`
* [x] Contrato `DeviceConnectionRepository`
* [x] Provider de status do dispositivo
* [x] Implementação local de conexão/status
* [x] Reação local a chamada recebida (notificação + tela de chamada, sem hardware real — ver seção 19)
* [x] `DeviceSettings` por dispositivo: modelo, persistência local, provider e tela de configurações (ver seção 25)
* [x] Modelos de domínio do protocolo v1.1: `DeviceCommand`/`DeviceCommandResult`/`DeviceProtocolError`/`DeviceEvent`/`IntercomState`, `DeviceStatus` alinhado ao Device Shadow (ver seção 26)
* [x] Contratos `DeviceBackendRepository`/`AuthRepository` + stubs honestos (`LocalDeviceBackendRepository`/`LocalAuthRepository`, nunca fingem sucesso)
* [x] Fluxo `OPEN_DOOR` real na UI: máquina de estados idle/sending/accepted/completed/failed/rejected/timedOut, sem duplo-toque, sem reenvio automático (ver seção 26)
* [x] Alinhamento dos modelos/parsers com o contrato oficial v1: timestamps de comando em epoch segundos, 18 códigos de erro, vocabulário de `intercom_state`, formato do QR (`interbridge://claim?v=1&...`) — ver seção 26, "Alinhamento com o contrato v1"
* [x] Onboarding de novo InterBridge (BLE primário + QR/manual fallback): `OnboardingCoordinator` (máquina de estados única, 17 fases), `AddInterBridgePage`, contratos `BleOnboardingTransport`/`OnboardingClaimRepository` (stub honesto em produção, mock em debug), `SetupCode`, análise de eventos (`OnboardingAnalytics`) — substitui a arquitetura anterior de `ProvisioningState`/`ProvisioningRepository`/`ProvisioningTransport`/`PairingController`/`PairingPage` (ver seção 13)

## Fase 2 — Primeiro hardware

* [x] Definir protocolo de comunicação — `docs/communication-protocol.md` v1.1 (arquitetura AWS IoT Core); falta confirmar a decisão Supabase vs. AWS do backend de aplicação (ver seção 15)
* [ ] Definir hardware final/protótipo
* [ ] Definir interface elétrica com o interfone
* [ ] Implementar o backend de aplicação AWS real (Cognito/API/Lambda) + `RemoteDeviceBackendRepository`
* [ ] Validar/implementar BLE real (`BleOnboardingTransport`) — confirmar compatibilidade com ESP-IDF Unified Provisioning/Protocomm Security 1 (versão pinada ao firmware) antes de escolher pacote
* [ ] Scanner de QR real (hoje o fallback de QR em `AddInterBridgePage` usa entrada manual do payload) — confirmar antes o formato de serialização do QR de `setup_code`
* [ ] Ativar `CloudDeviceConnectionRepository` como implementação padrão de `deviceConnectionRepositoryProvider`
* [ ] Pareamento de verdade (ponta a ponta)
* [ ] Descoberta/conexão local
* [ ] Comunicação básica
* [ ] Ler status real
* [ ] Emitir `hasIncomingCall` de verdade a partir do evento `RING_DETECTED` (ver seção 19)
* [ ] Detectar `NetworkPresence` real (rede local vs. remota) para `DeviceSettings.calls`
* [ ] Fazer `IncomingCallListener`/`IncomingCallNotificationService` respeitarem `DeviceSettings` (modo de alerta por presença, horário silencioso) em vez de sempre tocar
* [ ] Comando de abertura de porta funcionando de ponta a ponta (hoje a UI já existe, falta o backend/hardware real)
* [ ] Primeiro teste do fluxo completo

## Fase 3 — Áudio

* [ ] Captura do áudio do interfone
* [ ] Reprodução no aplicativo
* [ ] Áudio bidirecional
* [ ] Controle de chamadas
* [ ] Tratamento de latência/perda de conexão

## Fase 4 — Cloud

* [ ] Autenticação
* [ ] Usuários
* [ ] Dispositivos remotos
* [ ] Favoritos remotos
* [ ] Eventos
* [ ] Compartilhamento
* [ ] Permissões
* [ ] Realtime
* [ ] Push notifications
* [ ] `UserDeviceSettings` (preferências por usuário, além de `DeviceSettings` por dispositivo — ver seção 25)

## Fase 5 — Produto

* [ ] Pairing simplificado
* [ ] OTA (UI + `DeviceBackendRepository` de OTA + AWS IoT Jobs/S3 — nenhum código de OTA existe ainda, ver seção 20)
* [ ] Telemetria
* [ ] Diagnóstico
* [ ] Logs
* [ ] Recuperação de falhas
* [ ] Autenticação biométrica para abertura de porta (`DeviceSettings.requireDeviceAuthenticationToOpenDoor`)
* [ ] Segurança de produção
* [ ] Preparação para publicação nas lojas
* [ ] Infraestrutura de produção
* [ ] Monitoramento

---

# 25. DeviceSettings — configurações por InterBridge

Cada InterBridge tem suas próprias configurações de comportamento, independentes das de outros dispositivos cadastrados.

## Visão geral

Hoje `DeviceSettings` guarda só preferências locais do app — nada aqui comunica com hardware real. A persistência é local (`shared_preferences`), seguindo o mesmo padrão de repository já usado no resto do projeto, para que uma futura migração para backend não exija reescrever a tela.

## Modelo de domínio

Em `features/devices/domain/entities/device_settings.dart`:

* `DeviceSettings` — a raiz: `calls` (`DeviceCallSettings`), `quietHours` (`QuietHoursSettings`), `confirmBeforeOpeningDoor` (bool), `requireDeviceAuthenticationToOpenDoor` (bool).
* `NetworkPresence` — enum `{localNetwork, remoteNetwork}`. Não assume que "conectado a algum Wi-Fi" signifique "em casa"; é só o conceito de domínio para presença — a detecção real ainda não existe (Fase 2).
* `CallAlertMode` — enum `{none, ringOnly, notificationOnly, ringAndNotification}`, com getters `includesRing`/`includesNotification` e o construtor `CallAlertMode.from(ring:, notification:)`. Substitui os três booleans soltos que uma modelagem ingênua de "receber ligação/notificação/chamada fora da rede" teria.
* `DeviceCallSettings` — um `CallAlertMode` por zona de rede (`localNetworkAlertMode`, `remoteNetworkAlertMode`). `remoteNetworkAlertMode == none` já expressa "não receber chamadas fora da rede local", sem precisar de um bool redundante.
* `QuietHoursSettings` — `enabled`, `start`/`end` (`ClockTime`), `weekdays` (`Set<int>`, 1 = segunda ... 7 = domingo, igual a `DateTime.monday`..`DateTime.sunday`), `behavior` (`QuietHoursBehavior`).
* `QuietHoursBehavior` — enum `{blockAll, silentNotificationOnly}`.
* `ClockTime` — par hora/minuto próprio, deliberadamente independente de `TimeOfDay`/Flutter, para manter a camada de domínio livre de framework (mesmo padrão das outras entidades de `devices/domain`). A tela converte para/de `TimeOfDay` ao abrir o seletor de horário.

Todas essas classes têm `copyWith` (edições imutáveis a partir da UI) e `toMap`/`fromMap`. Diferente de `InterBridgeDevice`/`Favorite` (string tab-separated), `DeviceSettings` serializa como `Map` → JSON, porque tem estrutura aninhada, enums e um `Set` — um formato tab-separated ficaria ilegível e frágil para esse formato.

## Persistência

`DeviceSettingsRepository` (contrato) + `LocalDeviceSettingsRepository` (`features/devices/data/repositories/`), seguindo o mesmo padrão de `DeviceConnectionRepository`/`LocalDeviceConnectionRepository`: a UI depende só da abstração.

Persistido em `shared_preferences` sob a chave `device_settings_<deviceId>`, isolado por dispositivo (mesmo padrão de `favorites_<deviceId>`). Se não houver nada salvo, ou o valor salvo estiver corrompido, `get()` devolve `DeviceSettings()` (valores padrão) em vez de lançar erro.

## Provider

Em `features/devices/presentation/providers/device_settings_provider.dart`:

* `deviceSettingsRepositoryProvider` (em `devices_providers.dart`) expõe o repository, tipado pelo contrato abstrato.
* `DeviceSettingsController` — `AsyncNotifier<DeviceSettings>` com family por `deviceId`. `build()` carrega do repository; `updateSettings(updater)` aplica a alteração, atualiza o `state` na hora (a UI responde sem esperar o disco) e persiste; `reset()` volta para `DeviceSettings()` padrão.
* `deviceSettingsProvider` — `AsyncNotifierProvider.family<DeviceSettingsController, DeviceSettings, String>`, consumido pela tela como `AsyncValue` via `.when(...)`, igual ao `deviceStatusProvider`.

A tela nunca acessa `LocalDeviceSettingsRepository`/`shared_preferences` diretamente.

## Tela

`features/devices/presentation/pages/device_settings_page.dart`, aberta pelo ícone de engrenagem no app bar de `DeviceDetailPage`.

Seções (cada uma um `Card`):

* **Chamadas** — dois `SwitchListTile` ("Receber ligação"/"Receber notificação") que editam `calls.localNetworkAlertMode` via `CallAlertMode.from`.
* **Silencioso** — liga/desliga, horário (`showTimePicker`, convertido de/para `ClockTime`), dias da semana (`FilterChip`s), comportamento (`SegmentedButton` com as duas opções de `QuietHoursBehavior`). Os controles de horário/dias/comportamento só aparecem quando o modo silencioso está ligado.
* **Presença** — mostra o modo local (somente leitura, editado na seção Chamadas) e um `DropdownButton` para escolher o `CallAlertMode` da rede remota.
* **Porta** — dois `SwitchListTile` independentes (confirmar abertura / exigir autenticação do aparelho). A autenticação biométrica em si **não está implementada** — o campo só reserva o comportamento.
* **Dispositivo** — Wi-Fi / Firmware / Diagnóstico / Reiniciar: itens de lista que mostram um snackbar "disponível quando o InterBridge estiver conectado" ao toque (mesmo padrão do botão verde do discador). Não fazem nada de verdade ainda.
* **Avançado** — "Redefinir configurações": única ação realmente funcional dessa seção; volta as configurações locais desse dispositivo para o padrão (com confirmação). Não reseta nenhum hardware, porque não existe hardware conectado ainda.

## O que ainda não está implementado

* Detecção real de `NetworkPresence` (saber se o celular está na rede do InterBridge) — depende do hardware/protocolo (Fase 2).
* `DeviceSettings.calls`/`quietHours` ainda não são **consumidos** por `IncomingCallListener`/`IncomingCallNotificationService` — hoje eles só ficam salvos; a lógica de checar as configurações antes de tocar/notificar ainda precisa ser plugada na feature de chamada recebida (seção 19).
* Autenticação biométrica/Face ID para abrir a porta.
* Registro da ação de abertura no histórico de eventos (seção 19).
* Wi-Fi, firmware, diagnóstico e reinicialização reais do dispositivo.
* `UserDeviceSettings` (ver abaixo).

## Separação futura: DeviceSettings vs. UserDeviceSettings

`DeviceSettings` é **do dispositivo**, compartilhado por todos que têm acesso a ele (ver seção 14, Compartilhamento). Quando o compartilhamento existir de verdade, algumas preferências deixarão de fazer sentido como globais — por exemplo, uma pessoa silenciar o próprio celular sem silenciar para todo mundo que usa o mesmo InterBridge. Essas preferências devem virar uma futura entidade `UserDeviceSettings`, ligada a `(userId, deviceId)`, sem se misturar com `DeviceSettings`. Não implementar `UserDeviceSettings` antes de existir autenticação/usuários (Fase 4).

---

# 26. Protocolo de comunicação (InterBridge Communication Protocol v1.1)

O protocolo de comunicação entre InterApp, backend e InterBridge está definido em `docs/communication-protocol.md` — **fonte da verdade, não redefinida aqui**. Como o InterApp implementa/consome esse protocolo está em `docs/communication-integration.md`. O status de cada área está em `docs/APP_COMMUNICATION_STATUS.md`. Esta seção é um resumo de navegação, não substitui nenhum dos três.

## Arquitetura cloud

```text
InterApp
    ↓ HTTPS autenticado / application APIs
AWS application backend (Cognito / API / Lambda)
    ↓
AWS IoT Core
    ↓ MQTT/TLS, X.509/mTLS
InterBridge
```

O app **nunca** conecta em AWS IoT Core diretamente e **nunca** guarda certificado X.509 permanente do dispositivo — só o backend e o InterBridge participam desse canal.

## Caminho direto app ↔ dispositivo

A única comunicação direta definida no protocolo v1 é **BLE, exclusivamente para provisioning/recovery** (feature `pairing`, seção 13). Comunicação local via HTTPS/WebSocket na mesma LAN é mencionada como possibilidade futura, mas explicitamente **não definida** e **não implementada**.

## Separação de autenticação

```text
humano  → Cognito/backend de aplicação (abstraído por AuthRepository — ainda não implementado de verdade)
device  → X.509/mTLS contra AWS IoT Core (o app nunca vê essas credenciais)
```

`AuthRepository`/`LocalAuthRepository` (`features/auth/`) são novos nesta tarefa. Não têm relação com o "perfil" local já existente (`features/profile/`, só um nome digitado) — são conceitos diferentes que continuam separados.

## Claim (associação de propriedade)

QR = `device_id` (não é segredo) + `claim_code` (segredo de posse, single-use), no formato `interbridge://claim?v=1&device_id=ib-<32 hex minúsculos>&claim_code=<segredo>` (`docs/communication-protocol.md` §4). Modelado em `features/pairing/domain/entities/device_claim.dart`: `parseDeviceClaimQrPayload` valida scheme/host/versão/formato do `device_id`/presença do `claim_code`/parâmetros obrigatórios duplicados, sem nunca lançar exceção (entrada inválida vira `null`). `claim_code` nunca aparece em `toString()` e não deve ser persistido depois de um claim bem-sucedido. `DeviceBackendRepository.claimDevice` é a operação de backend correspondente — hoje sempre retorna "backend indisponível".

## Provisioning (pareamento)

Ver seção 13 (Pairing) para o detalhe completo da arquitetura (`ProvisioningRepository`/`ProvisioningTransport`/`StubProvisioningRepository`/`PairingController`/`PairingPage`).

## Controle (comandos)

`OPEN_DOOR` e `RESTART` são os comandos v1. `ANSWER_CALL`/`REJECT_CALL`/`END_CALL` estão reservados no protocolo para chamada/áudio futuros — modelados em `DeviceCommandType` para que um resultado que os referencie não quebre o app, mas **nunca oferecidos na UI**.

O botão "Abrir porta" (`_OpenDoorCard` em `device_detail_page.dart`) já usa a máquina de estados real:

```text
idle → sending → accepted → completed / failed / rejected / timedOut
```

via `DeviceCommandController` (`features/devices/presentation/providers/device_command_provider.dart`). Uma resposta HTTP `200` nunca é tratada como sucesso — só `status == completed` é. `timedOut` nunca é reenviado automaticamente. Um segundo toque enquanto uma solicitação está em andamento é ignorado (guard por `isBusy`). Hoje toda tentativa termina em `rejected`/`NOT_PROVISIONED` (via `LocalDeviceConnectionRepository`) porque não há dispositivo/backend real.

`RESTART` está modelado no contrato mas sem UI dedicada — o protocolo nota que `ACCEPTED` pode chegar antes do reboot de verdade, e só a reconexão é o sinal autoritativo de conclusão, o que exige um backend real para ter sentido. Continua atrás do placeholder "Reiniciar" em `DeviceSettingsPage`.

`issued_at`/`expires_at` no envelope do comando são **epoch Unix em segundos** (inteiro, não ISO-8601) — `DeviceCommand.toJson`/`fromJson` já convertem certo via `dateTimeToEpochSeconds`/`epochSecondsToDateTime` (`core/protocol/protocol_constants.dart`). Esses timestamps são **autoritativos do backend**: o app nunca os define, só contribui a intenção do comando e o `command_id` (idempotência) — o relógio do celular nunca é tratado como autoridade de segurança.

`DeviceProtocolError` cobre os 18 códigos v1 (`INVALID_PAYLOAD`, `PAYLOAD_TOO_LARGE`, `UNSUPPORTED_PROTOCOL_VERSION`, `UNKNOWN_COMMAND`, `COMMAND_NOT_ALLOWED`, `COMMAND_EXPIRED`, `CLOCK_NOT_TRUSTWORTHY`, `INVALID_TIMESTAMP`, `DEVICE_BUSY`, `NOT_PROVISIONED`, `WIFI_UNAVAILABLE`, `CLOUD_UNAVAILABLE`, `DOOR_OUTPUT_FAILURE`, `OTA_DOWNLOAD_FAILED`, `OTA_VALIDATION_FAILED`, `OTA_INSTALL_FAILED`, `PROVISIONING_FAILED`, `INTERNAL_ERROR`) + `unknown` de fallback. Uma primeira versão desta integração só tinha 13 desses códigos — corrigido nesta tarefa de alinhamento. Cada erro também tem um `origin` (`device`/`backend`/`connectivity`) — classificação só do lado do app para diagnóstico/tratamento, sem alterar os códigos do contrato.

## Status

`DeviceStatus` foi revisado para refletir o que o backend consolida do Device Shadow (`docs/communication-protocol.md` §22-23): `firmwareVersion`, `hardwareVersion`, `intercomState`, `wifiRssi`, `uptime`, `isProvisioned`, além de `isOnline`/`lastSeen`/`hasIncomingCall`/`errorMessage` que já existiam. Campos removidos por não corresponderem ao protocolo real: `batteryLevel`, `connectionType`/`DeviceConnectionType`, `wifiName` (nenhum estava em uso na UI).

`isOnline` **nunca** é inferido localmente por heartbeat — no protocolo real ele vem de eventos de lifecycle/connectivity do AWS IoT, consolidados pelo backend; `DeviceStatus.fromReportedShadow` recebe `isOnline` como parâmetro separado do mapa do shadow por causa disso.

`IntercomState` reconhece os cinco valores definidos pelo protocolo (`docs/communication-protocol.md` §22.1): `IDLE`, `RINGING`, `OFF_HOOK`, `IN_CALL`, `ERROR`. Continua sendo um wrapper aberto (não um enum fechado) — não porque o vocabulário seja desconhecido (agora é), mas porque um valor fora desses cinco precisa virar um estado "desconhecido" seguro preservando a string bruta, em vez de quebrar a interface (`IntercomState.isKnown`).

`health_interval_s`/`ring_timeout_ms`/`door_open_duration_ms`/`audio_volume` são configuração do Device Shadow **desired**, modelada separadamente em `DeviceHardwareConfig` — nunca misturada com `DeviceSettings` (preferências do app/usuário). Ver seção 25.

## Eventos

Ver seção 19.

## OTA

Ver seção 20.

## Áudio

Ver seção 18. Fora de escopo, não implementado.

## LAN local

Ver seção 6 e `docs/communication-protocol.md` §27.1. `DeviceConnectionRepository` já comporta uma futura `LocalLanDeviceConnectionRepository` ao lado de `CloudDeviceConnectionRepository` sem mudar telas — nenhuma das duas está implementada além da local de protótipo.

## Segurança

O que o app nunca deve guardar/logar (chave privada permanente, certificado X.509 permanente, credenciais administrativas AWS, `claim_code` após uso, PoP do BLE, senha de Wi-Fi, material temporário de Fleet Provisioning) está detalhado em `docs/communication-integration.md` §3. Reforçado no código: `DeviceClaim.toString()` redige o `claim_code`; senha de Wi-Fi só existe em memória durante o fluxo de pareamento.

O protocolo **proíbe** factory reset remoto (`docs/communication-protocol.md` §9) — por isso não existe (e não deve existir) um botão de "Factory Reset remoto" no app. "Redefinir configurações" em `DeviceSettingsPage` só reseta preferências locais do app, nunca o hardware — isso já era verdade antes desta tarefa e continua sendo.

## Conflito descoberto: Supabase vs. AWS

Ver seção 15 para o detalhe completo. Resumo: a seção 15 deste documento apontava Supabase como candidato de backend, escrita antes do protocolo v1.1 existir. O protocolo exige AWS IoT Core para a comunicação com o dispositivo — isso não é compatível com "Supabase como backend único". O conflito está documentado, não resolvido silenciosamente; falta uma decisão explícita de quem define a arquitetura do projeto.

## Alinhamento com o contrato v1 (correção pós-integração)

A integração inicial do protocolo (o que virou a seção 26 original) tinha três imprecisões, corrigidas numa tarefa de alinhamento subsequente, antes da Fase 1 AWS:

* **Vocabulário de `intercom_state`** — antes só `"IDLE"` estava confirmado; agora são os 5 valores definidos (`IDLE`/`RINGING`/`OFF_HOOK`/`IN_CALL`/`ERROR`, §22.1).
* **Formato do QR code** — antes um placeholder JSON; agora o scheme `interbridge://claim?v=1&device_id=...&claim_code=...` (§4).
* **Lista de códigos de erro** — antes 13 códigos; agora os 18 do contrato oficial (faltavam `PAYLOAD_TOO_LARGE`, `COMMAND_EXPIRED`, `CLOCK_NOT_TRUSTWORTHY`, `INVALID_TIMESTAMP`, `PROVISIONING_FAILED`).
* **Timestamps do comando** — antes o exemplo em `docs/communication-protocol.md` mostrava ISO-8601 para `issued_at`/`expires_at`; o wire protocol real usa epoch Unix em segundos (`timestamp` dos *eventos* continua ISO-8601 UTC, isso não mudou).

Essa correção **não** ativou nenhuma integração real nova — só alinhou modelos/parsers/testes ao contrato. `CloudDeviceConnectionRepository` continua fora de uso (`LocalDeviceConnectionRepository` é a implementação ativa); nenhum SDK AWS/Cognito/cliente MQTT foi adicionado; nenhum scanner de QR/câmera foi adicionado.

## Estado de implementação

Ver `docs/APP_COMMUNICATION_STATUS.md` para a matriz completa por área. Nenhuma dependência AWS/BLE/QR real foi adicionada ao `pubspec.yaml` — tudo que existe hoje é contrato + stub honesto + modelo de domínio + testes.

## Testes

Novos em `test/`: `device_protocol_error_test.dart`, `device_command_result_test.dart`, `device_status_shadow_test.dart`, `device_event_test.dart`, `device_claim_test.dart`, `stub_provisioning_repository_test.dart`, `device_command_provider_test.dart`, `local_device_backend_repository_test.dart`, `cloud_device_connection_repository_test.dart`, `protocol_constants_test.dart`, `local_auth_repository_test.dart` — além de um novo grupo em `device_settings_test.dart` confirmando a separação `DeviceSettings`/`DeviceHardwareConfig`.

---

# 27. Princípio central do projeto

O InterApp deve ser tratado como **a interface digital de um dispositivo físico**, e não como um aplicativo isolado.

Sempre que uma funcionalidade nova for criada, pensar nas três camadas:

```text
┌─────────────────────────┐
│       InterApp          │
│       Flutter           │
└────────────┬────────────┘
             │
             │ contrato
             ▼
┌─────────────────────────┐
│    Device Runtime       │
│ providers / repositories│
└────────────┬────────────┘
             │
             │ comunicação
             ▼
┌─────────────────────────┐
│       InterBridge       │
│        Hardware         │
└────────────┬────────────┘
             │
             │
             ▼
┌─────────────────────────┐
│   Interfone / Porta     │
│       físico             │
└─────────────────────────┘
```

O objetivo final é que o usuário consiga pegar o celular, abrir o InterApp e interagir com seu interfone físico de maneira simples, segura e confiável, mesmo que toda a complexidade de comunicação, áudio, rede e hardware esteja escondida por trás dessa interface.
