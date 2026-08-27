# InterBridge — Contexto do Projeto

> **Atualização Fase 2C:** a Fase 2B DEV foi implantada/validada, incluindo usuário Cognito confirmado e criação atômica do primeiro Device com membership OWNER/ACTIVE. O app agora usa Cognito User Pool via Amplify (`USER_SRP_AUTH`) e access token para leitura das três rotas HTTPS de dispositivos. Refresh e armazenamento seguro são responsabilidade do Amplify. Não há Identity Pool nem acesso direto do app ao IoT Core. Outputs de ambiente entram exclusivamente por `--dart-define`; valores reais não são versionados. BLE, claim, comandos, MQTT, eventos e voz seguem adiados.

> **Atualização Fase 3:** a Fase 2D de comandos assíncronos permanece concluída e encerrada. A numeração detalhada de 3A (fundamentos), 3B (alertas remotos e chamada) e 3C (onboarding BLE real) está em [`docs/PHASE_3_ROADMAP.md`](docs/PHASE_3_ROADMAP.md). Áudio, compartilhamento e presença por rede continuam sem numeração definitiva.


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
* O backend não é mais uma pendência geral: Cognito, diretório e leitura de dispositivos, status, `PATCH` de `display_name` e a API assíncrona de comandos estão implantados em DEV. `DeviceBackendRepository` + `LocalDeviceBackendRepository` continuam ativos somente em providers genéricos de comandos/eventos ainda não migrados para transporte remoto; esse stub reporta `CLOUD_UNAVAILABLE` sem representar `HttpDeviceRepository` nem as APIs reais já usadas pelo app. Ver seção 26.
* **A seção 15 preserva uma decisão histórica que apontava Supabase como candidato. A arquitetura implantada usa AWS (Cognito/API/Lambda + AWS IoT Core); o registro antigo não deve ser interpretado como estado atual. Ver seção 26, "Conflito descoberto: Supabase vs. AWS".**
* O app já reage localmente a uma chamada recebida (`DeviceStatus.hasIncomingCall`): notificação do sistema + tela de chamada em tela cheia. Ver seção 19. Isso só funciona com o processo do app vivo; com o app fechado, ainda depende da futura integração push/backend, sem numeração definitiva no roadmap.
* O fluxo assíncrono de API para `OPEN_DOOR` e sua máquina de estados (`idle`/`sending`/`accepted`/`completed`/`failed`/`rejected`/`timedOut`) estão implementados. Um aceite HTTP confirma somente o recebimento pelo backend, não execução ou ação física. Como o firmware/hardware ainda mantém a capacidade física de abertura desabilitada, a tentativa aplicável termina de forma segura em rejeição, como `CAPABILITY_DISABLED` ou estado equivalente previsto pelo contrato; abertura física não foi validada. Ver seção 26.

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

Além de identidade (`InterBridgeDevice`) e estado (`DeviceStatus`), existem duas camadas de preferências: `DeviceNotificationPreferences`, remota por usuário autenticado + dispositivo, e `DeviceSettings`, local por instalação/dispositivo e restrita à porta.

Nenhuma das duas vem do hardware ou do Device Shadow. As preferências de alertas usam a API autenticada; as preferências da porta permanecem no `shared_preferences`, isoladas por `deviceId`. Ver seção 25.

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
 ├── LocalDeviceConnectionRepository (ativa neste provider) — sem transporte para hardware
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

1. A aba **Dispositivos** exibe os InterBridges acessíveis ao usuário, vindos do backend (`apiDevicesProvider`/`HttpDeviceRepository`), não de um cadastro local.
2. O dispositivo é adicionado pelo fluxo de pareamento/claim (seção 13), não por um formulário de nome — um formulário de nome só faz sentido para o legado local (`DeviceFormPage`/`InterBridgeDevice`), que este fluxo não usa mais.
3. O dispositivo tem um `device_id` próprio, gerado pelo backend.
4. O usuário pode editar seu **nome pessoal** (`display_name`) quando possui uma membership ACTIVE, seja seu papel OWNER, ADMIN ou MEMBER. O valor vem da `DeviceMembership` do usuário autenticado; não é propriedade física/global do Device e não altera o nome visto por outros usuários. Tela dedicada: `EditDeviceNamePage`, acessível a partir do ícone de edição em `ApiDeviceDetailPage`. Regras:
   * campo pré-preenchido com o `display_name` atual (vazio quando não há nome customizado, nunca com o texto de fallback);
   * limite confirmado de `kDeviceDisplayNameMaxLength` caracteres (60);
   * "Usar nome padrão" envia `display_name: null` para limpar o nome customizado — nunca uma string vazia;
   * sem atualização otimista: a tela espera a confirmação do repository antes de atualizar a UI, e falha recuperável preserva o texto digitado.
   * **Deliberadamente não há campo de cômodo/ambiente/localização interna**; `display_name` é somente o apelido pessoal do usuário para identificar o InterBridge.
