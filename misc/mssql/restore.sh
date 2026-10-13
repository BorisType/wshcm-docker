#!/bin/bash

timeout=3
attempts=100
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

attempt=0
while true;
do
  echo "Sleep for $timeout seconds before executing test connection"
  sleep $timeout

  attempt=$((attempt + 1))
  echo "Test connection to database (attempt $attempt of $attempts)"
  $SQLCMD -S localhost -C -U sa -P "${MSSQL_SA_PASSWORD}" -Q "SELECT 1"

  if [ $? -eq 0 ]; then
    echo "Connection established"
    break
  fi

  if [ $attempt -ge $attempts ]; then
    echo "ERROR: failed to connect to SQL Server after $attempts attempts"
    exit 1
  fi
done;

if [ -e "/tmp/config/db.bak" ]; then
  echo "Start database restoring"
  $SQLCMD -S localhost -C -U "${MSSQL_USERNAME}" -P "${MSSQL_SA_PASSWORD}" -Q 'RESTORE FILELISTONLY FROM DISK = "/tmp/config/db.bak"' | tr -s ' ' | cut -d ' ' -f 1-2 || exit 1
  $SQLCMD -b -S localhost -C -U "${MSSQL_USERNAME}" -P "${MSSQL_SA_PASSWORD}" -Q 'RESTORE DATABASE WTDB FROM DISK = "/tmp/config/db.bak" WITH MOVE "WTDB" TO "/var/opt/mssql/data/WTDB.mdf", MOVE "BLOBS" TO "/var/opt/mssql/data/WTDB_blobs.mdf", MOVE "FT_IDX" TO "/var/opt/mssql/data/WTDB_ft_idx.mdf", MOVE "IDX" TO "/var/opt/mssql/data/WTDB_idx.mdf", MOVE "LOG" TO "/var/opt/mssql/data/T1_WTDB.ldf"' || exit 1
else
  DATABASE_EXISTS=$($SQLCMD -S localhost -C -U sa -P "${MSSQL_SA_PASSWORD}" -Q "IF EXISTS (SELECT name FROM sys.databases WHERE name = 'WTDB') PRINT 'EXISTS'")

  if [[ $DATABASE_EXISTS != "EXISTS" ]]; then
    echo "Database does not exist. Creating it..."
    $SQLCMD -b -S localhost -C -U "${MSSQL_USERNAME}" -P "${MSSQL_SA_PASSWORD}" -i "/tmp/config/create.sql" || exit 1
  else
    echo "Database exist"
  fi
fi

# Маркер готовности БД: healthcheck в wt-mssql.yml ждёт этот файл,
# чтобы wt не стартовал, пока WTDB ещё создаётся/восстанавливается.
touch /tmp/db_init_done

exit 0
