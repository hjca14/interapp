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

O hardware específico e o protocolo final de comunicação ainda estão em desenvolvimento.

O aplicativo, portanto, **não deve assumir prematuramente uma tecnologia específica** como Bluetooth, Wi-Fi, MQTT ou WebSocket.

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
* Backend/cloud ainda não está implementado.
* Supabase Cloud é o candidato inicial para a futura camada de backend.
* O app já reage localmente a uma chamada recebida (`DeviceStatus.hasIncomingCall`): notificação do sistema + tela de chamada em tela cheia. Ver seção 19. Isso só funciona com o processo do app vivo; com o app fechado, ainda depende de push/backend (Fase 4).

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

# 6. Contrato de comunicação com o hardware

A comunicação entre o aplicativo e o InterBridge é abstraída através de:

```text
DeviceConnectionRepository
```

Esse contrato deverá definir operações relacionadas ao dispositivo, como:

* conexão;
* acompanhamento de status;
* abertura de porta;
* discagem;
* futuramente atendimento/desligamento de chamadas;
* outros comandos específicos do InterBridge.

A tela do aplicativo não deve conhecer detalhes do protocolo físico.

Conceitualmente:

```text
UI
 │
 ▼
Provider / Controller
 │
 ▼
DeviceConnectionRepository
 │
 ├── implementação local/protótipo
 │
 └── implementação real futura
      ├── Wi-Fi
      ├── Bluetooth
      ├── MQTT
      ├── WebSocket
      └── outra tecnologia
```

A implementação concreta poderá mudar conforme o hardware evoluir.

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
│   ├── constants/
│   ├── router/
│   │   └── app_router.dart
│   └── theme/
│
├── features/
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

# 13. Pairing

A feature `pairing` existe como base para o futuro processo de associação de um aplicativo a um InterBridge físico.

O fluxo final ainda não está definido.

Possíveis mecanismos futuros incluem:

* QR Code;
* código de pareamento;
* descoberta local;
* Bluetooth;
* Wi-Fi;
* combinação de métodos.

Não assumir uma tecnologia antes da definição do hardware.

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

O protótipo atualmente funciona localmente.

Quando o produto evoluir para múltiplos usuários/dispositivos, será necessária uma camada cloud.

O candidato inicial é **Supabase Cloud**, principalmente por oferecer:

* autenticação;
* PostgreSQL;
* Row Level Security;
* APIs;
* atualizações em tempo real;
* infraestrutura gerenciada.

A arquitetura deverá permitir trocar:

```text
LocalDevicesRepository
```

por uma implementação remota sem modificar a UI.

Conceitualmente:

```text
Flutter
   │
   ├── Auth
   ├── Device Repository
   ├── Favorites Repository
   └── Event Repository
             │
             ▼
          Supabase
```

Não criar um servidor próprio apenas por necessidade arquitetural enquanto o produto ainda estiver em protótipo/MVP.

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

O protocolo e os componentes responsáveis pelo áudio ainda precisam ser definidos durante o desenvolvimento do hardware.

A arquitetura do aplicativo deve permitir que a implementação seja adicionada futuramente sem reestruturar todo o projeto.

---

# 19. Eventos

O dispositivo deverá futuramente produzir eventos como:

* dispositivo conectado;
* dispositivo desconectado;
* chamada recebida;
* chamada atendida;
* chamada encerrada;
* porta aberta;
* erro;
* atualização de firmware;
* outros eventos relevantes.

A tela de resumo poderá apresentar eventos recentes.

No estado atual, **não inventar eventos**.

Quando não houver dados reais:

```text
Nenhum evento recebido
```

é preferível a mostrar eventos fictícios.

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
* [ ] Emitir `hasIncomingCall` de verdade a partir do hardware (Fase 2).
* [ ] Ligar Atender/Recusar a um canal de áudio real (Fase 3).
* [ ] Push notification (FCM/APNs) para acordar o app fechado (Fase 4) — reaproveitar `IncomingCallNotificationService` para renderizar a notificação quando o payload remoto chegar.

---

# 20. Firmware / OTA

Atualização remota de firmware é um objetivo futuro.

O fluxo esperado será aproximadamente:

```text
InterApp
   │
   ▼
Backend / distribuição de firmware
   │
   ▼
InterBridge
   │
   ├── valida firmware
   ├── instala
   └── reinicia
```

A implementação deverá considerar:

* autenticação;
* integridade do firmware;
* rollback;
* versão;
* compatibilidade;
* segurança contra firmware não autorizado.

Não implementar OTA antes de definir o hardware e o mecanismo de boot/atualização.

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

## Fase 2 — Primeiro hardware

* [ ] Definir hardware final/protótipo
* [ ] Definir interface elétrica com o interfone
* [ ] Definir protocolo de comunicação
* [ ] Pareamento
* [ ] Descoberta/conexão local
* [ ] Comunicação básica
* [ ] Ler status real
* [ ] Emitir `hasIncomingCall` de verdade a partir do hardware
* [ ] Comando de abertura de porta
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

## Fase 5 — Produto

* [ ] Pairing simplificado
* [ ] OTA
* [ ] Telemetria
* [ ] Diagnóstico
* [ ] Logs
* [ ] Recuperação de falhas
* [ ] Segurança de produção
* [ ] Preparação para publicação nas lojas
* [ ] Infraestrutura de produção
* [ ] Monitoramento

---

# 25. Princípio central do projeto

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