5. Quando `display_name` está ausente, vazio ou ainda não carregado, toda a UI usa o fallback literal **"InterBridge"** (função `deviceDisplayName`, `api_device.dart`) — nunca `device_id`. O Resumo não mostra o identificador. Diagnóstico começa com o sufixo mascarado e só revela o ID completo, com cópia explícita, após ação do usuário.
6. Remover o dispositivo (transferência/exclusão de propriedade) **não está implementado** — adiado para uma PR própria de compartilhamento (seção 14).
7. Tocar em um dispositivo abre `ApiDeviceDetailPage`.
8. O detalhe possui as abas:

   * **Resumo** (nome pessoal editável, status online/offline, abertura de porta e eventos recentes; sem metadados técnicos ou de acesso)
   * **Discar**
   * **Favoritos**
9. O cadastro do dispositivo não depende de uma conexão física.
10. Eventos, status e firmware não são simulados.
11. Enquanto não houver conexão, a UI informa que está aguardando conexão/dados.

### Validação real do nome pessoal (Fase 3, DEV)

O `PATCH /v1/devices/{device_id}` e o hotfix correspondente do backend foram implantados em DEV; a atualização CloudFormation terminou em `UPDATE_COMPLETE`. No teste real do app Android, o nome `Casa` foi salvo e permaneceu após sair da tela e retornar. Isso valida ponta a ponta `app → API → DynamoDB → nova leitura`, incluindo edição, persistência e recarga de `display_name`.

Na primeira tentativa, o cold start da Lambda falhou e nenhuma escrita ocorreu. O backend foi corrigido e reimplantado; o reteste posterior funcionou. Esse incidente é histórico e não representa bloqueio atual.

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

Esta seção preserva a arquitetura e o scaffold app-side já preparados, não uma entrega BLE real. O transporte BLE de produção não foi iniciado; produção usa o stub honesto e somente o mock de debug percorre o fluxo.

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
                            └──────────────→ OnboardingClaimRepository → API real de claim futura
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

OWNER, ADMIN e MEMBER com membership ACTIVE podem editar o próprio
`display_name`; essa operação não é administração do Device e não afeta a
visão das outras memberships.

O compartilhamento ainda não está implementado.

---

# 15. Decisão histórica de backend

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

A aba **Resumo** de `DeviceDetailPage` já consome `deviceEventsProvider(deviceId)` (`features/devices/presentation/providers/device_events_provider.dart`), que carrega o histórico recente e escuta eventos ao vivo via `DeviceBackendRepository`. Para esse provider específico de histórico/eventos, a implementação ativa ainda é o stub `LocalDeviceBackendRepository`, que sempre devolve uma lista vazia — isso não descreve `HttpDeviceRepository`, as leituras/status reais nem a API assíncrona de comandos. Por isso a tela continua mostrando:

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

* Atender e Recusar apenas dispensam a tela; não existe canal de áudio real ainda (etapa futura, sem numeração definida).
* O listener só reage enquanto a `DeviceDetailPage` daquele dispositivo está montada — ainda não há um watcher global cobrindo todas as telas do app (exigiria um provider reativo de "todos os dispositivos", que não existe hoje).
* Com o app totalmente fechado (killed), não há como acordar o app sem push remoto de um backend. FCM/APNs ainda não está implementado; a notificação local só funciona com o processo do app vivo (primeiro ou segundo plano).
* `LocalDeviceConnectionRepository.simulateIncomingCall(deviceId)` é um hook **debug-only** (fora do contrato `DeviceConnectionRepository`) para testar esse fluxo sem hardware — pulsa `hasIncomingCall` por 20s. Só é exposto na UI em `kDebugMode`, via botão no app bar de `DeviceDetailPage`. Não reutilizar esse padrão para simular outros dados fictícios fora de depuração.

