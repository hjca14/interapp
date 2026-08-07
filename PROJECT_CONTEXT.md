# InterBridge — Contexto do Projeto

## Objetivo

Aplicativo Flutter para controlar dispositivos InterBridge. Um usuário pode ter
vários dispositivos, e cada dispositivo possui favoritos próprios para o
discador interno.

## Estado atual

- O aplicativo ainda não se comunica com um InterBridge físico.
- Dados são persistidos localmente com `shared_preferences`.
- Não existem dados fictícios: um dispositivo, perfil ou favorito só aparece
  depois de ser criado pelo usuário.
- O botão verde do discador é um ponto de integração futuro. Ele não deve abrir
  o aplicativo de telefone nem usar `tel:`.

## Arquitetura adotada

- **Feature First:** cada domínio fica em `lib/features/<feature>`.
- **Riverpod:** `ProviderScope` é criado em `main.dart`; repositórios locais são
  expostos em `features/devices/presentation/providers/devices_providers.dart`.
- **GoRouter:** rotas ficam em `lib/core/router/app_router.dart`.
- A rota de detalhes é `/devices/:deviceId`. No estado atual, o objeto do
  dispositivo é encaminhado via `extra`; quando houver backend, a rota deverá
  buscar o dispositivo pelo `deviceId`.

## Estrutura relevante

```text
lib/
  app/                         # Tema e MaterialApp.router
  core/router/                 # Configuração do GoRouter
  features/
    devices/                   # Cadastro, cards e detalhe do InterBridge
    dialer/                    # Teclado e estado do número a discar
    favorites/                 # Favoritos isolados por dispositivo
    profile/                   # Cadastro local do perfil
    settings/                  # Ajustes do aplicativo
    sharing/                   # Modelos preparados para compartilhamento
```

## Fluxos implementados

### Dispositivos

1. A aba **Dispositivos** exibe cada InterBridge em um card.
2. O usuário adiciona um dispositivo por nome; a conexão real será criada mais
   adiante.
3. Cada card permite editar e remover o dispositivo.
4. Tocar em um card abre `DeviceDetailPage`.
5. O detalhe possui as abas **Resumo**, **Discar** e **Favoritos**.
6. Eventos, status e firmware não são simulados: enquanto não houver conexão,
   a UI informa que está aguardando dados.

### Discador e favoritos

- Os favoritos são salvos por `deviceId`, usando a chave local
  `favorites_<deviceId>`.
- Tocar em um favorito preenche o discador interno e abre a aba **Discar**.
- Criar/editar favorito usa `FavoriteFormDialog`, que possui seus próprios
  `TextEditingController`s para evitar descarte prematuro durante o fechamento
  do diálogo.

## Tema

O tema usa a identidade azul do InterBridge, configurada em `lib/app/app.dart`:

- primária: `#1246A8`;
- fundo: `#F3F7FF`;
- navegação: azul-claro com indicador azul.

## Compartilhamento futuro

O compartilhamento entre usuários **não está implementado**. A base inicial
está em `features/sharing/domain/entities/device_access.dart`:

- `owner`: administra, remove e compartilha o dispositivo;
- `admin`: poderá editar dispositivo e favoritos;
- `member`: poderá usar o dispositivo conforme permissões futuras.

Quando houver backend, implementar:

1. autenticação de usuários;
2. fonte remota para dispositivos, favoritos e eventos;
3. tabela/coleção de acessos por dispositivo e usuário;
4. convite por QR code ou link opaco, de uso único e com expiração;
5. deep link do convite no GoRouter;
6. regras de autorização no backend. Não confiar apenas nas permissões do app.

Supabase Cloud é o candidato inicial para autenticação, banco, regras de acesso
e atualizações em tempo real. Não há necessidade de hospedar um servidor próprio
para o protótipo.
