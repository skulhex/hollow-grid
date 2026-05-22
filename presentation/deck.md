---
marp: true
theme: hollow-grid
paginate: true
size: 16:9
title: Hollow Grid
description: Презентация проекта Hollow Grid для показа в колледже
---

<!-- _class: lead -->

<div class="kicker">Проектная работа</div>

# Hollow Grid

<p class="subtitle">Пошаговая multiplayer strategy game на hex-grid: Godot-клиент, TypeScript WebSocket-сервер и браузерный запуск.</p>

<img class="hero-mark" src="./assets/hex-network-mark.svg" alt="Минималистичная схема hex-сети">

<div class="chips">
  <span class="chip">Godot Web</span>
  <span class="chip">Node.js</span>
  <span class="chip">WebSocket</span>
  <span class="chip">TypeScrip</span>
</div>

---

## Актуальность проекта

<div class="grid-2">
  <div class="panel">
    <h3>Практика реальной разработки</h3>
    <ul>
      <li>клиент и сервер как отдельные части системы;</li>
      <li>сетевое взаимодействие через WebSocket;</li>
      <li>проверка правил на сервере, а не только на клиенте.</li>
    </ul>
  </div>
  <div class="panel">
    <h3>Почему игра подходит для демонстрации</h3>
    <ul>
      <li>видимый результат в браузере;</li>
      <li>есть алгоритмическая часть: поле, ходы, валидация;</li>
      <li>можно показать архитектуру, тесты и сборку.</li>
    </ul>
  </div>
</div>

---

## Цель и задачи

<div class="grid-2">
  <div class="panel">
    <h3>Цель</h3>
    <p>Создать рабочий прототип сетевой пошаговой стратегии, которую можно запустить в браузере и протестировать локально.</p>
  </div>
  <div class="panel">
    <h3>Задачи</h3>
    <ul>
      <li>описать правила матча и игровое состояние;</li>
      <li>реализовать Godot-клиент с hex-полем и HUD;</li>
      <li>создать WebSocket-сервер комнат;</li>
      <li>покрыть серверную логику тестами;</li>
      <li>подготовить web-preview через Docker/nginx.</li>
    </ul>
  </div>
</div>

---

## Идея игры Hollow Grid

<div class="game-idea">
  <div>
    <p><strong>Hollow Grid</strong> — тактическая игра про развитие сети от своего <code>Core</code> на hex-grid поле.</p>
    <ul>
      <li>игроки расширяют сеть узлов;</li>
      <li>перекрывают маршруты соперника;</li>
      <li>улучшают узлы под экономику, защиту и атаку;</li>
      <li>побеждают, уничтожив вражеский <code>Core</code>.</li>
    </ul>
  </div>
  <div class="shot contain">
    <img src="./assets/rules-mini-map.svg" alt="Стартовое поле Hollow Grid с двумя ядрами и центральной ресурсной клеткой">
  </div>
</div>

---

## Правила и игровое поле

<div class="rules-layout">
  <div>
    <div class="grid-3">
      <div class="metric panel">
        <span class="value">37</span>
        <span class="label">клеток на hex-grid радиуса 3</span>
      </div>
      <div class="metric panel">
        <span class="value">2</span>
        <span class="label">игрока в основном online-режиме</span>
      </div>
      <div class="metric panel">
        <span class="value">5 HP</span>
        <span class="label">у каждого Core в базовой настройке</span>
      </div>
    </div>
    <div class="panel" style="margin-top: 24px;">
      <ul>
        <li>каждый ход активный игрок строит, восстанавливает, улучшает или завершает ход;</li>
        <li>сеть активна только если связана с собственным <code>Core</code>;</li>
        <li>сервер проверяет очередность, владельца действия и допустимость клетки.</li>
      </ul>
    </div>
  </div>
  <div class="rules-map">
    <img src="./assets/game-overview.png" alt="Минималистичная схема игрового поля и сетей игроков">
  </div>
</div>

---

## Архитектура проекта

<div class="arch">
  <div class="arch-box">
    <h3><span class="accent-blue">Godot-клиент</span></h3>
    <ul>
      <li>отрисовка hex-grid;</li>
      <li>HUD и ввод игрока;</li>
      <li>Web export в браузер;</li>
      <li>WebSocketPeer для сети.</li>
    </ul>
  </div>
  <div class="arch-arrow">WS<br><span class="small">JSON</span></div>
  <div class="arch-box">
    <h3><span class="accent-cyan">TypeScript-сервер</span></h3>
    <ul>
      <li>комнаты и слоты игроков;</li>
      <li>авторитетный <code>MatchState</code>;</li>
      <li>валидация публичных действий;</li>
      <li>broadcast полного snapshot.</li>
    </ul>
  </div>
</div>

---

## Сетевой flow

