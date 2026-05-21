# Hollow Grid

Hollow Grid — небольшая 2D multiplayer strategy game на hex-grid.

Клиент разрабатывается в Godot и экспортируется в Web/HTML5. Сервер — Node.js +
TypeScript WebSocket-сервис, который хранит авторитетное состояние матча,
проверяет действия игроков и рассылает снимки состояния.

## Что уже есть

- Godot-клиент в `game/` с локальным режимом и online flow через WebSocket.
- Node.js сервер в `server/` с room code, двумя игроками, проверкой текущего
  игрока, применением action и broadcast полного `snapshot`.
- Docker preview, где web image сам собирает Godot Web export и отдаёт игру
  через nginx.
- GitHub Actions для server checks и публикации Docker images в GHCR.

## Структура проекта

```text
hollow-grid/
  docs/      Документация проекта
  game/      Godot-клиент
  server/    Node.js WebSocket-сервер
  deploy/    Docker/nginx файлы для web image
  scripts/   Локальные helper-скрипты
```

## Быстрый старт: сервер

```sh
cd server
npm install
npm run dev
```

По умолчанию dev-сервер слушает:

```text
ws://127.0.0.1:8787
```

Порт можно изменить через `PORT`:

```sh
PORT=9000 npm run dev
```

Проверки сервера:

```sh
cd server
npm test
npm run build
```

`npm test` проверяет валидацию действий, TypeScript-порт правил матча и
WebSocket room flow. `npm run build` проверяет TypeScript-компиляцию.

## Быстрый старт: Web preview

Полный локальный web-flow запускается из корня репозитория:

```sh
scripts/web-up.sh
```

Сайт будет доступен здесь:

```text
http://127.0.0.1:8080/
```

Скрипт запускает `docker compose up -d --build`, собирает Node-сервер и web
image. Web image скачивает Godot, устанавливает Web export templates,
экспортирует проект и кладёт готовую игру в nginx runtime.

Порт web preview можно изменить через `WEB_PORT`:

```sh
WEB_PORT=8090 scripts/web-up.sh
```

Остановить preview:

```sh
scripts/web-down.sh
```

В браузере Godot-клиент подключается к WebSocket по same-origin пути `/ws`.
Для локального preview это `ws://127.0.0.1:8080/ws`; nginx внутри Docker
проксирует этот WebSocket в Node-сервер.

## Ручной Godot Web export

Для debug-сборки без Docker web image можно экспортировать клиент в `dist/web/`:

```sh
scripts/export-web.sh
```

Для этого локально должен быть доступен `godot` с установленными Web export
templates. `dist/` — генерируемый артефакт, его не нужно коммитить.

## Документация

- [GDD](docs/gdd.md) — дизайн-направление игры, текущие правила и будущие расширения.
- [Protocol](docs/protocol.md) — сетевой формат `Action` и `Snapshot`.
- [Deploy](docs/deploy.md) — локальный Docker preview, GHCR images и production deploy через Apache.

## WebSocket room flow

Первый клиент создаёт комнату:

```json
{ "type": "create_room" }
```

Сервер отвечает `room_created` с `room_code`, назначенным `player_1` и начальным
`snapshot`.

Второй клиент подключается к комнате:

```json
{ "type": "join_room", "room_code": "ABCD12" }
```

Сервер назначает свободный слот, обычно `player_2`, отправляет подключившемуся
клиенту `joined`, а клиентам в комнате — `player_joined` и `presence_updated`.
Для возврата после обрыва клиент может отправить желаемый слот:

```json
{ "type": "join_room", "room_code": "ABCD12", "player": "player_1" }
```

Игровое действие отправляется через typed envelope:

```json
{
  "type": "action",
  "action": {
    "type": "place_node",
    "player": "player_1",
    "cell": { "q": -2, "r": 0 }
  }
}
```

После принятого действия сервер применяет правила и рассылает обоим игрокам
полный `snapshot`. Некорректные действия возвращают `error` только отправителю.

## CI и Docker images

GitHub Actions запускает server checks на pull request, push в `main` и tags
`v*`. На push в `main` и release tags workflow публикует два image в GHCR:

```text
ghcr.io/skulhex/hollow-grid/server
ghcr.io/skulhex/hollow-grid/web
```

Подробный production flow описан в [Deploy](docs/deploy.md).
