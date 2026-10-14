# wshcm-docker

Запуск WebSoft HCM в Docker с внешней базой данных **PostgreSQL** из одного `compose up`.

Образ WebSoft HCM закрытый и в репозиторий не входит — нужен `hcm_*.tar.gz` с кабинета WebSoft,
загружается через `docker load -i`.

## Источники

- Основа postgres-стека: [wshcmx/docker](https://github.com/wshcmx/docker)
  (идея `wt + postgres + mailpit`, `start.sh` с шаблонизацией `spxml_unibridge_config.xml`,
  `misc/postgres/create_db.sql`).
- Официальный способ установки/обновления: `WT_directory*.zip` + `docker.run`
  (bind-маунты `WebSoftServerForDocker`, `docker load`, `UpgradeLocked`, интерактивный x-shell).
- Вендорские статьи по PostgreSQL и миграции БД (`db set type / db create / db init / db migrate`).

Отличия от `wshcmx/docker` — см. «Что починили» ниже.

## Структура репозитория

```
wt.base.yml        # общий фрагмент сервиса wt (образ, тома, start.sh)
wt-postgres.yml    # ветка PostgreSQL: postgres + wt + proxy + mailpit
wt-mssql.yml       # ветка MSSQL: db + wt + proxy + mailpit
misc/wt/           # start.sh, шаблоны xhttp.ini/is.js/..., overlay/
misc/postgres/     # create_db.sql (инициализация схемы)
misc/mssql/        # entrypoint.sh, restore.sh, create.sql, drop.sql, db.bak
misc/proxy/        # nginx.conf
scripts/smoke.sh   # ожидание готовности портала (200 на /default)
dist/              # hcm_*.tar.gz и WT_directory*.zip (локально, не в git)
```

## Быстрый старт (postgres)

```bash
docker load -i dist/hcm_2025.1.1333.tar.gz
cp .env.example .env   # поправь версии/пароли при необходимости
docker compose -f wt-postgres.yml up -d
./scripts/smoke.sh     # ждёт готовности и проверяет 200 на /default
```

Первый старт долгий (10–20 мин): WT сам дотягивает схему и накатывает ~160 пакетов.
Портал отвечает `302` на `/` когда готов. Вход в каталог `hosts` нужен построчно
на каждый внешний порт, поэтому спереди стоит nginx (см. ниже).
Дефолтный логин стенда: `user1/user1`.

## Диагностика первого старта

`Server started` в логе — ещё не готовность: после него 10–15 минут идёт накат
пакетов, и портал не отвечает. Прогресс-бара нет, признаки фазы установки такие:

- `docker logs <project>-wt-1 | grep "Installation proc pack"` — очередь пакетов,
  набирается в первые минуты после старта;
- `docker logs <project>-wt-1 | grep "Too long handle statements"` — собственно
  установка (обработчик `wtv_global_handle_statements_update.js` занят пакетами),
  повторяется раз в ~1–2 мин; последняя запись ≈ конец установки;
- веб-запросы в это время либо висят, либо отдают
  `Current host (wt:80) is not found in the list of WebSoft HCM access allowed hosts` —
  это нормально: строка `*:80` в `dbo.hosts` создаётся сразу, но кэш узлов
  собирается только по завершении установки;
- `docker exec <project>-wt-1 tail -5 /WebsoftServer/Logs/statements_process_*.log`.

Признак готовности — ответ портала, а не строка в логе:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/default   # 200
```

## Известные предупреждения (не баги)

- `Warning: Database version (X) may be incompatible` в
  `/WebsoftServer/Logs/spxml_unibridge_*.log` — печатается на каждом старте в обеих
  ветках (PG: `1.23.4.21`, MSSQL: `1.8.11.1`). Значения приходят из вендорских
  `create_db.sql` / `create.sql` (функция `getdbversion`) и не совпадают с версией
  сборки; на работу не влияет — установка, запись данных и Lucene-индексы проходят
  штатно. Менять значение без вендорской доки не стоит: оно важно только для
  утилит `db set type / db create / db init / db migrate`.
- MSSQL: `spxml_check_db()` возвращает 0 и default fulltext-каталога в БД нет —
  в Linux-образе SQL Server Full-Text Search не установлен
  (`SERVERPROPERTY('IsFullTextInstalled') = 0`), поэтому строка
  `CREATE FULLTEXT CATALOG` в `create.sql` закомментирована. WT использует Lucene
  (`LuceneFTIndex=true`), SQL-FTS не нужен.
- PG: `create_db.sql` прописывает `OWNER TO root` — при смене `POSTGRES_USERNAME`
  init-скрипт упадёт (роль `root` не существует). Оставляй `root` или правь скрипт.

## Авторизация (для инструментов/агентов)

Вход — HTTP Basic (`portal_auth_type=basic`): `/default` отдаёт только страницу
с кнопкой «Вход», дальше нативная браузерная диалог-форма, которая не кликается
автоматизацией. Проверка: `curl -u user1:user1 .../home` → `200`, без креды → `401`.
Playwright — задать креды в контексте и идти сразу на `/home`:

```js
const ctx = await browser.newContext({
  httpCredentials: { username: 'user1', password: 'user1' },
});
await page.goto('http://127.0.0.1:8080/home');
```

## Кастомизация (overlay)

Свои файлы и замены коробочных кладём в `misc/wt/overlay/` (в контейнере —
`/tmp/wt/overlay`). `start.sh` при запуске копирует содержимое поверх
`/WebsoftServer/`, так правки переживают пересборку контейнера.
Содержимое overlay в git не попадает (см. `.gitignore`) — это локальные файлы.
Hot-reload у WT нет — после изменений: `docker compose -f wt-postgres.yml restart wt`.

Служебные `xHttp.ini`, `spxml_unibridge_config.xml`, `is.js` генерируются
`start.sh` с подстановкой env, поэтому overlay их перезаписывать не должен:
при конфликте контейнер не стартует с явной ошибкой в логе.
Осознанная замена — `OVERLAY_ALLOW_PROTECTED=1` в `.env`.

Пример раскладки:

```
misc/wt/overlay/wt/web/my_page.html
misc/wt/overlay/components/<component>/<file>.js
```

Что overlay не покрывает — объекты в БД (веб-шаблоны, LP-конфиги): они правятся
через админку/x-shell/SQL, но часто ссылаются на файлы, которые удобно возить overlay'ем.

## Сервисы и порты (по умолчанию из `.env.example`)

| Сервис    | Образ                  | Наружу       | Внутрь | Назначение                        |
|-----------|------------------------|--------------|--------|-----------------------------------|
| `wt`      | `websoft/hcm:2025.1…`  | `80`         | `80`   | сам WebSoft HCM (`./xhttp.out`)   |
| `postgres`| `postgres:16`          | `5432`       | `5432` | БД `WTDB`, схема из `create_db.sql` |
| `email`   | `axllent/mailpit`      | `1025/8025`  | `1025/8025` | SMTP-заглушка + веб-интерфейс |
| `proxy`   | `nginx:stable-alpine`  | `8080`       | `80`   | единая точка входа (см. ниже)     |

## Почему спереди nginx

WT привязывает доступ к паре `host:port` из каталога `hosts`
(`get_cur_hosts`: точное совпадение или `*:<порт>`).
Без прокси каждый новый внешний порт = новая строка в каталоге.

Прокси жёстко нормализует `Host` в `wt:80`, а `Location` переписывает
обратно на внешний хост. Итог: в каталоге навсегда одна строка `*:80`,
внешний порт меняется свободно. Проверено с произвольными `Host`.

## Что починили относительно wshcmx/docker

- `WT_IMAGE` под реальный образ, `POSTGRES_DB=WTDB` (БД создаёт сам образ,
  а не init-скрипт — внутри `/docker-entrypoint-initdb.d` это не работает).
- Путь данных postgres: `/var/lib/postgresql/data` (было неверно, данные не персистились).
- `postgres:16` вместо плавающего `postgres`; `healthcheck pg_isready` +
  `depends_on healthy` для `wt` (как в mssql-ветке).
- Порты всех сервисов через `.env`, а не хардкод.
- `start.sh`: регистр `xhttp.ini` (на Linux падало).
- `create_db.sql`: убран `CREATE DATABASE`, починен `table_schema=@schema`.
- `max_connections 100 → 300`: WT держит десятки висящих коннектов,
  дефолтный пул выбирался с `FATAL: sorry, too many clients already`.
- `extra_hosts: host.docker.internal:host-gateway` (на Linux имя не резолвится само).
- `+proxy` (nginx): нормализация `Host → wt:80`, `proxy_redirect` наружу.
- `+WebSocket` в nginx (`Upgrade`/`Connection: upgrade`): без этого
  `/services/*_ws_service` отдавал 500 и живые уведомления не работали.

## MSSQL-ветка

`wt-mssql.yml` — база как в оригинале плюс фиксы:
`docker compose -f wt-mssql.yml up -d`, БД `WTDB` создаёт `restore.sh`
(из `db.bak` в `misc/mssql/` либо из `create.sql`). `wt` ждёт healthcheck `db`:
маркер `/tmp/db_init_done` появляется только после создания/восстановления БД,
а не когда sqlservr просто поднялся. Что исправлено относительно оригинала:
`extra_hosts` для `wt` (ConnectionString и SMTP ходят через `host.docker.internal`),
том `mssql-data` под `/var/opt/mssql` (данные переживают пересоздание контейнера),
`restore.sh` коннектится к `localhost`, а не `host.docker.internal` (на Linux имя
не резолвится и скрипт зависал), лимит попыток подключения и `-b` для честных
кодов возврата, образ запинен `2022-latest`, добавлен nginx-прокси как в
PG-ветке (вход через 8080, WT видит `Host: wt:80`). Полный прогон проверен:
первый старт ~4 мин, вход `user1/user1`, в `dbo.hosts` строка `*:80`.
Свои дампы кладите в `misc/mssql/db.bak`.
