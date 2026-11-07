# 🛡️ Docker Anonymous: Minimal Node.js Stealth Runtime

[![CI](https://github.com/gkosarintsev/docker-anonymous/actions/workflows/ci.yml/badge.svg)](https://github.com/gkosarintsev/docker-anonymous/actions/workflows/ci.yml)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2%2B-blue.svg?logo=docker)](https://www.docker.com/)
[![Node.js](https://img.shields.io/badge/Node.js-v22%20LTS-green.svg?logo=node.js)](https://nodejs.org/)
[![Cloudflare WARP](https://img.shields.io/badge/Proxy-Cloudflare%20WARP-orange.svg?logo=cloudflare)](https://developers.cloudflare.com/warp-client/)
[![Anti-Fingerprint](https://img.shields.io/badge/Anti--Fingerprint-JA3%2FJA4-purple.svg)](#-защита-от-fingerprint)
[![Kill-Switch](https://img.shields.io/badge/Kill--Switch-Fail--Closed-red.svg)](#-механизм-fail-closed-kill-switch)

Минималистичное консольное приложение на **Node.js (TypeScript)** в изолированном **Docker**-окружении, которое делает интернет-запросы через **Cloudflare WARP** (WireGuard) и меняет TLS-отпечаток (JA3/JA4) при каждом перезапуске.

Ключевой принцип проекта: **сам Node.js код — минимален** (~70 строк, только `fetch` через `undici.ProxyAgent`). Всю инфраструктурную сложность — проксирование, ротацию IP, генерацию отпечатков, сетевую изоляцию — берёт на себя внешнее Docker-окружение.

---

## 📑 Содержание

- [Ключевые возможности](#-ключевые-возможности)
- [Архитектура](#-архитектура)
- [Защита от Fingerprint](#-защита-от-fingerprint)
- [Fail-Closed Kill-Switch](#-механизм-fail-closed-kill-switch)
- [Быстрый старт](#-быстрый-старт)
- [Команды управления](#-команды-управления)
- [Автоматические тесты](#-автоматические-тесты)
- [Структура репозитория](#-структура-репозитория)
- [Технический стек](#-технический-стек)

---

## ✨ Ключевые возможности

| Возможность | Реализация |
|---|---|
| Маршрутизация через Cloudflare WARP | WireGuard-туннель через `sing-box` |
| Ротация IP при переустановке | Новая пара ключей X25519 + новая учётная запись CF |
| Защита от TLS-фингерпринтинга | Перестановка порядка OpenSSL-шифров (`NODE_OPTIONS`) |
| Аутентичный Node.js профиль | User-Agent из пула реальных Node.js HTTP-клиентов |
| Абсолютный fail-closed | Если WARP недоступен — запросы блокируются, утечка IP невозможна |
| Минималистичный код приложения | `src/index.ts` — ~70 строк, нет самописных сокетов |
| Non-root контейнер | Docker образ запускается от пользователя `appuser` |
| CI в GitHub Actions | Полный прогон тестов с реальным WARP-туннелем |

---

## 🏛️ Архитектура

```
┌─────────────────────────────────────────────────────────┐
│                   Docker Host (Bridge)                   │
│                                                          │
│  ┌─────────────────────┐     ┌───────────────────────┐  │
│  │  node-anonymous-app  │     │  warp-proxy-service   │  │
│  │  node:22-alpine      │     │  sing-box WireGuard   │  │
│  │                      │     │                       │  │
│  │  • fetch() via undici│────▶│  Mixed proxy :9091    │  │
│  │  • Injected ciphers  │ lo  │  X25519 registration  │  │
│  │  • Injected UA       │     │  MTU 1200 optimised   │  │
│  │  • Non-root user     │     │                       │  │
│  └─────────────────────┘     └──────────┬────────────┘  │
│       ▲ network_mode:                   │               │
│       │ service:warp-proxy              │ WireGuard UDP  │
│       │ (shared namespace)              │               │
│       │                                 ▼               │
│  BLOCKED ❌                   Cloudflare Edge (warp=on)  │
│  (zero direct WAN)                      │               │
└─────────────────────────────────────────┼───────────────┘
                                          ▼
                                   Internet destination
```

**Ключевое архитектурное решение** — `network_mode: service:warp-proxy`.  
`node-app` не имеет собственного сетевого интерфейса: он разделяет сетевой namespace контейнера `warp-proxy`. Если `warp-proxy` упал — порт 9091 исчезает мгновенно, и `node-app` физически не имеет маршрута в интернет.

---

## 🔍 Защита от Fingerprint

### Почему НЕ эмуляция браузера?

Маскировка Node.js под браузер (`User-Agent: Mozilla/5.0`, заголовки `Sec-Ch-Ua`) мгновенно детектируется современными WAF-системами (Cloudflare Turnstile, Akamai, DataDome):
- TLS ClientHello от `node` принципиально отличается от Chromium/Firefox по набору и порядку cipher suites, GREASE-значениям, наборам расширений.
- Поведенческая аномалия (HTTP/2 stream priorities, timing) немедленно выдаёт автоматизацию.

### Стратегия проекта: аутентичный Node.js профиль + ротация отпечатка

```
scripts/generate-env.sh
   ↓ перемешивает пул из 10 OpenSSL cipher suites
   ↓ выбирает 6–9 случайных в случайном порядке
   ↓ записывает NODE_OPTIONS=--tls-cipher-list=ECDHE-ECDSA-AES256-GCM-SHA384:...
         ↓
   .env файл
         ↓
   docker run --env-file .env
         ↓
   node binary читает NODE_OPTIONS ДО запуска любого JS-кода  ← runtime, не compile-time
         ↓
   TLS ClientHello с этим порядком шифров
         ↓
   tls.peet.ws видит изменённые JA3 / JA4
```

> **NODE_OPTIONS — это runtime**, а не compile-time параметр. Скомпилированный TypeScript ничего не знает о шифрах: он просто вызывает `fetch()`. Менять fingerprint можно для уже собранного образа, просто передав другую переменную окружения через `--env-file` — пересборка не нужна.

### Что ротируется при `./reinstall.sh`

| Параметр | Механизм |
|---|---|
| Выходной IP | Новая пара ключей X25519 → новая учётная запись Cloudflare WARP |
| TLS JA3 / JA4 | Перестановка `--tls-cipher-list` в `NODE_OPTIONS` |
| User-Agent | Случайный выбор из пула Node.js HTTP-библиотек |
| Machine ID | 128-битный случайный идентификатор |

---

## 🛑 Механизм Fail-Closed (Kill-Switch)

Fail-closed гарантирует: **если WARP недоступен — ни один запрос не уходит с реального IP хоста**.

Реализован на двух независимых уровнях:

**Уровень 1 — Docker сеть (аппаратный):**  
`node-app` использует `network_mode: service:warp-proxy`. У контейнера нет собственного сетевого интерфейса и шлюза — только shared namespace от `warp-proxy`. Если `warp-proxy` недоступен, порт 9091 исчезает физически.

**Уровень 2 — Приложение (программный):**  
В `src/index.ts` первые строки кода:
```typescript
const proxyUrl = process.env.HTTP_PROXY || process.env.HTTPS_PROXY;
if (!proxyUrl) { process.exit(1); }                      // ← нет прокси = стоп
setGlobalDispatcher(new ProxyAgent({ uri: proxyUrl }));  // ← все запросы через прокси
```
Если `HTTP_PROXY` не задан или порт недоступен — `fetch()` выбрасывает `ECONNREFUSED` → `process.exit(1)`. Прямой выход в сеть программно исключён.

---

## 🚀 Быстрый старт

### Требования

- **Docker** и **Docker Compose v2+**
- **Bash** (Linux, macOS, Windows WSL2)

### Установка и запуск

```bash
git clone https://github.com/gkosarintsev/docker-anonymous.git
cd docker-anonymous

chmod +x *.sh scripts/*.sh
./install.sh
```

Ожидаемый вывод:
```
====================================================
    🛡️  MINIMAL NODE.JS CLIENT (WARP PROTECTED)  🛡️
====================================================
[+] Proxy Gateway:   http://127.0.0.1:9091
[+] Public IP:       104.28.225.251
[+] Cloudflare WARP: ACTIVE ✓ (loc=KZ colo=DME)
[+] Node User-Agent: got/14.4.2 (https://github.com/sindresorhus/got; Node.js/v20.18.0)
[+] Remote JA3 Hash: 17aaa2e85549966f70290febdc327459
[+] Remote JA4:      t13d1212h1_717f5778009e_8e6e362c5eac
====================================================
✨ [SUCCESS] Request completed via Cloudflare WARP.
```

---

## 🛠️ Команды управления

### `./install.sh`

Первоначальная установка:
1. Генерирует `.env` с TLS-профилем (если отсутствует).
2. Компилирует TypeScript и собирает Docker-образы.
3. Регистрирует WARP-идентичность, дожидается `healthy`.
4. Выполняет первый запрос.

### `./reinstall.sh`

Полная переустановка с ротацией всего:
```bash
./reinstall.sh          # переустановить и запустить
./reinstall.sh --json   # то же, но JSON-вывод (для пайплайнов)
```
1. `docker compose down -v` — стоп + удаление томов.
2. Генерация нового `.env` (новые шифры, новый UA, новый MACHINE_ID).
3. `docker compose build --no-cache` — чистая перекомпиляция.
4. Регистрация новой учётной записи WARP → **новый внешний IP**.

### `./run.sh`

Повторный запуск без удаления данных:
```bash
./run.sh                # стандартный вывод
./run.sh --json         # JSON (для скриптов / CI)
```
Если `warp-proxy` не запущен — стартует автоматически.

### `./test.sh`

Прогон всех автотестов:
```bash
./test.sh
```

---

## 🧪 Автоматические тесты

Скрипт `test.sh` проверяет все требования безопасности. Те же тесты запускаются в **[GitHub Actions CI](https://github.com/gkosarintsev/docker-anonymous/actions)** при каждом push.

### Три теста:

**TEST 1** — снимает baseline (IP, JA3, JA4, UA).

**TEST 2** — выполняет полный reinstall, сравнивает:
- IP изменился *(advisory: Cloudflare может выдать тот же edge)*
- **JA4 изменился** *(обязательно — основная проверка)*
- User-Agent аутентичный Node.js

**TEST 3** — Kill-Switch:
- Останавливает `warp-proxy`
- Пытается выполнить запрос
- **Убеждается, что запрос упал** (ECONNREFUSED)

### Пример вывода:

```
==========================================================
    🧪 RUNNING AUTOMATED ANONYMITY & INTEGRITY TESTS
==========================================================
[TEST 1/3] Capturing baseline state...
  -> IP:         104.28.225.252
  -> JA4:        t13d912h1_78c7e1c75613_8e6e362c5eac
  -> User-Agent: Node.js/v20.17.0 (linux; x64)

[TEST 2/3] Performing full reinstall...
  -> IP:         104.28.225.252
  -> JA4:        t13d1212h1_054af76f2497_8e6e362c5eac
  -> User-Agent: got/14.4.2 (...; Node.js/v20.18.0)

=== VERIFYING ROTATIONS ===
  ⚠️  NOTE: Same Cloudflare edge IP. WARP X25519 credentials were still rotated.
  ✅ PASS: TLS fingerprint rotated
           JA4: t13d912h1_78c7e1c75613_... → t13d1212h1_054af76f2497_...
  ✅ PASS: User-Agent is authentic Node.js client

[TEST 3/3] Kill-switch — host IP must NOT leak when WARP proxy is down...
  ✅ PASS: Request blocked (ECONNREFUSED on proxy). Host IP was NOT exposed.

==========================================================
  🎉 ALL TESTS PASSED!
==========================================================
```

---

## 📂 Структура репозитория

```text
docker-anonymous/
├── .github/
│   └── workflows/
│       └── ci.yml              # GitHub Actions: полный прогон с реальным WARP
├── src/
│   └── index.ts                # Приложение (~70 строк): fetch через undici.ProxyAgent
├── warp/
│   ├── Dockerfile              # WARP proxy образ (sing-box WireGuard)
│   └── entrypoint.sh           # Генерация X25519, регистрация в CF API, запуск sing-box
├── scripts/
│   ├── generate-env.sh         # Ротация TLS cipher suite + User-Agent + Machine ID
│   └── wait-for-warp.sh        # Shared helper: polling healthcheck с deadline
├── Dockerfile                  # Multi-stage: builder (tsc) + runner (non-root Alpine)
├── docker-compose.yml          # warp-proxy + node-app (shared network namespace)
├── package.json                # Зависимости: undici, typescript, @types/node
├── package-lock.json           # Lockfile для воспроизводимых сборок
├── tsconfig.json               # TypeScript: target ES2022, strict mode
├── install.sh                  # Первичная установка
├── reinstall.sh                # Полный вайп + пересборка + ротация IP/FP
├── run.sh                      # Повторный запуск без вайпа
├── test.sh                     # Автотесты: IP, JA3/JA4, kill-switch
├── .env.example                # Пример формата .env
└── .gitignore                  # node_modules/, dist/, .env, data/
```

---

## 💻 Технический стек

| Компонент | Технология |
|---|---|
| Runtime | Node.js 22 LTS (Alpine Linux) |
| Язык | TypeScript 5.6, строгий режим |
| HTTP клиент | `undici` (ProxyAgent + native fetch) |
| Proxy/Tunnel | Cloudflare WARP WireGuard via `sing-box` |
| Контейнеризация | Docker Compose v2 (service network sharing) |
| Anti-Fingerprint | OpenSSL cipher suite permutation via `NODE_OPTIONS` |
| Безопасность | Non-root container, fail-closed proxy enforcement |
| CI | GitHub Actions (ubuntu-latest, реальный WARP-туннель) |

---

## ⚖️ Лицензия

MIT — разработано для портфолио как демонстрация навыков проектирования защищённых контейнеризированных сетевых решений.
