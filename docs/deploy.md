# Деплой Hollow Grid

Есть два сценария:

- локальный preview: Docker собирает Node-сервер и web image, где Godot Web
  export уже встроен в nginx;
- production на Debian: Apache принимает HTTPS и проксирует запросы в Docker
  контейнеры, а web image не требует локального `dist/web`.

## Локальный preview через Docker

Из корня репозитория:

```sh
scripts/web-up.sh
```

Скрипт запускает:

- `docker compose up -d --build`;
- сборку Node-сервера;
- сборку web image, который скачивает Godot `4.6.2.stable`, устанавливает Web
  export templates, экспортирует проект и копирует результат в nginx;
- запуск Node-сервера и nginx.

По умолчанию сайт доступен здесь:

```text
http://127.0.0.1:8080/
```

Порт можно изменить через `WEB_PORT`:

```sh
WEB_PORT=8090 scripts/web-up.sh
```

В браузере Godot-клиент автоматически подключается к:

```text
ws://127.0.0.1:8080/ws
```

Nginx принимает `/ws` на том же origin и проксирует WebSocket в Node-сервис
внутри compose network.

Остановить локальный preview:

```sh
scripts/web-down.sh
```

## Ручной Godot Web export для debug

Обычно для запуска через Docker этот шаг не нужен: web image собирает Godot
export сам. Если нужно быстро получить локальные файлы в `dist/web/`, можно
выполнить:

```sh
scripts/export-web.sh
```

Сгенерированные файлы попадут сюда:

```text
dist/web/
```

`dist/` — генерируемый артефакт, его не нужно коммитить.

## Production: сборка и публикация images через GitHub Actions

GitHub Actions публикует два image в GHCR на push в `main` и на tags `v*`:

```text
ghcr.io/<owner>/<repo>/server
ghcr.io/<owner>/<repo>/web
```

На `main` публикуются tags `main`, `main-<short-sha>`, `sha-<short-sha>` и
`latest`. На release tag `v1.2.3` публикуются `v1.2.3` и `sha-<short-sha>`.

Если GitHub не даёт workflow публиковать packages, проверь настройки
репозитория: `Settings -> Actions -> General -> Workflow permissions`. Для
публикации в GHCR у `GITHUB_TOKEN` должно быть право записи.

Если package visibility приватная, на Debian-сервере нужно один раз выполнить
`docker login ghcr.io` с GitHub token, у которого есть право читать packages:

```sh
docker login ghcr.io
```

Для ручного обновления на Debian используй:

```sh
SERVER_IMAGE=ghcr.io/<owner>/<repo>/server:<tag> \
WEB_IMAGE=ghcr.io/<owner>/<repo>/web:<tag> \
docker compose pull

SERVER_IMAGE=ghcr.io/<owner>/<repo>/server:<tag> \
WEB_IMAGE=ghcr.io/<owner>/<repo>/web:<tag> \
docker compose up -d
```

## Production: локальная сборка без registry

Если registry пока не нужен, на Debian можно собрать images прямо из репозитория:

```sh
docker compose up -d --build
```

Compose публикует контейнеры только на localhost:

```text
127.0.0.1:8787 -> server container:8787
127.0.0.1:8080 -> web container:80
```

Проверка Node-сервера на Debian-хосте:

```sh
curl http://127.0.0.1:8787/healthz
```

Ожидаемый ответ:

```text
ok
```

## Production: Apache Virtual Host

Включи нужные модули Apache:

```sh
sudo a2enmod headers proxy proxy_http proxy_wstunnel ssl
sudo systemctl reload apache2
```

Пример HTTPS vhost:

```apache
<VirtualHost *:443>
    ServerName example.com

    ProxyPreserveHost On

    ProxyPass "/ws" "ws://127.0.0.1:8080/ws"
    ProxyPassReverse "/ws" "ws://127.0.0.1:8080/ws"

    ProxyPass "/" "http://127.0.0.1:8080/"
    ProxyPassReverse "/" "http://127.0.0.1:8080/"

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/example.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
</VirtualHost>
```

Замени `example.com` и пути к сертификатам на свой домен и реальные файлы
сертификата. Apache в этой схеме только принимает HTTPS и проксирует трафик в
локальный web container. Статические файлы игры уже находятся внутри web image.

Если игра открыта через HTTPS, браузер требует WebSocket-подключение через
`wss://`. Godot-клиент автоматически вычисляет такой адрес:

```text
wss://<current-host>/ws
```

Для локального HTTP-теста он вычисляет:

```text
ws://<current-host>/ws
```

Если нужно, WebSocket URL можно переопределить до старта Godot:

```html
<script>
  window.HOLLOW_GRID_WS_URL = "wss://example.com/ws";
</script>
```

Запуск из Godot editor/native по-прежнему использует:

```text
ws://127.0.0.1:8787
```