### Falta fazer

* [ ] Watcher global de chamada recebida, independente da tela do dispositivo estar aberta.
* [ ] Emitir `hasIncomingCall` de verdade a partir do evento `RING_DETECTED` do protocolo (Fase 2) — o evento já está modelado em `DeviceEventType.ringDetected`, falta a ponte entre ele e `DeviceStatus.hasIncomingCall`/`IncomingCallListener`.
* [ ] Ligar Atender/Recusar a um canal de áudio real (etapa futura, sem numeração definida).
* [ ] Push notification (FCM/APNs) para acordar o app fechado — o projeto Firebase ainda não foi criado e FCM não foi configurado; futuramente, reaproveitar `IncomingCallNotificationService` para renderizar a notificação quando o payload remoto chegar.
* [ ] Fazer a reação a `RING_DETECTED` respeitar `DeviceNotificationPreferences` (hoje sempre toca, independente das preferências salvas) — ver seção 25.

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
* [x] Scaffold app-side de onboarding (sem BLE real): `OnboardingCoordinator` (máquina de estados única, 17 fases), `AddInterBridgePage`, contratos `BleOnboardingTransport`/`OnboardingClaimRepository` (stub honesto em produção, mock em debug), `SetupCode`, análise de eventos (`OnboardingAnalytics`) — substitui a arquitetura anterior de `ProvisioningState`/`ProvisioningRepository`/`ProvisioningTransport`/`PairingController`/`PairingPage` (ver seção 13)

## Fase 2 — Primeiro hardware

* [x] Definir protocolo de comunicação — `docs/communication-protocol.md` v1.1 (arquitetura AWS IoT Core); falta confirmar a decisão Supabase vs. AWS do backend de aplicação (ver seção 15)
* [ ] Definir hardware final/protótipo
* [ ] Definir interface elétrica com o interfone
* [ ] Integrar os providers genéricos ainda locais de comandos/eventos por meio de uma implementação remota de `DeviceBackendRepository`; Cognito, diretório/status, nome pessoal e API assíncrona de comandos já existem em AWS
* [ ] Validar/implementar BLE real (`BleOnboardingTransport`) — confirmar compatibilidade com ESP-IDF Unified Provisioning/Protocomm Security 1 (versão pinada ao firmware) antes de escolher pacote
* [ ] Scanner de QR real (hoje o fallback de QR em `AddInterBridgePage` usa entrada manual do payload) — confirmar antes o formato de serialização do QR de `setup_code`
* [ ] Ativar `CloudDeviceConnectionRepository` como implementação padrão de `deviceConnectionRepositoryProvider`
* [ ] Pareamento de verdade (ponta a ponta)
* [ ] Descoberta/conexão local
* [ ] Comunicação básica
* [ ] Ler status real
* [ ] Emitir `hasIncomingCall` de verdade a partir do evento `RING_DETECTED` (ver seção 19)
* [ ] Avaliar presença por rede como evolução futura, sem solução ou contrato definidos
* [ ] Fazer `IncomingCallListener`/`IncomingCallNotificationService` respeitarem `DeviceNotificationPreferences` (os filtros ainda não são aplicados)
* [ ] Comando de abertura de porta funcionando de ponta a ponta (hoje a UI já existe, falta o backend/hardware real)
* [ ] Primeiro teste do fluxo completo

## Fase 3 — experiência do dispositivo e do usuário

Esta é a fase corrente, iniciada depois do encerramento da Fase 2D. A primeira entrega funcional foi o nome pessoal por membership, seguido pela reorganização de Resumo, Diagnóstico e Configurações.

O [roadmap canônico da Fase 3](docs/PHASE_3_ROADMAP.md) preserva o histórico e
define a sequência vigente. A Fase 3A está implementada: nome pessoal e
reorganização da experiência foram validados em DEV; alteração de senha tem
validação manual parcial; preferências GET/PATCH foram implantadas e validadas
em DEV, enquanto a UI de autosave ainda aguarda repetição manual. A Fase 3B
começa pela identidade Android/iOS `com.interbridge.app`, sem Firebase nesta
subfase. FCM, aplicação dos filtros e chamada continuam pendentes. A Fase 3C,
onboarding BLE real, ainda não começou.