<div class="flow">
  <div class="flow-step">
    <b>create room</b>
    <span>первый клиент получает <code>room_code</code>, <code>player_1</code> и начальный snapshot</span>
  </div>
  <div class="flow-step">
    <b>join room</b>
    <span>второй клиент подключается по коду и получает свободный слот игрока</span>
  </div>
  <div class="flow-step">
    <b>action</b>
    <span>клиент отправляет typed envelope с игровым действием</span>
  </div>
  <div class="flow-step">
    <b>snapshot</b>
    <span>после принятого действия сервер рассылает полное состояние матча</span>
  </div>
</div>

<div class="panel" style="margin-top: 28px;">
  <p><code>create_room</code>, <code>join_room</code>, <code>action</code>, <code>snapshot</code>, <code>presence_updated</code>, <code>error</code></p>
</div>

---

## Практическая реализация

<div class="grid-2">
  <div class="panel">
    <h3>Клиент</h3>
    <ul>
      <li><code>main.gd</code> управляет режимами игры;</li>
      <li><code>board_view.gd</code> отвечает за поле;</li>
      <li><code>network_client.gd</code> отправляет и принимает JSON-сообщения;</li>
      <li><code>hud.gd</code> показывает HP, ресурсы и статус.</li>
    </ul>
  </div>
  <div class="panel">
    <h3>Сервер</h3>
    <ul>
      <li><code>hollowGridServer.ts</code> держит комнаты и WebSocket-сессии;</li>
      <li><code>matchState.ts</code> применяет правила;</li>
      <li><code>gameAction.ts</code> разбирает и валидирует действия;</li>
      <li><code>messages.ts</code> фиксирует сетевой контракт.</li>
    </ul>
  </div>
</div>

---

## Тестирование и сборка

<div class="checks-layout">
  <div class="terminal">
    <code>$ cd server</code>
    <code>$ npm test</code>
    <code class="ok">3 test files passed</code>
    <code class="ok">20 tests passed</code>
    <br>
    <code>$ npm run build</code>
    <code class="ok">TypeScript compile OK</code>
  </div>
  <div class="check-list">
    <div class="check-item">
      <h3>Правила матча</h3>
      <p><code>matchState.test.ts</code>: начальный snapshot, очередность ходов, upkeep, ресурсы, роли узлов, атаки, взлом и завершение игры.</p>
    </div>
    <div class="check-item">
      <h3>Контракт действий</h3>
      <p><code>gameAction.test.ts</code>: публичные действия принимаются, некорректные формы отклоняются, внутренние команды не проходят в transport.</p>
    </div>
    <div class="check-item">
      <h3>Сетевой сценарий</h3>
      <p><code>websocket.test.ts</code>: healthcheck, create/join room, reconnect, full-room errors, player ownership и broadcast snapshot.</p>
    </div>
  </div>
</div>

---

<!-- _class: demo-slide -->

## Демонстрация запуска в браузере

<div class="demo-head">
  <p class="small">Web preview: <code>scripts/web-up.sh</code> → <code>http://127.0.0.1:8080/</code></p>
  <p class="demo-command">Godot Web клиент подключается к <code>/ws</code></p>
</div>

<div class="shot contain demo-shot">
  <img src="./assets/browser-demo-content.png" alt="Hollow Grid в браузере: партия в середине игры с HUD и online-комнатой">
</div>

---

## Выводы

<div class="grid-2">
  <div class="panel">
    <h3>Что получилось</h3>
    <ul>
      <li>прототип пошаговой стратегии с online flow;</li>
      <li>разделение клиента, сервера и документации;</li>
      <li>серверная валидация действий и снимки состояния;</li>
      <li>локальный browser preview через Docker.</li>
    </ul>
  </div>
  <div class="panel">
    <h3>Что показал проект</h3>
    <ul>
      <li>как связать игровой движок и backend;</li>
      <li>как проектировать сетевой протокол;</li>
      <li>как тестировать критичную игровую логику.</li>
    </ul>
  </div>
</div>

---

## Дальнейшее развитие

<div class="grid-2">
  <div class="panel">
    <h3>Игровые механики</h3>
    <ul>
      <li>баланс ролей <code>Harvester</code>, <code>Striker</code>, <code>Defender</code>, <code>Hacker</code>;</li>
      <li>новые карты, resource points и hazard cells;</li>
      <li>улучшенная визуальная обратная связь по действиям.</li>
    </ul>
  </div>
  <div class="panel">
    <h3>Техническая часть</h3>
    <ul>
      <li>лобби и список активных комнат;</li>
      <li>наблюдатели и reconnect-поведение;</li>
      <li>больше e2e-проверок браузерного flow;</li>
      <li>production deploy и мониторинг.</li>
    </ul>
  </div>
</div>

<div class="footnote">Hollow Grid: Godot + Node.js + WebSocket</div>
