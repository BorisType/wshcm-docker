#!/bin/bash
# Ждёт готовности портала через nginx-прокси (ответ 200 на /default).
# Использование: ./scripts/smoke.sh [число_попыток]  (по умолчанию 60, шаг 10с)

if [ -f .env ]; then
  . .env
fi

PORT=${PROXY_HOST_PORT:-8080}
URL="http://127.0.0.1:${PORT}/default"
ATTEMPTS=${1:-60}
INTERVAL=10

for i in $(seq 1 "$ATTEMPTS"); do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$URL" || true)
  echo "$(date +%H:%M:%S) $URL -> $code"
  if [ "$code" = "200" ]; then
    echo "Портал готов: $URL"
    exit 0
  fi
  sleep "$INTERVAL"
done

echo "Портал не ответил 200 за $((ATTEMPTS * INTERVAL)) секунд"
exit 1