## Trabalhos futuros sem numeração definitiva — áudio

* [ ] Captura do áudio do interfone
* [ ] Reprodução no aplicativo
* [ ] Áudio bidirecional
* [ ] Controle de chamadas
* [ ] Tratamento de latência/perda de conexão

## Trabalhos futuros sem numeração definitiva — cloud e colaboração

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
* [x] Diagnóstico de suporte inicial (ID sob ação explícita, hardware e estado de configuração amigável)
* [ ] Logs
* [ ] Recuperação de falhas
* [ ] Autenticação biométrica para abertura de porta (`DeviceSettings.requireDeviceAuthenticationToOpenDoor`)
* [ ] Segurança de produção
* [ ] Preparação para publicação nas lojas
* [ ] Infraestrutura de produção
* [ ] Monitoramento

---

# 25. Preferências do dispositivo

## Alertas remotos por usuário + dispositivo

O contrato final foi mergeado no **interBackend PR #21**: `GET` e `PATCH /v1/devices/{device_id}/notification-preferences`. O backend foi implantado em **DEV** (`InterBridge-Dev-ApiStack`, CloudFormation `UPDATE_COMPLETE`) e a integração foi validada ponta a ponta com uma chamada real do app: o app executou um `PATCH` real, a Lambda gravou e o item `notification_preferences` foi conferido diretamente no DynamoDB (`app → API → Lambda → DynamoDB`). `alert_mode: NOTIFICATION_ONLY` foi validado, assim como `quiet_schedule.enabled: false` — desativar os horários preserva (não apaga) dias, horários, timezone e comportamento previamente salvos, que reaparecem ao reativar.

`DeviceNotificationPreferences` contém `version`, um único `alertMode`, `quietSchedule` e `updatedAt`. O modo global compõe os switches de ligação e notificação. Os horários sem ligação usam dias ISO, `HH:mm`, timezone IANA e comportamento “Só notificação” ou “Bloquear tudo”. Ao ativar pela primeira vez, o app obtém o timezone IANA do aparelho sem localização; após salvar, preserva o timezone retornado pelo servidor e não o troca silenciosamente em viagens. As escolhas pertencem ao par usuário autenticado + dispositivo.

Android e iOS expõem o identificador atual por um `MethodChannel`, sem permissões de localização ou Wi-Fi. A implementação iOS está versionada, mas ainda não foi validada por build macOS ou em aparelho real.

As preferências de alertas saíram da tela geral de configurações do dispositivo e ganharam uma tela própria (`NotificationPreferencesPage`), aberta a partir de um único item "Notificações" em `DeviceSettingsPage` — abrir esse item é o que dispara o `GET` remoto; a tela geral nunca busca as preferências remotas só para montar seu resumo. A tela não tem mais botão "Salvar": todo campo válido inicia salvamento automático (debounce de 700ms), agrupando edições rápidas em um único PATCH, nunca enviando PATCH vazio ou repetindo um PATCH idêntico ao último confirmado. Só existe um PATCH em voo por vez; editar durante um PATCH em andamento não bloqueia os controles nem cancela a chamada em curso — a resposta confirma um novo "baseline" e, se o rascunho já mudou de novo nesse meio tempo, um único PATCH de acompanhamento é agendado com o delta restante, até convergir. Antes de cada PATCH, uma edição ainda não confirmada é gravada localmente (um "outbox" isolado por usuário autenticado + `device_id`, nunca contendo token/e-mail/senha/resposta bruta) para sobreviver ao encerramento do app; ao reabrir a tela, o app tenta reconciliar esse pendente com o servidor sem nunca sobrescrevê-lo às cegas em caso de conflito. A validação manual desse **novo** fluxo de autosave (em vez do antigo botão "Salvar") ainda está pendente até o próximo `flutter run` em aparelho real — o que foi validado em DEV acima cobre o contrato remoto (GET/PATCH/DynamoDB), não a UI de autosave em si. Conflito 409 nunca sobrescreve o servidor silenciosamente. Redefinir alertas envia os defaults contratuais; não altera porta, hardware ou Device Shadow.

## Preferências locais da porta

