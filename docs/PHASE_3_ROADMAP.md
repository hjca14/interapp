# Roadmap canônico da Fase 3

Este documento é a fonte canônica da numeração e da ordem da Fase 3. A Fase
2D permanece concluída e encerrada. A antiga correção documental foi um
trabalho histórico de organização, não uma entrega funcional paralela à 3A.

Uma subfase só pode ser marcada como concluída quando o código estiver
mergeado, a CI estiver verde, a infraestrutura aplicável estiver implantada e
os testes reais exigidos estiverem documentados. Testes manuais não executados
permanecem explicitamente pendentes.

## Fase 3A — fundamentos da experiência

- [x] **3A.1 — Nome pessoal e experiência do dispositivo**
  - `display_name` por membership;
  - reorganização entre Resumo, Diagnóstico e Configurações;
  - validação ponta a ponta em DEV.
- [x] **3A.2 — Segurança da conta**
  - alteração de senha para usuário autenticado;
  - recuperação de senha preservada como fluxo separado;
  - implementação e testes automatizados concluídos;
  - validação manual no Cognito DEV permanece parcial: o cenário de senha nova
    igual à atual foi executado; senha atual incorreta, política inválida,
    sessão expirada e troca por senha realmente nova ainda não foram repetidos.
- [x] **3A.3 — Preferências de alertas**
  - `DeviceNotificationPreferences`, GET/PATCH reais e persistência por usuário
    e dispositivo;
  - horários sem ligação e autosave com debounce e outbox local;
  - backend DEV implantado e contrato validado ponta a ponta;
  - a UI reorganizada com autosave ainda aguarda repetição manual via
    `flutter run`;
  - preferências são persistidas, mas ainda não filtram pushes ou chamadas.

## Fase 3B — alertas remotos e chamada

- [x] **3B.1 — Identidade definitiva dos apps móveis**
  - `com.interbridge.app` no Android e iOS;
  - nome visível `InterBridge`;
  - entrega da PR 19;
  - nenhum Firebase configurado.
- [x] **3B.2 — Projeto Firebase DEV**
  - criar projeto separado de produção;
  - manter Analytics inicialmente desativado;
  - não habilitar Firestore, Firebase Auth, Hosting ou Functions sem necessidade;
  - cadastrar inicialmente somente Android.
- [x] **3B.3 — FlutterFire e FCM no Android**
  - projeto Firebase DEV `interbridge-dev`, plano Spark, `firebase_core`
    4.14.0, `firebase_messaging` 16.6.0 e `flutterfire configure` executado
    somente para Android;
  - `Firebase.initializeApp` isolado do bootstrap do Amplify/Cognito: uma
    falha de Firebase/FCM é capturada de forma sanitizada e nunca impede
    login, listagem de dispositivos ou o restante do app;
  - abstração estreita (`lib/core/push`) entre o app e o `firebase_messaging`
    — a UI não chama `FirebaseMessaging.instance` diretamente;
  - permissão de notificação solicitada pela API oficial apenas quando ainda
    não decidida, sem repetição, sem tratar recusa como erro fatal;
  - token inicial e renovação mantidos em memória; caminhos de recebimento
    em foreground, toque que abre o app em background e mensagem inicial
    (app encerrado) implementados; handler de background como função
    top-level com `@pragma('vm:entry-point')`, sem UI/provider/BuildContext
    e sem operação AWS;
  - token mantido somente em memória, internamente, nunca persistido nem
    enviado a analytics/AWS; nenhum getter público expõe o valor completo —
    o único diagnóstico de token em debug informa presença/ausência
    (`token_initial present=…`, `token_refresh present=…`), nunca o valor;
  - cadastro de token no backend continua fora do escopo desta subfase;
  - validado via testes automatizados com fakes; o recebimento real de push
    foi validado manualmente na Fase 3B.4.
- [x] **3B.4 — Validação direta do FCM**
  - validado em Android real com o projeto Firebase DEV `interbridge-dev` e
    o package `com.interbridge.app`, usando pushes de teste enviados pelo
    Firebase Console diretamente ao token FCM da instalação;
  - app em segundo plano: notificação visual apareceu no Android, o
    background handler executou, o toque na notificação abriu o app e
    `opened_app` foi registrado;
  - app em primeiro plano: `foreground` foi registrado com título e corpo
    presentes; nenhuma notificação visual local foi criada, conforme
    esperado nesta fase — a validação nesse caminho foi feita pelo
    diagnóstico/handler, não por uma notificação do sistema;
  - app encerrado: a mensagem foi recebida, o background handler executou,
    o toque iniciou uma nova execução do app e `initial_message` foi
    consumido;
  - `messageId` esteve presente nos três testes; a obtenção do token inicial
    funcionou;
  - nenhuma navegação funcional específica e nenhuma tela de chamada foram
    implementadas — fora de escopo desta subfase;
  - nenhum token foi cadastrado na AWS e nenhum sender AWS foi implementado
    neste teste — o cadastro do token foi endereçado em seguida pela Fase
    3B.5; o sender AWS continua pendente para a Fase 3B.6.
