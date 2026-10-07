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

## Быстрый старт (postgres)

```bash
docker load -i hcm_2025.1.1333.tar.gz
cp .env.example .env   # поправь версии/пароли при необходимости
docker compose -f wt-postgres.yml up -d
docker logs -f <project>-wt-1   # ждём "Server started"
```

Первый старт долгий (10–20 мин): WT сам дотягивает схему и накатывает ~160 пакетов.
Портал отвечает `302` на `/` когда готов.

Вход в каталог `hosts` нужен построчно на каждый внешний порт,
поэтому спереди стоит nginx (см. ниже). Дефолтный логин стенда: `user1/user1`.

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

## MSSQL-ветка

`wt-mssql.yml` — как в оригинале (не обкатывалась здесь):
`docker compose -f wt-mssql.yml up -d`, БД `WTDB` создаёт `restore.sh`
(из `db.bak` либо `create.sql`), `wt` ждёт `healthy`.
