#!/bin/bash

if [ -f .env ]; then
  . .env
fi

cat /tmp/wt/xhttp.ini > /WebsoftServer/xHttp.ini
cat /tmp/wt/spxml_unibridge_config.xml > /WebsoftServer/spxml_unibridge_config.xml
cat /tmp/wt/is.js > /WebsoftServer/is.js

sed -i "s/\$SQL_TYPE/$SQL_TYPE/g" /WebsoftServer/spxml_unibridge_config.xml
sed -i "s/\$SQL_USERNAME/$SQL_USERNAME/g" /WebsoftServer/spxml_unibridge_config.xml
sed -i "s/\$SQL_PASSWORD/$SQL_PASSWORD/g" /WebsoftServer/spxml_unibridge_config.xml

sed -i "s/\$MAILPIT_DOCKER_SMTP_PORT/$MAILPIT_DOCKER_SMTP_PORT/g" /WebsoftServer/is.js
sed -i "s/\$SMTP_LOGIN/$SMTP_LOGIN/g" /WebsoftServer/is.js
sed -i "s/\$SMTP_PASSWORD/$SMTP_PASSWORD/g" /WebsoftServer/is.js


if [ ! -f "/fifd" ]; then
  touch /WebsoftServer/fifd
  touch /fifd
fi

# overlay: кастомные файлы и замены коробочных, копируются поверх /WebsoftServer.
# Служебные файлы генерируются выше (xHttp.ini, spxml_unibridge_config.xml, is.js)
# с подстановкой env — overlay не должен их молча перезатирать.
if [ -d /tmp/wt/overlay ]; then
  for f in xHttp.ini spxml_unibridge_config.xml is.js; do
    if [ -e "/tmp/wt/overlay/$f" ] && [ "${OVERLAY_ALLOW_PROTECTED}" != "1" ]; then
      echo "ERROR: overlay/$f конфликтует со служебным файлом, который генерируется при старте."
      echo "       Убери файл из overlay или задай OVERLAY_ALLOW_PROTECTED=1 для осознанной замены."
      exit 1
    fi
  done
  cp -a /tmp/wt/overlay/. /WebsoftServer/
  rm -f /WebsoftServer/.gitkeep
  echo "overlay: applied from /tmp/wt/overlay"
fi

./xhttp.out