`DeviceSettings`, persistido por dispositivo em `shared_preferences`, contém somente `confirmBeforeOpeningDoor` e `requireDeviceAuthenticationToOpenDoor`. Registros antigos podem conter `calls`, `quietHours` e campos experimentais: o parser ignora essas chaves, preserva as duas preferências da porta e nunca migra dados legados ao backend. A redefinição local não chama a API.

FCM/Firebase não está configurado e esta integração apenas persiste escolhas: os filtros não são aplicados a `IncomingCallListener`, `IncomingCallNotificationService` ou ao fluxo atual. Chamada Android com app encerrado continua pendente; iOS vem depois. Áudio é uma frente separada de push. Presença por rede fica adiada como possibilidade futura, sem solução escolhida, detecção ou campos reservados.

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
humano  → Cognito/backend de aplicação (integração real usada pelo app; separada do AuthRepository legado)
device  → X.509/mTLS contra AWS IoT Core (o app nunca vê essas credenciais)
```

`AuthRepository`/`LocalAuthRepository` (`features/auth/`) foram introduzidos como abstração local nesta etapa histórica. A autenticação real do app usa Cognito e não deve ser confundida com esse stub nem com o "perfil" local (`features/profile/`, só um nome digitado); são conceitos diferentes que continuam separados.

## Alteração de senha (Fase 3, item 2)

Usuário autenticado que já sabe a senha atual pode trocá-la em **Ajustes → Alterar senha** (`ChangePasswordPage`, rota `/change-password`), fora das configurações de qualquer Device e sem depender de haver um Device cadastrado. É um recurso da conta, não de compartilhamento: não aparece em "Acesso e compartilhamento" (`device_settings_page.dart` permanece intocado).

A operação usa exclusivamente o Amplify Auth já existente — `Amplify.Auth.updatePassword(oldPassword:, newPassword:)`, numa única chamada que recebe a senha anterior e a proposta juntas — através de `AuthRepository.changePassword`, implementado por `CognitoAuthRepository` e testado com um `CognitoAuthGateway` fake (nenhum SDK AWS paralelo, nenhuma chamada HTTP própria, nenhum Lambda/endpoint novo). A validação local antes do envio é deliberadamente mínima (campos obrigatórios, confirmação idêntica, espaços nunca removidos silenciosamente) porque cadastro/redefinição também nunca validaram a política de senha localmente — o texto de política (`PasswordPolicyHint`, compartilhado pelas três telas) é só informativo; o Cognito continua a única autoridade sobre a política real. Em particular, o app **não** rejeita localmente uma nova senha igual ao texto digitado em "senha atual": o campo pode conter um erro de digitação, então só o Cognito — validando os dois valores na mesma chamada — pode confirmar que a senha atual está correta antes de decidir se a nova senha é aceitável.

**Teste real no Android com Cognito DEV mostrou que o serviço aceita `PreviousPassword`/`ProposedPassword` iguais** em vez de rejeitar — `updatePassword` retornou sucesso sem produzir mudança efetiva na senha. Por isso, ao contrário de uma suposição anterior, o app não pode alegar que o Cognito rejeita necessariamente senhas iguais. Como o app só sabe, antes da chamada, que o campo "senha atual" *pode* estar incorreto, essa igualdade nunca bloqueia o envio. Depois que `updatePassword` retorna sucesso, porém, isso confirma implicitamente que a senha atual informada era a verdadeira; só nesse momento — em `ChangePasswordController.submit`, depois do retorno do repository, nunca antes — a igualdade entre os dois valores enviados é tratada com segurança como "nenhuma mudança efetiva": o controller não reporta sucesso, não limpa os campos, não sai da tela e não invalida a sessão, apresentando em vez disso "A nova senha deve ser diferente da atual." como erro do campo de nova senha para nova tentativa. Uma falha remota (por exemplo, senha atual incorreta) nunca é substituída por essa checagem de igualdade — o mapeamento sanitizado existente permanece intacto nesse caso.

Erros ficam sanitizados em `AuthFailureKind` (`incorrectCurrentPassword`, `invalidPassword`, `rateLimited`, `notAuthenticated`, `sessionExpired`, `unavailable`, `unknown`) — nunca a exceção crua do Amplify/Cognito, nunca o texto da mensagem do Cognito e nunca a senha digitada; a classificação usa somente o tipo estruturado da exceção. Uma sessão expirada ou um token inválido durante a troca passa pelo mesmo `invalidateSession()` central já usado pelo cliente HTTP num 401, sem tentativa de reautenticação silenciosa; o redirecionamento ao login é o mesmo mecanismo de `redirect` do `GoRouter` já existente. "Alterar senha" nunca é confundido com "Esqueci minha senha" (`ForgotPasswordPage`): a ação "Não lembra sua senha?" explica que a recuperação por e-mail exige sair da sessão atual antes de chamar `signOut()`, em vez de duplicar o fluxo de recuperação.

Implementado e testado localmente (repository com fake gateway, controller Riverpod com `LocalAuthRepository`, widget). **Um cenário real já foi validado em Android contra o Cognito DEV** — senha atual correta com nova senha igual, confirmando o comportamento de aceitação descrito acima — mas os demais cenários (senha atual incorreta, nova senha fora da política, sessão expirada durante a troca, troca bem-sucedida com senha realmente nova) ainda não foram repetidos manualmente; **não considere o fluxo completo de alteração de senha validado ponta a ponta** até essa verificação adicional. Nenhuma mudança em `interBackend`, AWS CDK, User Pool ou política do Cognito.

## Claim (associação de propriedade)

QR = `device_id` (não é segredo) + `claim_code` (segredo de posse, single-use), no formato `interbridge://claim?v=1&device_id=ib-<32 hex minúsculos>&claim_code=<segredo>` (`docs/communication-protocol.md` §4). Modelado em `features/pairing/domain/entities/device_claim.dart`: `parseDeviceClaimQrPayload` valida scheme/host/versão/formato do `device_id`/presença do `claim_code`/parâmetros obrigatórios duplicados, sem nunca lançar exceção (entrada inválida vira `null`). `claim_code` nunca aparece em `toString()` e não deve ser persistido depois de um claim bem-sucedido. `DeviceBackendRepository.claimDevice` é a operação correspondente na abstração de onboarding; a implementação local desse fluxo específico hoje retorna "backend indisponível". Isso não descreve as APIs reais de autenticação, diretório, status, nome pessoal ou comandos.

