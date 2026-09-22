#!/bin/sh
# =============================================================================
#  设置应用数据库账号的密码
#
#  为什么需要这个脚本：
#    V1__init_schema.sql 里创建了 app_rw 角色，但密码是占位符
#    'CHANGE_ME_ON_DEPLOY'。生产环境必须在初始化时换成 .env 里的真实密码。
#
#  执行时机：
#    docker-entrypoint-initdb.d 按文件名字母序执行，
#    10-schema.sql（建表）先跑，本脚本（20-）后跑。
#    仅在数据目录为空（首次初始化）时执行一次。
# =============================================================================

set -e

if [ -z "$APP_DB_USER" ] || [ -z "$APP_DB_PASSWORD" ]; then
    echo "[init] 跳过：未设置 APP_DB_USER / APP_DB_PASSWORD"
    exit 0
fi

if [ "$APP_DB_USER" = "postgres" ] || [ "$APP_DB_USER" = "$DB_SUPERUSER" ]; then
    echo "[init] 错误：应用账号不能使用超级用户名。"
    exit 1
fi

echo "[init] 正在设置应用账号 ${APP_DB_USER} 的密码…"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
ALTER ROLE "${APP_DB_USER}" WITH LOGIN PASSWORD '${APP_DB_PASSWORD}';
EOSQL

echo "[init] 完成。"
echo "[init] 自检："
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c \
  "SELECT rolname, rolsuper, rolcanlogin FROM pg_roles WHERE rolname = '${APP_DB_USER}';"