- [x] **3B.5 — Registro de instalações e tokens**
  - backend implementado no interBackend PR #23; integração do app implementada
    com `PUT`/`DELETE` autenticados e UUID v4 persistente por instalação;
  - token inicial, restauração/login e renovação convergem em um coordenador
    single-flight; logout solicitado remove a instalação antes do sign-out;
  - testes usam fakes e não acessam Firebase, Cognito ou AWS; token não é
    persistido, exposto à UI ou incluído em logs/erros;
  - validado ponta a ponta em DEV (`sa-east-1`), SHA
    `62a5a4d68e06f565e0118a900763a18485692516` (CI Flutter #104 aprovada;
    `dart format` com 9 arquivos ainda não formatados — checagem tolerante,
    não bloqueia a CI; `flutter analyze` sem problemas; `flutter test`: 552
    aprovados; build e instalação Android debug aprovados);
  - evidência E2E (sanitizada, sem tokens, hashes completos, UUIDs completos
    ou `user_id`): login autenticado gerou `PUT` e criou exatamente um item
    autoritativo `INSTALLATION` e um `CLAIM`; o item apresentou `ANDROID`,
    `FCM`, `com.interbridge.app` e `1.0.0+1`; um reinício completo do app
    preservou o mesmo `installation_id` e `created_at`, avançou `updated_at`
    e não criou duplicatas; o logout seguro removeu os dois itens (`DELETE`)
    antes de encerrar a sessão; um novo login recriou instalação e claim
    usando o mesmo `installation_id`;
  - sender FCM continua exclusivamente na 3B.6 e não houve mudança de firmware.
- [x] **3B.6 — Emissor FCM na AWS**
  - implantada e validada em DEV (`sa-east-1`): a cadeia
    `telemetry_ingestion → push_sender → FCM HTTP v1` executou com sucesso
    em teste real, com o sender registrando `membership_count=1`,
    `installation_count=1`, `sent_count=1`, `suppressed_count=0`,
    `invalid_token_count=0`, `temporary_failure_count=0`,
    `permanent_failure_count=0`, `auth_config_failure_count=0`; o FCM
    aceitou as mensagens;
  - o backend envia deliberadamente um payload `data-only` (sem bloco
    `notification`) com o contrato `push_contract_version`, `event_id`,
    `device_id`, `event`, `presentation_intent`, `occurred_at` — a
    apresentação local desse contrato é a entrega mínima da 3B.9 abaixo.
- [x] **3B.7 — Aplicação das preferências**
  - o backend já aplica `alert_mode` e `quiet_schedule` na decisão de
    enviar ou suprimir um evento; eventos suprimidos não são enviados ao
    FCM;
  - comportamento por rede local continua fora do escopo e reservado para
    uma possível V2.
- [x] **3B.8 — Simulador físico de toque no firmware**
  - botão/switch físico no ESP32;
  - publicar o evento definitivo (`RING_DETECTED` ou nome contratual
    equivalente), com `event_id` estável e fluxo MQTT real;
  - não criar atalho descartável fora do protocolo;
  - substituir futuramente o botão pelo detector real do interfone.
  - validada ponta a ponta em ESP32-C3 real até uma notificação Android: o
    teste final usou pull-down externo de aproximadamente 10 kΩ para GND e
    jumper momentâneo de 3V3 no GPIO4, não o Linker Button. O GPIO4 continua
    provisório e não constitui decisão de hardware de produção.
