# 🛡️ Docker Anonymous: Minimal Node.js Stealth Runtime

[![CI](https://github.com/gkosarintsev/docker-anonymous/actions/workflows/ci.yml/badge.svg)](https://github.com/gkosarintsev/docker-anonymous/actions/workflows/ci.yml)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2%2B-blue.svg?logo=docker)](https://www.docker.com/)
[![Node.js](https://img.shields.io/badge/Node.js-v22%20LTS-green.svg?logo=node.js)](https://nodejs.org/)
[![Cloudflare WARP](https://img.shields.io/badge/Proxy-Cloudflare%20WARP-orange.svg?logo=cloudflare)](https://developers.cloudflare.com/warp-client/)
[![Anti-Fingerprint](https://img.shields.io/badge/Anti--Fingerprint-Node.js%20Native-purple.svg)](#-защита-от-fingerprint-без-эмуляции-браузера)
[![Kill-Switch](https://img.shields.io/badge/Kill--Switch-Fail--Closed-red.svg)](#-механизм-fail-closed-kill-switch)

Минималистичное консольное приложение на **Node.js (TypeScript)** в изолированном **Docker**-окружении с подменой IP-адреса через **Cloudflare WARP** и аппаратной защитой от фингерпринтинга (TLS JA3/JA4 и HTTP).

Проект спроектирован по принципу **минимализма кодовой базы приложения**: сам Node.js код выполняет исключительно сетевые запросы, а всю инфраструктурную сложность (проксирование, ротацию IP, генерацию отпечатков и изоляцию) берет на себя внешнее Docker-окружение.

---

## 📑 Содержание

- [Ключевые возможности](#-ключевые-возможности)
- [Архитектура решения](#-архитектура-решения)
- [Защита от Fingerprint (Node.js Native)](#-защита-от-fingerprint-без-эмуляции-браузера)
- [Механизм Fail-Closed (Kill-Switch)](#-механизм-fail-closed-kill-switch)
- [Быстрый старт](#-быстрый-старт)
- [Команды управления](#-команды-управления)
- [Автоматическое тестирование](#-автоматическое-тестирование)
- [Структура репозитория](#-структура-репозитория)
- [Технический стек](#-технический-стек)

---

## ✨ Ключевые возможности

1. **Минималистичное приложение (`src/index.ts`)**:
   - Чистый и лаконичный код (~60 строк).
   - Никаких тяжелых самописных сокетов — работа через стандартный `undici.ProxyAgent` и нативный `fetch`.
2. **Маршрутизация через Cloudflare WARP**:
   - Автоматическая регистрация клиентского ключа X25519 в Cloudflare API.
   - Туннелирование всего трафика через WireGuard в дата-центры Cloudflare (`warp=on`).
3. **Ротация IP при переустановке**:
   - При выполнении `reinstall.sh` генерируется новая пара ключей WireGuard и создается новая учетная запись WARP, что дает свежий выходной IP-адрес.
4. **Защита от Fingerprint для Node.js**:
   - Варьирование порядка и набора шифров TLS 1.3 / 1.2 (`--tls-cipher-list`).
   - Изменение сетевых хешей **JA3** и **JA4** при каждой переустановке.
   - **Честный профиль Node.js**: никакой фальшивой эмуляции браузера (Chrome/Firefox/Safari), которая легко выявляется поведенческим анализом WAF.
5. **Абсолютный Fail-Closed (Kill-Switch)**:
   - Если прокси-контейнер Cloudflare WARP недоступен или отключен, приложение аварийно завершает работу и **никогда не отправляет запросы с реального IP хоста**.
6. **Сохранение данных при обычном запуске**:
   - Команда `run.sh` повторно запускает приложение без изменения IP и отпечатка.

---

## 🏛 Архитектура решения

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Docker Host / Environment                       │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                     docker-compose (Bridge)                    │   │
│   │                                                                │   │
│   │  ┌───────────────────────┐          ┌───────────────────────┐  │   │
│   │  │  node-anonymous-app   │          │  warp-proxy-service   │  │   │
│   │  │                       │          │                       │  │   │
│   │  │ • Minimal Node.js 22  │          │ • Sing-Box WireGuard  │  │   │
│   │  │ • Strict ProxyAgent   │ ───────> │ • Mixed Proxy (:9091) │  │   │
│   │  │ • Injected TLS Ciphers│ loopback │ • Auto-reg CF Identity│  │   │
│   │  │ • Injected User-Agent │          │ • MTU 1200 Optimized  │  │   │
│   │  └───────────────────────┘          └───────────┬───────────┘  │   │
│   │              ▲                                  │              │   │
│   │              │ (Fail-Closed: no direct WAN)     │ WireGuard    │   │
│   └──────────────┼──────────────────────────────────┼──────────────┘   │
│                  │                                  │                  │
└──────────────────┼──────────────────────────────────┼──────────────────┘
                   │                                  ▼
              BLOCKED ❌                 Cloudflare Edge (WARP=ON)
         (Zero host IP leak)                          ▼
                                             Internet Destination
```

---

## 🔍 Защита от Fingerprint (без эмуляции браузера)

### Почему НЕ эмуляция браузера?
Попытки маскировать скрипты автоматизации под браузер (отправка `User-Agent: Mozilla/5.0...`, заголовков `Sec-Ch-Ua`) при использовании Node.js мгновенно детектируются современными антифрод-системами (Cloudflare Turnstile, Akamai, Datadome):
- Несовпадение структуры сетевого стека Node.js и реального браузерного движка Chromium/Gecko.
- Аномальное поведение HTTP/2 соединений и TLS ClientHello (отсутствие GREASE, другие наборы расширений).

### Как устроена защита в проекте:
Приложение позиционирует себя как **легитимный Node.js клиент**, но защищено от статистического профилирования и отслеживания между инсталляциями:

1. **Ротация TLS ClientHello (JA3 / JA4)**:
   - Внешний скрипт `generate-env.sh` формирует псевдослучайную комбинацию и порядок криптографических шифров из пула стойких шифров OpenSSL:
     `ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...`
   - Набор передаётся в Node.js через переменную окружения `NODE_OPTIONS=--tls-cipher-list=...`, которая читается **бинарём `node` при старте процесса** — до выполнения какого-либо JavaScript кода. Это runtime-параметр, а не compile-time: скомпилированный TypeScript ничего не знает о шифрах; ими управляет внешнее окружение.
   - В результате внешние анализаторы (например, `tls.peet.ws`) фиксируют смену сигнатур **JA3** и **JA4** после каждого `reinstall.sh`, не требуя пересборки образа.
2. **Ротация идентификаторов бэкенд-клиентов**:
   - `User-Agent` генерируется из набора популярных серверных HTTP-клиентов (`axios`, `node-fetch`, `got`, `undici`, `Node.js native`).
3. **Смена Machine ID**:
   - При каждой переустановке генерируется новый 128-битный идентификатор машины.

---

## 🛑 Механизм Fail-Closed (Kill-Switch)

Главный критерий безопасности анонимного контура — **невозможность утечки реального IP-адреса хоста**.

В данном проекте реализована строгая защита от падения прокси:
1. **На уровне HTTP-клиента**:
   Глобальный диспетчер `ProxyAgent` настроен исключительно на `http://127.0.0.1:9091`. Если порт прокси недоступен, Node.js выбрасывает ошибку `fetch failed (ECONNREFUSED)` и аварийно завершает процесс (`exit 1`). Резервный прямой выход в сеть программно исключен.
2. **На уровне Docker сети**:
   Контейнер `node-app` использует сетевой стек `network_mode: service:warp-proxy`. Если сервис `warp-proxy` падает или останавливается, сетевой порт 9091 исчезает мгновенно.

---

## 🚀 Быстрый старт

### Требования
- **Docker** и **Docker Compose v2+**
- **Bash** (Linux, macOS или Windows WSL2)

### 1. Первоначальная установка

```bash
git clone https://github.com/gkosarintsev/docker-anonymous.git
cd docker-anonymous

chmod +x *.sh scripts/*.sh warp/*.sh
./install.sh
```

Вывод команды продемонстрирует успешное выполнение запроса через Cloudflare WARP:
```text
====================================================
    🛡️  MINIMAL NODE.JS CLIENT (WARP PROTECTED)  🛡️
====================================================
[+] Proxy Gateway:   http://127.0.0.1:9091
[+] Public IP:       104.28.225.251
[+] Cloudflare WARP: ACTIVE (Protected) (Location: KZ, Colo: DME)
[+] Node User-Agent: got/14.4.2 (https://github.com/sindresorhus/got; Node.js/v20.18.0)
[+] Remote JA3 Hash: 17aaa2e85549966f70290febdc327459
[+] Remote JA4:      t13d1112h1_e70fcb4b08da_8e6e362c5eac
====================================================
✨ [SUCCESS] Internet request completed via Cloudflare WARP.
```

---

## 🛠 Команды управления

### `./install.sh`
Выполняет первоначальную настройку:
- Генерирует начальный профиль `.env`.
- Компилирует TypeScript и собирает Docker-образы.
- Запускает WARP прокси, дожидается прохождения healthcheck.
- Выполняет первый тестовый запрос.

### `./run.sh`
Повторный запуск приложения **без удаления данных**:
- Сохраняет текущий IP-адрес, профиль отпечатка и сессионные данные.
- Запускает контейнер и выполняет запрос.
```bash
# Стандартный запуск
./run.sh

# Запуск с выводом в формате JSON (для пайплайнов)
./run.sh --json
```

### `./reinstall.sh`
Полная переустановка и сброс состояния:
- Останавливает и удаляет контейнеры и тома (`docker compose down -v`).
- Удаляет файл конфигурации `.env`.
- Генерирует **новый профиль отпечатка** (новый порядок шифров и User-Agent).
- **Перекомпилирует** Node.js приложение с нуля (`docker compose build --no-cache`).
- Регистрирует **новую личность Cloudflare WARP** (сменяется внешний IP-адрес).
- Запускает обновленный контур.

```bash
./reinstall.sh
```

---

## 🧪 Автоматическое тестирование

В проект встроен скрипт комплексного тестирования `test.sh`, проверяющий все требования безопасности:

```bash
./test.sh
```

### Что проверяет тест:
1. **Смена IP-адреса**: фиксирует `IP_1`, запускает `reinstall.sh`, проверяет `IP_2 != IP_1`.
2. **Смена отпечатка (JA3/JA4)**: проверяет изменение сетевого TLS отпечатка после переустановки.
3. **Проверка User-Agent**: валидирует, что идентификатор соответствует Node.js и не маскируется под браузер.
4. **Тест Kill-Switch (Fail-Closed)**:
   - Принудительно глушит контейнер `warp-proxy`.
   - Пытается отправить сетевой запрос из `node-app`.
   - Убеждается, что запрос завершился **ошибкой**, и утечки реального IP хоста не произошло.
   - Автоматически восстанавливает работу прокси.

### GitHub Actions CI

Те же самые тесты автоматически запускаются в [GitHub Actions](.github/workflows/ci.yml) при каждом `push` и `pull_request` в `main`. Раннер `ubuntu-latest` имеет полный доступ в интернет и поддерживает Docker-in-Docker, поэтому тесты с реальным WARP-туннелем проходят в CI без дополнительной настройки.

### Пример вывода тестов:
```text
==========================================================
    🧪 RUNNING AUTOMATED ANONYMITY & INTEGRITY TESTS
==========================================================
[TEST 1/3] Capturing baseline state (Run 1)...
  -> Baseline IP:          104.28.225.252
  -> Baseline JA3 Hash:    17aaa2e85549966f70290febdc327459
  -> Baseline JA4:         t13d1112h1_e70fcb4b08da_8e6e362c5eac
  -> Baseline User-Agent:  got/14.4.2 (https://github.com/sindresorhus/got; Node.js/v20.18.0)

[TEST 2/3] Performing full reinstall (Reinstall & Rebuild)...
  (Wiping state, recompiling app, rotating WARP identity and cipher list)
  -> New IP:               104.28.225.251
  -> New JA3 Hash:         f7e77f63f7e2b21f06df8469af1c6608
  -> New JA4:              t13d1212h1_717f5778009e_8e6e362c5eac
  -> New User-Agent:       Node.js/v20.18.0 (linux; x64)

=== VERIFYING REINSTALLATION ROTATIONS ===
  ✅ PASS: IP address changed successfully (104.28.225.252 -> 104.28.225.251)
  ✅ PASS: Node.js TLS Fingerprint rotated successfully!
          Old JA4: t13d1112h1_e70fcb4b08da_8e6e362c5eac
          New JA4: t13d1212h1_717f5778009e_8e6e362c5eac
  ✅ PASS: User-Agent is authentic Node.js client (no browser emulation): Node.js/v20.18.0 (linux; x64)

[TEST 3/3] Testing Fail-Closed / Kill-Switch Protection...
  (Stopping WARP proxy; asserting requests fail closed and host IP is NOT leaked)
  ✅ PASS: Outbound request was completely blocked when WARP proxy was down.
          (Strict fail-closed active: host IP was NOT leaked to the internet).

==========================================================
  🎉 ALL TESTS PASSED! Portfolio readiness confirmed.
==========================================================
```

---

## 📂 Структура репозитория

```text
docker-anonymous/
├── .github/
│   └── workflows/
│       └── ci.yml              # GitHub Actions: тесты с реальным WARP-туннелем в CI
├── Dockerfile                  # Многоэтапная (multi-stage) сборка Node.js runner на Alpine
├── docker-compose.yml          # Спецификация сервисов (warp-proxy + node-app)
├── package.json                # Зависимости проекта (undici, typescript, @types/node)
├── package-lock.json           # Lockfile для воспроизводимых сборок
├── tsconfig.json               # Конфигурация компилятора TypeScript (ES2022)
├── install.sh                  # Скрипт первоначальной установки
├── reinstall.sh                # Скрипт переустановки (полная перекомпиляция + ротация IP и FP)
├── run.sh                      # Скрипт повторного запуска без сброса данных
├── test.sh                     # Автотест смены IP, отпечатка и kill-switch
├── .env.example                # Пример формата .env (без реальных значений)
├── .gitignore                  # Исключения git (node_modules, dist, .env)
├── src/
│   └── index.ts                # Минималистичное Node.js приложение (~60 строк)
├── warp/
│   ├── Dockerfile              # Dockerfile прокси-контейнера Cloudflare WARP
│   └── entrypoint.sh           # Скрипт генерации ключей X25519, регистрации в CF и запуска sing-box
└── scripts/
    └── generate-env.sh         # Генератор профиля TLS шифров и Node.js идентичности
```

---

## 💻 Технический стек

- **Runtime**: Node.js 22 LTS (Alpine Linux)
- **Language**: TypeScript 5.6
- **HTTP Client**: `undici` (`ProxyAgent`, native `fetch`)
- **Proxy/Tunnel**: Cloudflare WARP WireGuard via `sing-box`
- **Containerization**: Docker Compose v2 (Bridge + Service Network Sharing)
- **Security Protocols**: TLS 1.3, OpenSSL Cipher Suites Permutation

---

## ⚖️ Лицензия

Проект распространяется под лицензией [MIT](LICENSE).
Разработано для портфолио в качестве демонстрации навыков проектирования защищенных контейнеризированных сетевых решений.
