# Hollow Grid

Hollow Grid — небольшая 2D multiplayer strategy game на hex-grid.

Клиент игры разрабатывается на Godot с экспортом в Web/HTML5. Серверная часть — Node.js + TypeScript WebSocket-сервер, который хранит авторитетное состояние матча.

## Цели проекта

- Небольшая пошаговая multiplayer-игра для 1-2 игроков.
- Тактический геймплей с упором на построение сети, контроль пространства и связность.
- Минималистичный визуальный стиль с понятным отображением игрового состояния.
- Возможность играть в браузере через Godot Web export.
- Отдельная серверная архитектура для синхронизации игроков.
- Компактный open-source проект, удобный для итераций и обучения.

## Структура проекта

```text
hollow-grid/
  docs/      Документация проекта
  game/      Godot-клиент
  server/    Node.js WebSocket-сервер
```

## Запуск сервера

```sh
cd server
npm install
npm run dev
```

По умолчанию сервер слушает:

```text
ws://127.0.0.1:8787
```

Порт можно изменить через `PORT`:

```sh
PORT=9000 npm run dev
```

## Проверка сервера

```sh
cd server
npm test
npm run build
```

`npm test` проверяет валидацию действий, TypeScript-порт правил матча и WebSocket room flow. `npm run build` проверяет TypeScript-компиляцию.

## Web export и деплой

Godot Web export генерируется в `dist/web/`:

```sh
scripts/export-web.sh
```

Для локальной проверки полного web-flow одной командой:

```sh
scripts/web-up.sh
```

После запуска сайт доступен по адресу:

```text
http://127.0.0.1:8080/
```

Godot-клиент в браузере подключается к multiplayer через `/ws`, а nginx внутри
Docker проксирует WebSocket в Node-сервер. `dist/` не коммитится. Инструкция для
локального preview и Apache + Docker деплоя находится в [Deploy](docs/deploy.md).

## WebSocket MVP flow

Первый клиент создаёт комнату:

```json
{ "type": "create_room" }
```

Сервер отвечает `room_created` с `room_code`, назначенным `player_1` и начальным `snapshot`.

Второй клиент подключается к комнате:

```json
{ "type": "join_room", "room_code": "ABCD12" }
```

Сервер назначает `player_2`, отправляет второму клиенту `joined`, а первому — `player_joined`.

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

После принятого действия сервер применяет правила и рассылает обоим игрокам полный `snapshot`. Некорректные действия возвращают `error` только отправителю.

## Документация

- [MVP](docs/mvp.md) — ближайшая реализуемая версия правил и критерии готовности.
- [GDD](docs/gdd.md) — дизайн-направление игры, долгосрочная модель и будущие расширения.
- [Protocol](docs/protocol.md) — сетевой формат `Action` и `Snapshot`.

## Текущий статус

Godot-проект находится в `game/`. В `server/` есть первый авторитетный WebSocket MVP: room code, два игрока, назначение `player_1`/`player_2`, приём action, проверка текущего игрока, TypeScript-порт `MatchState` и broadcast snapshot.