- [x] **3B.9 — Experiência de chamada no Android (validada em DEV para o
  escopo atual de apresentação de chamada/notificação — ver 3B.9f abaixo;
  áudio bidirecional, integração nativa de chamada e produção seguem fora
  de escopo)**
  - **3B.9a — notificação mínima (PR #22):** parser estrito, deduplicação,
    apresentação local e diagnósticos sanitizados implementados e validados
    por uma notificação `RING_DETECTED` real na cadeia ponta a ponta;
  - entrega mínima e isolada: reconhece e valida o payload `data-only`
    versão 1 do contrato `RING_DETECTED` (`lib/core/push/ring_detected_push_parser.dart`),
    deduplica por `event_id` (`ring_event_deduplicator.dart`, janela local
    de 60s, best-effort, não é fonte de verdade), e apresenta uma
    notificação local Android genérica ("Interfone tocando" / "Alguém
    chamou no interfone.") em foreground e background, aplicando
    `presentation_intent` (`RING_ONLY`/`RING_AND_NOTIFICATION` com som,
    canal `incoming_call`; `NOTIFICATION_ONLY` silenciosa, canal
    `ring_notification_silent`); reaproveita `IncomingCallNotificationService`,
    `PushNotificationService` e o background handler existentes — nenhuma
    arquitetura paralela;
  - payloads inválidos ou não suportados são rejeitados silenciosamente,
    sem apresentar notificação; diagnóstico debug sanitizado (`event_id`
    mascarado, contrato válido/inválido, `event`, `presentation_intent`,
    apresentado sim/não, motivo) — nunca título, corpo, `data`, token ou
    IDs completos;
  - "app encerrado" não é um cenário único: remover o app da lista de
    recentes (swipe) mantém o processo elegível para o Android acordar o
    background handler normalmente, e é o cenário validável por este
    trabalho. Forçar parada real (Configurações → Apps → Forçar parada, ou
    `adb shell am force-stop`) é diferente — o Android pode bloquear
    mensagens em segundo plano para o app até que o usuário o abra
    manualmente de novo; esse não é um cenário de entrega garantida e não
    deve ser tratado como equivalente ao swipe nem cobrado como validado
    aqui;
  - **3B.9b — tela interna e ações disponíveis:** o toque na notificação
    local preserva apenas uma intenção mínima validada, aguarda sessão válida
    e autorização do dispositivo, e então abre a rota interna. A tela carrega
    o nome pelo repositório autenticado, permite dispensar localmente e
    reutiliza integralmente o fluxo `OPEN_DOOR` quando disponível e habilitado
    por preferência local opt-in do dispositivo (desativada por padrão).
    Essa preferência controla somente a visibilidade no app e não concede
    autorização nem desabilita fisicamente o relé. “Atender”
    informa honestamente que o áudio ainda não está disponível e não envia
    comando nem cria uma chamada ativa;
  - **3B.9c — full-screen intent e comportamento sobre lock screen
    (implementação completa; validada manualmente em Android físico — ver
    3B.9f abaixo):**
    `RING_ONLY`/`RING_AND_NOTIFICATION` passam a usar categoria
    `CATEGORY_CALL` e `fullScreenIntent` no canal de chamada (renomeado
    para `incoming_call_v2` na 3B.9d abaixo, junto da mudança para toque
    contínuo — ver lá o motivo do versionamento). A decisão de
    pedir tela cheia é **incondicional** para esses dois intents — `present()`
    nunca consulta nenhuma checagem de acesso do SO para decidir isso, e o
    próprio Android aplica o fallback documentado para heads-up quando
    `USE_FULL_SCREEN_INTENT` não está concedido ou quando decide não abrir a
    tela (aparelho desbloqueado, app em uso etc.); `NOTIFICATION_ONLY` nunca
    recebe categoria de chamada nem full-screen, em nenhuma hipótese. Essa
    incondicionalidade é deliberada: `checkFullScreenIntentAccess()`
    (`lib/core/push/full_screen_intent_access.dart`, canal nativo
    `interapp/full_screen_intent`, distinto do plugin) fala com um handler
    registrado somente em `MainActivity`, sem nenhuma garantia de estar vivo
    quando um `RING_DETECTED` chega pelo isolate de background do FCM com o
    app em segundo plano/encerrado e o aparelho bloqueado — justamente o
    cenário que esta entrega existe para cobrir. Consultar essa checagem para
    decidir a apresentação do push faria a notificação silenciosamente nunca
    pedir tela cheia nesse cenário, degradando de forma sempre-`false` sem
    erro visível. Por isso `checkFullScreenIntentAccess()` e o canal nativo
    permanecem exclusivamente para alimentar o status informativo da
    `SecuritySettingsPage` — nunca para decidir se um push recebe full-screen;
  - o toque que abre a `IncomingCallPage` e o disparo automático do
    full-screen intent são literalmente o mesmo `PendingIntent`/payload
    (o plugin usa o mesmo intent de conteúdo para ambos), então foreground,
    background, cold start e o lançamento sobre a tela bloqueada convergem
    no mesmo `RingCallNavigationCoordinator` sem caminho paralelo;
    `MainActivity` só aplica `setShowWhenLocked`/`setTurnScreenOn` (Android
    27+) quando a própria intent de lançamento carrega um extra `payload`
    que valida estritamente contra o formato mínimo `RingCallIntent` v2
    (`RingCallLaunchPayload.kt`: estrutura/tipos, `v=2`, `event_id`/
    `call_id`/`device_id` nos padrões do contrato, `occurred_at` UTC válido;
    versão elevada de v1 para v2 na 3B.9d abaixo, junto da adição de
    `call_id`) — nunca
    em abertura comum do app, de outra notificação, ou de uma Intent externa
    arbitrária carregando um extra chamado `payload` (a Activity é
    exportada). O payload nunca é logado por essa validação;
  - nenhuma ação é anexada diretamente à notificação: "Atender"/"Dispensar"
    continuam vivendo somente na `IncomingCallPage`, evitando qualquer
    atalho de `OPEN_DOOR`/autorização a partir de um receiver em isolate de
    background;
  - permissão e fallback: `USE_FULL_SCREEN_INTENT` foi declarada no
    manifest (distinta de `POST_NOTIFICATIONS`); `SecuritySettingsPage`
    ganhou uma seção informativa e estritamente voluntária ("Chamada em
    tela cheia") que só mostra status e, quando necessário, um botão que
    abre `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` — nada disso é chamado
    automaticamente no boot, login ou recebimento de push, e uma recusa
    nunca é tratada como falha do app nem gera nova cobrança repetida;
  - `USE_FULL_SCREEN_INTENT` é acesso especial do Android sujeito à política
    da Google Play; a publicação exigirá declarar na Play Console que
    receber chamadas do interfone é funcionalidade central do produto —
    nenhuma alteração de Play Console foi feita nesta entrega, e nenhuma
    aprovação futura é dada como garantida;
  - avaliação técnica e decisão consciente de adiamento: `ConnectionService`/
    `TelecomManager`/`InCallService` não foram implementados nesta subfase.
    Sem sessão de mídia real, chamada ativa ou ciclo de chamada de fato, uma
    integração Telecom seria uma "chamada" cosmética sem conteúdo por trás —
    a documentação oficial não aponta necessidade de Telecom apenas para
    apresentar full-screen intent e ações locais. Essa integração será
    reavaliada junto da futura frente de áudio bidirecional, quando existir
    uma chamada real para registrar;
  - testes automatizados cobrem: a apresentação de `RING_ONLY`/
    `RING_AND_NOTIFICATION` sempre com full-screen intent (`androidChannelFor`
    e `present()`, este último sem nenhum handler registrado no canal nativo
    de acesso — provando que não depende de `MainActivity`/Activity viva),
    `NOTIFICATION_ONLY` nunca com full-screen, uma falha ou ausência do canal
    nativo de acesso nunca alterando a apresentação do push, a UI voluntária
    de acesso da `SecuritySettingsPage` (nunca solicita sozinha, só ao toque
    explícito), e — em Kotlin (`RingCallLaunchPayloadTest.kt`) — que só um
    `payload` estritamente válido do contrato `RingCallIntent` v2 habilita o
    comportamento de lock screen, enquanto payload ausente, malformado,
    incompleto, com campo extra ou de versão anterior (v1) nunca habilita
    (um toque em `NOTIFICATION_ONLY` carrega esse mesmo formato de payload,
    já que representa a mesma sessão de chamada — ver bullet abaixo);
    `flutter analyze`/`flutter test` verdes — ver
    `docs/APP_COMMUNICATION_STATUS.md` para o resultado exato;
  - **3B.9d — toque contínuo, modos exclusivos, `RING_ENDED`/`call_id`,
    overlay de navegação e correções de UX reportadas em teste manual
    (Android 17; implementação completa, validada manualmente em Android
    físico — ver 3B.9f abaixo):**
    - **toque contínuo e canais versionados:** `RING_ONLY`/
      `RING_AND_NOTIFICATION` passam a usar `Notification.FLAG_INSISTENT`
      (API pública e estável do Android, o mecanismo anterior ao
      `ConnectionService` para repetir som/vibração até a notificação ser
      cancelada — nenhuma dependência nova), `AudioAttributesUsage
      .notificationRingtone`, `ongoing: true`/`autoCancel: false` (não
      some com toque acidental) e `timeoutAfter: 60000` (auto-cancelamento
      pelo próprio Android, garantido mesmo com o processo do app morto).
      O canal de chamada foi renomeado para `incoming_call_v2` e o antigo
      canal silencioso `ring_notification_silent` foi substituído por
      `device_notification_v1`, uma notificação normal e audível (nunca
      mais forçada a silenciosa) — canais Android congelam som/vibração/
      importância na primeira criação, então qualquer mudança semântica
      futura exige novo id versionado, nunca editar o canal existente;
    - **modo Notificação também leva a `IncomingCallPage`:** `RING_ONLY` e
      `NOTIFICATION_ONLY` representam a mesma sessão de chamada viva, só
      apresentada de forma diferente (toque contínuo + tela automática vs.
      notificação comum tocável, sem full-screen, sem toque contínuo) — os
      dois carregam o mesmo payload `RingCallIntent`, o toque em qualquer um
      leva ao mesmo `IncomingCallPage`, e `RING_ENDED`/timeout/`expires_at`/
      tombstone se aplicam igualmente aos dois, já que é a mesma sessão sob
      o mesmo `call_id`. (Uma iteração anterior desta entrega havia feito
      `NOTIFICATION_ONLY` navegar apenas para o destino do dispositivo
      `/devices/{deviceId}` com um payload próprio e distinto — corrigido
      após confirmar em teste manual que a expectativa correta é abrir a
      chamada, não um evento já encerrado.)
    - **preferências exclusivas:** as duas opções independentes de alerta
      viraram uma escolha exclusiva de três estados ("Chamada" /
      "Notificação" / "Desativado") em `NotificationPreferencesPage`. O app
      só grava `NONE`/`RING_ONLY`/`NOTIFICATION_ONLY`; o valor legado
      `RING_AND_NOTIFICATION` continua sendo lido e exibido como "Chamada"
      selecionada (nunca reescrito), preservando compatibilidade com contas
      não tocadas desde antes desta migração ou com o rollout do próprio
      backend. "Horários sem ligação" foi renomeado para "Horários de
      silêncio" (nome mais preciso: a agenda também pode silenciar
      notificações comuns, não só a chamada);
    - **contrato `RING_ENDED` e correlação por `call_id` (consumo
      implementado no app; extensão coordenada e implantada pelo backend
      em DEV — interBackend PR #27, validada na 3B.9f abaixo):**
      `RingDetectedEvent`/o novo `RingEndedEvent`
      (`lib/core/push/ring_detected_event.dart`) compartilham um `call_id`
      que correlaciona um `RING_DETECTED` ao seu eventual `RING_ENDED`,
      conforme a extensão mínima e retrocompatível abaixo (ver
      `lib/core/push/ring_detected_push_parser.dart`):
      - `call_id` **opcional** em `RING_DETECTED`, casando
        `^call-[0-9a-f]{32}$`; ausente, o app deriva `call-<32 hex>` a partir
        do sufixo do `event_id` (nenhum push antigo quebra, e o valor
        derivado já casa a regex canônica que todo consumidor exige);
      - `RING_ENDED`: mesmo envelope de `RING_DETECTED` (`push_contract_version`,
        `event_id`, `device_id`, `event`, `occurred_at`), **sem**
        `presentation_intent` e com `call_id` **obrigatório**;
      - dedup por `event_id` já cobre um `RING_ENDED` duplicado de graça
        (idempotente);
      - `endCall` ignora silenciosamente um `call_id` que não é o
        pendente/ativo no momento (chamada antiga já superada nunca cancela
        uma nova; um fim que nunca corresponde a nada aqui — por exemplo
        para `NOTIFICATION_ONLY`, que não tem `call_id` rastreado — também
        não faz nada);
    - **timeout local de 60s como fallback (independe do backend enviar
      `RING_ENDED`):** `RingCallNavigationCoordinator` agenda um único
      timer a partir de `occurredAt` (mesmo antes de autenticar/abrir a
      tela) que encerra a chamada localmente aos 60s se nada mais a
      encerrar antes — mesma duração usada no `timeoutAfter` da notificação,
      então os dois se cancelam juntos mesmo que o app esteja em foreground
      (ver `ringCallEndIntegrationProvider`, que também cobre o caso desse
      timer interno, que sozinho não cancela nada);
    - **navegação por overlay, não mais rota `/incoming-call`:**
      `RingCallOverlay` (`lib/features/devices/presentation/widgets/
      ring_call_overlay.dart`) fica empilhado sobre o conteúdo atual do
      `GoRouter` via `MaterialApp.router.builder`, nunca trocando de rota.
      Isso corrige três problemas reportados no teste manual: a tela
      anterior (`HomePage`/`BiometricLockGate`) não aparece mais
      brevemente e interativa antes da tela de chamada (o overlay cobre a
      partir do primeiro frame em que a chamada fica pendente, com uma
      superfície neutra "Validando chamada…" — `RingCallNavigationCoordinator
      .isValidating`); dispensar a chamada nunca mais navega para `/`,
      revelando de novo exatamente a rota/pilha anterior; e como
      `HomePage`/`BiometricLockGate` nunca são reconstruídos por causa da
      chamada, o bloqueio biométrico não é acionado duas vezes;
    - **chamada em foreground não depende do full-screen intent do
      Android:** quando o próprio app já está em primeiro plano,
      `IncomingCallNotificationService.onCallPresented` abre a
      `IncomingCallPage` diretamente pelo mesmo coordenador usado pelo
      toque na notificação — nunca esperando o Android decidir abrir tela
      cheia, algo que o próprio SO pode legitimamente não fazer com o app
      já em uso. Esse retorno só é usado pela instância que o listener de
      *foreground* usa para apresentar (`_handleForegroundRingPush`); a
      instância do isolate de background nunca o recebe, então esse
      comportamento nunca ocorre a partir de push processado com o app
      fechado;
    - **bloqueio biométrico é exceção durante uma chamada:**
      `BiometricLockGate` nunca inicia um prompt biométrico nativo enquanto
      `RingCallNavigationCoordinator` tem uma chamada pendente ou ativa —
      necessário porque um prompt nativo aparece por cima de qualquer
      overlay Flutter, então cobrir visualmente não bastaria. Uma tentativa
      automática represada é retomada exatamente uma vez quando a chamada
      termina, nunca duas;
    - **bug encontrado em rodada de teste manual posterior, corrigido nesta
      branch: a mesma exceção precisa cobrir a *decisão* de bloquear, não só
      o prompt.** Com bloqueio biométrico "imediato", um app já desbloqueado
      em foreground voltava a pedir biometria só por causa da própria
      apresentação da chamada (central de notificações abrindo/fechando,
      full-screen intent, `MainActivity` alternando `showWhenLocked`) emitir
      `inactive`/`paused`/`resumed` no Flutter sem o usuário realmente ter
      saído do app;
    - **hardening posterior: checar `_callInFlight` só no instante do
      `resumed` ainda deixava uma corrida real.** No Android real,
      `endCall()` (Atender, Dispensar, `RING_ENDED`, o ring-timeout local)
      pode chegar *antes* do `resumed` correspondente, não só depois — nesse
      caso `_callInFlight` já volta a `false` antes da checagem rodar. A
      primeira correção classificava o **ciclo** de background inteiro
      (`_backgroundedAt` até o próximo `resumed`) em vez de só o instante do
      `resumed`, mas usava um latch booleano simples: "uma chamada esteve
      pendente/ativa em algum momento do ciclo" — **qualquer chamada no
      ciclo bastava**, mesmo uma que só coincidiu no tempo com o usuário
      tendo saído de fato do app;
    - **hardening final: distinguir apresentação-da-própria-chamada de
      background genuíno.** O latch booleano acima confundia dois eventos
      diferentes: (1) o app estava em foreground e desbloqueado, e foi a
      *própria apresentação* da chamada (central de notificações, toque,
      full-screen intent, `MainActivity` alternando `showWhenLocked`) que
      gerou o ciclo `inactive`/`paused`/`resumed` — deve preservar o
      desbloqueio; (2) o usuário realmente saiu do app, e uma chamada por
      acaso chegou (e talvez terminou) enquanto ele estava fora — a política
      de bloqueio configurada deve valer normalmente, mesmo com a chamada.
      `BiometricLockGate` agora usa uma máquina de estados explícita,
      `_BackgroundCycleClassification` (`none` /
      `foregroundTransientCandidate` / `callPresentationFromForeground` /
      `genuineBackground`), em vez do latch booleano: um ciclo só pode virar
      `callPresentationFromForeground` se começou com o app desbloqueado em
      foreground e nenhuma evidência de `paused`/`hidden` ainda apareceu
      quando a chamada chega; assim que `paused`/`hidden` chega antes de
      qualquer chamada, o ciclo vira `genuineBackground` **permanentemente**
      — nenhuma chamada posterior, por mais que apareça e termine, o
      reclassifica de volta. No `resumed`, só `callPresentationFromForeground`
      pula o bloqueio (com um teto de segurança de 2 minutos, salvaguarda
      contra estado impossível/obsoleto, nunca a decisão principal);
      `genuineBackground` sempre aplica a política configurada normalmente,
      **mesmo que uma chamada ainda esteja ativa nesse instante** — o
      bloqueio é decidido de qualquer forma, e a exceção já existente em
      `build()`/`_scheduleAutomaticUnlock()` para `_callInFlight` apenas
      adia a revelação/o prompt até a chamada terminar, sem precisar de
      nenhum mecanismo novo de bloqueio diferido. Não é bypass permanente:
      nada aqui jamais define `_locked = false` fora de autenticação
      bem-sucedida, um app já bloqueado (cold start, sobre o keyguard) nunca
      alcança `callPresentationFromForeground` e permanece bloqueado nas
      duas ordens de evento, e a classificação é reiniciada a cada novo
      ciclo, ao trocar a instância do coordenador rastreado, ao desabilitar
      o bloqueio e ao desmontar o gate (logout);
    - **retorno ao keyguard ao encerrar sobre tela bloqueada:** novo canal
      `interapp/ring_call_presentation` (`MainActivity.endRingCallPresentation`)
      derruba `setShowWhenLocked`/`setTurnScreenOn` e, se o aparelho ainda
      estiver de fato bloqueado (`KeyguardManager#isKeyguardLocked`), chama
      `moveTaskToBack(true)` para devolver o usuário ao bloqueio do
      sistema — nunca deixando conteúdo comum do app visível sobre uma tela
      ainda bloqueada;
    - **status de tela cheia se atualiza de verdade:** `fullScreenIntentAccessProvider`
      agora é `autoDispose` (reconsulta ao reentrar na tela) e
      `SecuritySettingsPage` reconsulta também a cada retomada do app
      (`WidgetsBindingObserver`), corrigindo o texto "Ativado" que antes
      podia ficar desatualizado depois de o usuário mexer nas configurações
      do Android e voltar;
    - **"Atender" honesto (revisado na 3B.9e abaixo):** continua sem áudio
      real, mas desde a 3B.9e encerra a chamada exatamente como "Dispensar"
      em vez de deixá-la aberta indefinidamente — ver lá o motivo;
    - **Si3050 e força-encerramento continuam fora do critério de
      conclusão desta entrega:** nada aqui exige hardware físico do
      interfone — Si3050, linha analógica real, detecção física de ringing
      e o Linker Button seguem fora de escopo mesmo após a 3B.9f abaixo.
      `RING_ENDED` real do backend passou a ser validado ponta a ponta (ver
      3B.9f), mas isso não implica áudio real nem hardware de produção.
      Força-encerramento segue com a mesma ressalva já registrada na 3B.9a:
      o Android pode bloquear mensagens em segundo plano até reabertura
      manual, o que não é garantia do FCM/Android e por isso nunca é
      cobrado como validado.
  - **3B.9e — ordenação fora de sequência, `expires_at` e "Atender" honesto
    até o fim (revisão pós-CI conjunto com interBackend PR #27 e
    firmware/protocolo PR #23; implementação completa, validada
    manualmente em Android físico — ver 3B.9f abaixo):**
    - **tombstone persistente por `call_id`:** FCM, o isolate de background
      e o app encerrado não garantem que `RING_DETECTED(call_id=X)` seja
      processado antes do seu próprio `RING_ENDED(call_id=X)` — são
      `event_id`s diferentes, entregues por caminhos possivelmente
      distintos. `RingCallTombstoneStore` (`lib/core/push/ring_call_tombstone.dart`)
      grava de forma durável, via `SharedPreferences`, que um `call_id`
      terminou, e `presentRingDetectedPush` consulta esse estado
      imediatamente antes de qualquer `RING_DETECTED` chegar ao
      `present()` — um `call_id` já marcado como encerrado nunca cria
      notificação, toque, full-screen intent ou navegação; um término
      duplicado é idempotente (dedup por `event_id` já cobre); um término
      de uma chamada anterior nunca afeta uma chamada mais nova (`call_id`
      diferente). Assim como o deduplicador de `event_id`
      (`ring_event_deduplicator.dart`), isso é **best-effort**, não fonte
      de verdade, e falha aberto (nunca bloqueia uma chamada legítima) se a
      leitura falhar — nunca fechado;
    - **por que não um `Set` em memória:** o mesmo `call_id` precisa ser
      reconhecido pelo listener de foreground, pelo isolate de background
      do FCM (que pode ser recriado do zero a cada mensagem) e por um cold
      start causado por toque na notificação ou full-screen intent — nenhum
      desses compartilha memória entre si;
    - **cache do `SharedPreferences` diverge entre isolates — corrigido com
      `reload()`:** a API legada de `shared_preferences` cacheia todo o
      mapa de preferências em memória por isolate na primeira chamada a
      `getInstance()`, e uma leitura simples nunca busca de novo do nativo
      sozinha. Por isso `isEnded()` sempre chama
      `SharedPreferences#reload()` antes de ler — sem isso, uma instância
      de longa duração no isolate principal nunca enxergaria um tombstone
      escrito por uma execução mais recente do isolate de background. Esse
      mecanismo específico está coberto por teste automatizado que escreve
      diretamente no *mock* nativo por baixo da instância já cacheada e
      confirma que só a versão com `reload()` observa a escrita
      (`test/ring_call_tombstone_test.dart`);
    - **sem atomicidade entre isolates, declarada explicitamente:** esta
      entrega garante que um `RING_ENDED` gravado de forma durável *antes*
      de uma leitura posterior é sempre observado por ela; **não** garante
      atomicidade para uma corrida verdadeiramente simultânea entre início
      e término. Nesse caso raro, o pior cenário converge para "encerrada"
      pouco depois de qualquer forma (o próprio `RING_ENDED` cancela a
      notificação de modo incondicional, independente da corrida), e o
      timeout local de 60s/`timeoutAfter` do Android — já existentes,
      independentes deste tombstone — limitam por quanto tempo qualquer
      janela de corrida poderia parecer uma chamada viva;
    - **limpeza limitada:** TTL de 30 minutos (generoso frente ao TTL de
      push de ~30s do backend) e no máximo 50 entradas, com poda
      oportunística das expiradas a cada escrita — nunca cresce sem limite;
    - **`expires_at` (interBackend PR #27):** o parser
      (`lib/core/push/ring_detected_push_parser.dart`) passa a validar
      `expires_at` (UTC ISO-8601) quando presente em `RING_DETECTED`:
      formato inválido ou `expires_at < occurred_at` rejeita como
      `invalid_expires_at`; `now >= expires_at` rejeita como `expired`.
      **Nunca aplicado a `RING_ENDED`** — um fim de chamada é honrado mesmo
      que seu próprio `expires_at` de transporte pareça vencido, porque é
      preferível encerrar uma chamada "atrasada" a deixar uma chamada
      fantasma tocando. Payload legado sem `expires_at`: `RING_ENDED`
      segue exigindo `call_id` normalmente; `NOTIFICATION_ONLY` continua
      usando o `maxAge` genérico (15 min por padrão); `RING_ONLY`/
      `RING_AND_NOTIFICATION` sem `expires_at` passam a usar um teto
      próprio de ~60s a partir de `occurred_at` — o mesmo timeout de toque
      — em vez do `maxAge` genérico, para que uma chamada com muitos
      minutos de idade nunca comece a tocar só porque ainda estava dentro
      da folga genérica de entrega. Esse teto não precisa ser propagado
      para `RingCallIntent`/`RingCallLaunchPayload.kt`, que já derivam sua
      própria expiração com segurança de `occurred_at` mais essa mesma
      janela de 60s;
    - **"Atender" agora encerra de fato:** `IncomingCallPage._answer` (e o
      antigo `RingCallNavigationCoordinator.markAnswered`, removido por não
      ter mais função legítima) deixavam a tela de chamada aberta
      indefinidamente até `RING_ENDED` ou "Dispensar" — eliminando
      justamente o fallback de 60s para o cenário em que `RING_ENDED` nunca
      chega. Sem áudio bidirecional implantado, não existe sessão real para
      manter aberta depois de "Atender": agora ele cancela toque/
      notificação, encerra o coordenador, invalida o timer, desfaz o
      bypass de lock screen e retorna à rota anterior/ao keyguard — a única
      diferença para "Dispensar" é mostrar a mensagem honesta de áudio
      indisponível antes;
    - testes cobrem ordenação fora de sequência (fim antes do início nunca
      apresenta; início suprimido nunca reserva dedup; fim de X nunca
      afeta Y; corrida próxima degrada para encerrada), `expires_at`
      (futuro aceito; igual a agora e passado rejeitados; formato/coerência
      inválidos rejeitados; nunca aplicado a `RING_ENDED`; fallback legado
      de ~60s só para modo chamada), e "Atender" (cancela tudo, preserva
      rota, desfaz keyguard, sem prompt biométrico duplo, mensagem honesta
      preservada) — ver `test/ring_call_tombstone_test.dart`,
      `test/ring_detected_presenter_test.dart`,
      `test/ring_detected_push_parser_test.dart` e
      `test/incoming_call_page_test.dart`.
  - **bloqueio de autenticação encontrado na validação manual do PR #24,
    corrigido na mesma branch (fora do escopo funcional da 3B.9):**
    redefinição de senha (`beginPasswordReset`/`confirmPasswordReset`)
    falhava com a mensagem genérica "Não foi possível concluir a operação"
    mesmo com um código real enviado pelo Cognito, sem nenhum detalhe de
    diagnóstico em debug — `_runGuarded`/`_mapAuthException` em
    `CognitoAuthRepository` mapeavam qualquer `AuthException` não
    reconhecida para `AuthFailureKind.unknown` silenciosamente. Corrigido
    com: mapeamento de exceção **contextual por operação** (o mesmo
    `NotAuthorizedServiceException` não vira mais a mensagem de login
    "e-mail ou senha inválidos" durante a confirmação de reset); um
    diagnóstico sanitizado de debug (`lib/features/auth/data/repositories/auth_diagnostic.dart`,
    formato `[AUTH] operation=confirm_password_reset
    failure_type=InvalidParameterException` — nunca e-mail, senha, código,
    token ou mensagem bruta do provedor; nunca emitido em release); extensão
    do `CognitoAuthGateway` para cobrir `resetPassword`/`confirmResetPassword`
    (testável sem Cognito real); tratamento do próximo passo real do
    `resetPassword` (`AuthResetPasswordStep.done` não navega mais cegamente
    para a tela de código); e um botão "Enviar novo código" dedicado na tela
    de reset (nunca reaproveitando `resendSignUpCode`, que é do fluxo de
    cadastro). Cobertura em `test/cognito_password_reset_test.dart` e
    `test/auth_pages_reset_flow_test.dart`. A causa raiz exata do Cognito
    (qual `failure_type` real aparece) **ainda não foi confirmada** — depende
    de uma nova tentativa manual controlada com o novo log de diagnóstico.
  - **3B.9f — validação manual física ponta a ponta, após o deploy
    coordenado do backend (interBackend PR #27) e o flash do firmware
    coordenado (interBridge PR #23) — ambiente DEV:** confirmado em
    aparelho Android físico, com `RING_DETECTED` real chegando pelo
    pipeline AWS IoT → backend → FCM e `RING_ENDED` real (mesmo `call_id`)
    encerrando a chamada/apresentação correspondente; uma nova chamada pôde
    começar normalmente depois do término da anterior; modo Chamada
    apresentou a experiência de chamada conforme permitido pelo Android;
    modo Notificação mostrou notificação audível e acionável, e tocar nela
    abriu a experiência de chamada (não apenas o detalhe do dispositivo);
    "Programação de alertas → Somente notificação" reduziu Chamada a
    notificação acionável sem bloquear totalmente o alerta, e "Não avisar"
    seguiu sendo o único comportamento que bloqueia tudo; o layout vertical
    dos seletores não quebrou os rótulos; e, ao encerrar uma chamada com o
    app previamente desbloqueado, a biometria não foi pedida de novo
    indevidamente (ver o hardening de `BiometricLockGate` acima). Com isso,
    a 3B.9 está validada em DEV para o escopo atual de apresentação de
    chamada/notificação — infraestrutura de backend DEV implantada,
    firmware DEV coordenado, app e contrato `RING_ENDED`/`call_id`
    confirmados ponta a ponta.
    - **o que essa validação confirma, e o que não confirma:** o app
      valida a *apresentação* de uma sessão de chamada simulada — nenhum
      áudio real trafega nesta fase, `ConnectionService`/integração
      completa com a UI nativa de chamada do Android segue não iniciada
      (ver 3B.9d acima), e os GPIOs usados no firmware para gerar os
      eventos (`GPIO3`/`GPIO4`) são entradas DEV provisórias, não decisão
      de hardware de produção — mesma ressalva já registrada para o GPIO4
      na 3B.8. Si3050, linha analógica real, detecção física de ringing e o
      Linker Button continuam fora de escopo (ver bullet acima). Não foi
      testado, e não deve ser lido como validado: comportamento após
      força-encerramento (`adb shell am force-stop`), modo Não perturbe,
      permissão/canal de notificação revogados ou outras restrições do
      sistema; validação em múltiplos fabricantes/versões de Android além
      do aparelho usado neste teste; troca de som/toque configurável pelo
      usuário (fica para trabalho futuro); e nada disto é validação de
      produção — o backend e o firmware envolvidos são implantações DEV.
      Áudio bidirecional continua uma frente totalmente separada, ainda não
      iniciada; iOS/APNs permanece na 3B.10.
- [ ] **3B.10 — iOS, APNs e chamada**
  - cadastrar o app iOS no Firebase e configurar APNs;
  - capabilities, background modes e validação em aparelho físico;
  - estudar e implementar a integração apropriada de chamada no iOS;
  - não afirmar que FCM comum entrega sozinho toda a experiência de chamada;
  - manter áudio como frente separada.

### Consequência da nova identidade em Android DEV

Ao trocar o `applicationId`, o Android trata `com.interbridge.app` como outro
aplicativo. A instalação antiga `com.example.interapp` pode continuar separada;
será necessário entrar novamente no Cognito, e preferências locais e a outbox
da instalação antiga não serão migradas. Isso é aceitável antes da publicação
e de usuários reais, portanto não haverá migração do pacote provisório.

Dados remotos no Cognito e no DynamoDB — dispositivos, nomes e preferências —
não são apagados nem alterados. A instalação antiga pode ser removida
manualmente após a validação.

## Fase 3C — onboarding BLE real

- [ ] **3C.1 — firmware BLE:** implementação e CI prontas no PR de firmware;
  validação física permanece pendente.
- [ ] **3C.2 — transporte Android:** implementação com o SDK oficial Espressif
  em andamento; descoberta, conexão e Protocomm Security 1 aguardam validação
  física e não são considerados concluídos.
- [ ] **3C.3 — credenciais Wi-Fi:** envio seguro por `prov-config` permanece
  pendente; a 3C.2 falha explicitamente antes de iniciar configuração parcial.
- [ ] **iOS:** adaptador nativo futuro, fora da 3C.2.

### Execução DEV e validação física pendente da 3C.2

O app Android usa `esp-idf-provisioning-android` `lib-2.1.3`, SDK oficial da
Espressif para Unified Provisioning sobre BLE/Protocomm. A PoP DEV existe
somente em memória e deve ser fornecida localmente, sem entrar em arquivo,
log, screenshot ou controle de versão:

```sh
flutter run --dart-define=INTERBRIDGE_BLE_DEV_POP="$INTERBRIDGE_BLE_DEV_POP"
```

Sem a define, o adaptador falha fechado e o onboarding continua explicitamente
indisponível. Distribuição/obtenção da PoP de produção não pertence a esta fase.
O `setup_code` de 12 dígitos nunca é usado como PoP.

`DiscoveredInterBridge.transportId` é somente um handle opaco válido durante a
tentativa BLE. Nem esse handle, nem endereço Bluetooth, UUID local, nome
anunciado ou o sufixo `XXXX` podem alimentar uma API de claim como `device_id`.
Até existir um vínculo autenticado específico, o fluxo de claim exige uma
`ClaimSession` válida previamente resolvida por QR/código manual; descoberta
BLE pura para ao fim da sessão segura sem inventar identidade de produto.

Checklist de bancada ainda não executada:

1. instalar o app Android com PoP DEV local;
2. gravar o firmware BLE 3C.1;
3. encontrar `InterBridge-XXXX`;
4. conectar;
5. concluir Security 1 com PoP correta;
6. confirmar falha com PoP incorreta;
7. cancelar/desconectar e reconectar;
8. confirmar que scan e conexão não deixam recursos ativos;
9. confirmar ausência de segredos nos logs;
10. confirmar que Wi-Fi permanece bloqueado até a 3C.3.

- [ ] Implementar `BleOnboardingTransport` real.
- [ ] Garantir compatibilidade com ESP-IDF Unified Provisioning/Protocomm
  Security 1.
- [ ] Validar no Android físico antigo disponível.
- [ ] Manter QR e código manual como fallbacks.

O adaptador Android está em implementação; nenhuma capacidade BLE desta fase
foi validada fisicamente ou marcada como concluída.

## Trabalhos sem numeração definitiva

- compartilhamento e atribuição de membros;
- remoção ou transferência de dispositivos;
- áudio bidirecional;
- presença por rede local;
- demais evoluções ainda não decididas.

Esses trabalhos não pertencem automaticamente às Fases 3B ou 3C.
