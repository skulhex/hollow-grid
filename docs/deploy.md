# Деплой Hollow Grid

Есть два сценария:

- локальный preview: Docker запускает Node-сервер и nginx, nginx отдаёт Godot Web
  export и проксирует `/ws`;
- production на Debian: Apache отдаёт Godot Web export, Node WebSocket-сервер
  работает в Docker, Apache проксирует `/ws` в локальный контейнер.

## Сборка Web-клиента

Из корня репозитория:

```sh
scripts/export-web.sh
```

Сгенерированные файлы попадут сюда:

```text
dist/web/
```

`dist/` — генерируемый артефакт, его не нужно коммитить.

## Локальный preview через Docker

Из корня репозитория:

```sh
scripts/web-up.sh
```

Скрипт:

- пересобирает Godot Web export в `dist/web/`;
- запускает `docker compose up -d --build`;
- поднимает Node-сервер и nginx;
- печатает URL сайта и healthcheck URL.

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

## Production: Node-сервер в Docker

Из корня репозитория:

```sh
docker compose up -d --build
```

Compose публикует контейнер только на localhost:

```text
127.0.0.1:8787 -> container:8787
```

Проверка на Debian-хосте:

```sh
curl http://127.0.0.1:8787/healthz
```

Ожидаемый ответ:

```text
ok
```

## Production: публикация статических файлов

Скопируй или синхронизируй web-сборку в document root Apache:

```sh
sudo mkdir -p /var/www/hollow-grid
sudo rsync -a --delete dist/web/ /var/www/hollow-grid/
```

## Production: Apache Virtual Host

Включи нужные модули Apache:

```sh
sudo a2enmod headers proxy proxy_http proxy_wstunnel ssl mime
sudo systemctl reload apache2
```

Пример HTTPS vhost:

```apache
<VirtualHost *:443>
    ServerName example.com

    DocumentRoot /var/www/hollow-grid
    DirectoryIndex index.html

    <Directory /var/www/hollow-grid>
        Require all granted
        Options -Indexes
    </Directory>

    AddType application/wasm .wasm
    AddType application/octet-stream .pck

    ProxyPreserveHost On
    ProxyPass "/ws" "ws://127.0.0.1:8787/"
    ProxyPassReverse "/ws" "ws://127.0.0.1:8787/"

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/example.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
</VirtualHost>
```

Замени `example.com` и пути к сертификатам на свой домен и реальные файлы
сертификата.

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
