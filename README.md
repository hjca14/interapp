# InterApp — InterBridge

## Fase 2C: Cognito e leitura HTTPS

A Fase 2B do backend DEV está implantada e validada: existe um usuário confirmado e o primeiro Device foi registrado atomicamente com membership `OWNER/ACTIVE`. A Fase 2C conecta o app ao User Pool existente com os pacotes oficiais Amplify e consome, com **access token**, somente `GET /v1/devices`, `GET /v1/devices/{device_id}` e `GET /v1/devices/{device_id}/status`.

Obtenha os outputs não sensíveis na stack CloudFormation aprovada (console ou processo operacional da equipe) e mantenha-os fora do Git. Copie `config.example.json` para `config.dev.json` (ignorado) e substitua localmente os placeholders:

```sh
flutter run --dart-define-from-file=config.dev.json
```

Também se pode fornecer `APP_ENVIRONMENT=dev`, `API_BASE_URL`, `AWS_REGION=sa-east-1`, `COGNITO_USER_POOL_ID` e `COGNITO_APP_CLIENT_ID` individualmente com `--dart-define`. Nunca forneça senha ou token por argumento, log ou arquivo versionado.

O Amplify executa `USER_SRP_AUTH`, renova a sessão e guarda credenciais no armazenamento seguro nativo (Keychain no iOS e armazenamento criptografado suportado pelo plugin no Android). Não há app client secret, Hosted UI, MFA ou Identity Pool. A arquitetura é `Cognito → access token → API HTTP`; o app não chama AWS IoT Core.

Valide em aparelho/emulador: login do usuário DEV confirmado, restauração após reiniciar, lista do Device registrado, detalhe/status, pull-to-refresh, expiração/logout e estados offline. Cadastro, confirmação/reenvio e redefinição de senha também estão disponíveis. BLE, claim, QR, Fleet Provisioning, commands, MQTT, eventos, voz e realtime permanecem adiados.

## Gerenciamento de dispositivos: lista, detalhes e nome pessoal

A lista de dispositivos, a tela de detalhes e a edição do nome pessoal
(`display_name`) usam `DeviceRepository` (`listDevices`/`getDeviceDetails`/
`updateDeviceName`), implementado por `HttpDeviceRepository`. Listar e ver
detalhes continuam reais (as mesmas três rotas GET da Fase 2C). O contrato de
`PATCH /v1/devices/{device_id}` foi confirmado pelo interBackend PR #18 e o
`HttpDeviceRepository` já está alinhado a ele. A implementação existe
localmente no backend, mas ainda não foi implantada na AWS nem validada por
uma chamada remota real. Para testes/desenvolvimento sem depender da rota, use
`FakeDeviceRepository` (determinístico, em memória) no lugar de
`HttpDeviceRepository` ao sobrescrever `deviceRepositoryProvider`; cada
instância do fake representa a visão de um único usuário autenticado.

`display_name` pertence à `DeviceMembership` do usuário autenticado, não ao
Device físico/global. OWNER, ADMIN e MEMBER com membership ACTIVE podem mudar
o próprio apelido sem alterar o nome visto por outros usuários. Não há campo
de cômodo/ambiente/localização. Toda
a UI usa "InterBridge" como único fallback (`deviceDisplayName`,
`api_device.dart`) quando não há nome customizado — nunca `device_id`, que só
aparece em uma área técnica discreta e copiável na tela de detalhes.
Histórico, compartilhamento, notificações e BLE continuam adiados para PRs
próprias.

## Bloqueio biométrico local

Em **Segurança**, o usuário pode habilitar opcionalmente Face ID/Touch ID no iOS ou a biometria equivalente no Android e escolher depois de quanto tempo em background o app será bloqueado. A opção começa desativada. A preferência armazena somente a ativação e o período; nenhuma senha ou token é armazenado pelo recurso.

A biometria é apenas uma trava local: antes de desbloquear, o app confirma que a sessão Cognito continua válida. Sessão expirada ou revogada sempre volta ao login normal. Cancelamento, indisponibilidade e falha mantêm a tela bloqueada, e o botão **Entrar com e-mail e senha** é o fallback obrigatório. Cadastro, confirmação de e-mail e recuperação de senha não passam por essa trava.

Passkeys/WebAuthn ficam documentadas como evolução futura para autenticação biométrica real no servidor. Elas não devem ser confundidas com este desbloqueio local de uma sessão Cognito existente.
