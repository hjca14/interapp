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
- [ ] **3B.9 — Experiência de chamada no Android (antecipação mínima
  entregue; fase continua aberta)**
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
    reutiliza integralmente o fluxo `OPEN_DOOR` quando disponível. “Atender”
    informa honestamente que o áudio ainda não está disponível e não envia
    comando nem cria uma chamada ativa;
  - **continua aberta:** full-screen intent, integração Android de chamada
    (ConnectionService ou equivalente) e comportamento sobre lock screen
    permanecem no restante da 3B.9. Áudio bidirecional é uma frente separada,
    ainda não iniciada; iOS/APNs permanece na 3B.10.
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

- [ ] Implementar `BleOnboardingTransport` real.
- [ ] Garantir compatibilidade com ESP-IDF Unified Provisioning/Protocomm
  Security 1.
- [ ] Validar no Android físico antigo disponível.
- [ ] Manter QR e código manual como fallbacks.

O BLE real ainda não começou e permanece como a próxima grande frente depois
da Fase 3B.

## Trabalhos sem numeração definitiva

- compartilhamento e atribuição de membros;
- remoção ou transferência de dispositivos;
- áudio bidirecional;
- presença por rede local;
- demais evoluções ainda não decididas.

Esses trabalhos não pertencem automaticamente às Fases 3B ou 3C.
