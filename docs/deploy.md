# Деплой Hollow Grid

Документ описывает локальный web preview и production deploy через Docker.
Статические файлы Godot Web export находятся внутри web image, поэтому отдельный
`dist/web` на сервере не нужен.

## Схема

Локально:

```text
browser -> http://127.0.0.1:8080/ -> web nginx
browser -> ws://127.0.0.1:8080/ws -> web nginx -> server:8787
```

В production Apache принимает HTTPS и проксирует запросы в Docker:

```text
https://example.com/  -> Apache -> http://127.0.0.1:8080/
wss://example.com/ws -> Apache -> ws://127.0.0.1:8080/ws
```

Compose публикует контейнеры только на localhost:

```text
127.0.0.1:8787 -> server container:8787
127.0.0.1:8080 -> web container:80
```

## Требования

- Docker с Compose plugin.
- Для production: Apache 2, домен и HTTPS-сертификат.
- Для первой сборки web image: доступ в интернет, потому что Dockerfile
  скачивает Godot `4.6.2.stable` и Web export templates.

## Runtime-настройки

Сервер:

- `HOST` — bind host, по умолчанию `127.0.0.1` в dev и `0.0.0.0` в Docker image;
- `PORT` — порт сервера, по умолчанию `8787`;
- `GET /healthz` возвращает `ok`.

Compose:

- `WEB_PORT` — localhost-порт web container, по умолчанию `8080`;
- `SERVER_IMAGE` — image сервера, по умолчанию `hollow-grid-server`;
- `WEB_IMAGE` — image web-клиента, по умолчанию `hollow-grid-web`.

Godot Web client в браузере подключается к same-origin `/ws`: на HTTP это
`ws://<host>/ws`, на HTTPS — `wss://<host>/ws`. URL можно переопределить до
старта Godot:

```html
<script>
  window.HOLLOW_GRID_WS_URL = "wss://example.com/ws";
</script>
```

Запуск из Godot editor/native использует `ws://127.0.0.1:8787`.

Nginx runtime кеширует тяжёлые статические файлы Godot export (`.wasm`, `.pck`,
`.js`) на длительный срок с `immutable`, а `index.html` оставляет на
перепроверке. Поэтому первый заход может загружаться заметно, но повторное
открытие должно брать основной payload из кеша браузера.

## Локальный preview

Из корня репозитория:

```sh
scripts/web-up.sh
```

Сайт будет доступен по адресу:

```text
http://127.0.0.1:8080/
```

Скрипт запускает `docker compose up -d --build`, собирает Node-сервер и web
image. Web image сам скачивает Godot, устанавливает Web export templates,
экспортирует проект и кладёт результат в nginx runtime.

Порт web preview выставляется через `WEB_PORT`:

```sh
WEB_PORT=8090 scripts/web-up.sh
```

Проверка сервера:

```sh
curl http://127.0.0.1:8787/healthz
```

Остановить preview:

```sh
scripts/web-down.sh
```

## Ручной Godot Web export

Docker preview не требует локального `dist/web`. Для debug-export без Docker
нужен установленный `godot` с Web export templates:

```sh
scripts/export-web.sh
```

Файлы попадут в `dist/web/`. `dist/` не коммитится.

## Production images

GitHub Actions проверяет сервер и публикует два image в GHCR на push в `main` и
на tags `v*`:

```text
ghcr.io/skulhex/hollow-grid/server
ghcr.io/skulhex/hollow-grid/web
```

На сервере можно указать нужные образы через `.env` рядом с `compose.yml`:

```sh
SERVER_IMAGE=ghcr.io/skulhex/hollow-grid/server:<tag>
WEB_IMAGE=ghcr.io/skulhex/hollow-grid/web:<tag>
WEB_PORT=8080
```

После этого деплой или обновление:

```sh
docker compose pull
docker compose up -d
```

Если registry не используется, можно собрать images прямо на сервере:

```sh
docker compose up -d --build
```

## Apache vhost

Включить модули:

```sh
sudo a2enmod headers proxy proxy_http proxy_wstunnel ssl
sudo systemctl reload apache2
```

Базовый HTTP vhost:

```apache
<VirtualHost *:80>
    ServerName example.com

    ProxyPreserveHost On

    ProxyPass "/ws" "ws://127.0.0.1:8080/ws"
    ProxyPassReverse "/ws" "ws://127.0.0.1:8080/ws"

    ProxyPass "/" "http://127.0.0.1:8080/"
    ProxyPassReverse "/" "http://127.0.0.1:8080/"
</VirtualHost>
```

`/ws` должен быть описан до общего `ProxyPass "/"`. Замени `example.com` на
реальный домен. Если HTTPS настраивается через certbot или другой SSL-слой, эти
же proxy rules должны остаться в HTTPS vhost.

## Проверка после деплоя

На сервере:

```sh
docker compose ps
curl http://127.0.0.1:8787/healthz
```

В браузере:

- открыть `https://example.com/`;
- создать комнату в первом клиенте;
- подключиться по room code из второго клиента;
- сделать действие и убедиться, что оба клиента получили обновление поля.
