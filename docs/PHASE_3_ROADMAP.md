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
- [ ] **3B.3 — FlutterFire e FCM no Android**
  - `firebase_core`, `firebase_messaging` e `flutterfire configure`;
  - inicialização segura e permissão de notificações;
  - token inicial, renovação e handlers de foreground, background e app
    encerrado;
  - sem backend nesta subfase.
- [ ] **3B.4 — Validação direta do FCM**
  - enviar mensagem de teste pelo Firebase Console;
  - validar Android em foreground, background e app encerrado;
  - validar o toque na notificação;
  - não concluir antes do teste real.
- [ ] **3B.5 — Registro de instalações e tokens**
  - contrato coordenado entre app e backend;
  - instalação por usuário autenticado e suporte a múltiplos celulares;
  - renovação de token, logout e desregistro;
  - nunca expor tokens em logs.
- [ ] **3B.6 — Emissor FCM na AWS**
  - FCM HTTP v1 e credencial protegida no Secrets Manager;
  - nenhuma chave em repositório ou variável pública;
  - remoção segura de tokens inválidos;
  - mecanismo DEV controlado, sem rota pública improvisada para disparo.
- [ ] **3B.7 — Aplicação das preferências**
  - avaliar `alert_mode` e `quiet_schedule`;
  - respeitar dias ISO, horários e timezone IANA;
  - aplicar `NOTIFICATION_ONLY` e `BLOCK_ALL`;
  - comportamento por rede local continua fora do escopo e reservado para uma
    possível V2.
- [ ] **3B.8 — Simulador físico de toque no firmware**
  - botão/switch físico no ESP32;
  - publicar o evento definitivo (`RING_DETECTED` ou nome contratual
    equivalente), com `event_id` estável e fluxo MQTT real;
  - não criar atalho descartável fora do protocolo;
  - substituir futuramente o botão pelo detector real do interfone.
- [ ] **3B.9 — Experiência de chamada no Android**
  - evento remoto acorda o app;
  - notificação comum ou experiência de ligação conforme configuração;
  - respeitar filtros, abertura pelo toque e estados de
    foreground/background/encerrado;
  - não confundir recebimento de push com áudio bidirecional.
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