## Provisioning (pareamento)

Ver seção 13 (Pairing) para o detalhe completo da arquitetura (`ProvisioningRepository`/`ProvisioningTransport`/`StubProvisioningRepository`/`PairingController`/`PairingPage`).

## Controle (comandos)

`OPEN_DOOR` e `RESTART` são os comandos v1. `ANSWER_CALL`/`REJECT_CALL`/`END_CALL` estão reservados no protocolo para chamada/áudio futuros — modelados em `DeviceCommandType` para que um resultado que os referencie não quebre o app, mas **nunca oferecidos na UI**.

O botão "Abrir porta" (`_OpenDoorCard` em `device_detail_page.dart`) já usa a máquina de estados real:

```text
idle → sending → accepted → completed / failed / rejected / timedOut
```

via `DeviceCommandController` (`features/devices/presentation/providers/device_command_provider.dart`). Uma resposta HTTP de aceite nunca é tratada como comprovação de abertura — só `status == completed` permitiria confirmar execução. `timedOut` nunca é reenviado automaticamente e um segundo toque durante a solicitação é ignorado (`isBusy`). O fluxo assíncrono de API existe; a capacidade física de abertura permanece desabilitada no firmware/hardware, portanto a tentativa aplicável termina de forma segura em rejeição como `CAPABILITY_DISABLED` ou estado equivalente do contrato. Nenhuma abertura física foi validada. Providers genéricos que ainda usam `LocalDeviceConnectionRepository` constituem um caminho local separado, não evidência de ausência do backend.

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

Naquele momento, essa correção **não** ativou integração nova; apenas alinhou modelos/parsers/testes ao contrato. `CloudDeviceConnectionRepository` continuou fora de uso naquele caminho genérico e não foram adicionados cliente MQTT nem scanner de QR/câmera. Desde então, Cognito, diretório/status, nome pessoal e a API HTTPS assíncrona de comandos foram implantados por integrações próprias; este registro histórico não substitui o estado atual.

## Estado de implementação

Ver `docs/APP_COMMUNICATION_STATUS.md` para a matriz completa por área. As integrações reais de Cognito e APIs HTTPS coexistem com contratos e stubs locais restritos a features ainda pendentes. BLE real, scanner QR, áudio, push, compartilhamento e capacidade física de abertura continuam não implementados.

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
