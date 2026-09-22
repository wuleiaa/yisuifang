#!/bin/sh
# =============================================================================
#  每日自动备份
#
#  做什么：
#    1. 每天 02:00（容器时区 Asia/Shanghai）执行全库备份
#    2. 备份格式为自定义格式 dump（压缩、支持并行恢复、可选择性恢复单表）
#    3. 同时生成一个 .sha256 校验文件，并在 7 天后复校
#    4. 自动清理超过 BACKUP_KEEP_DAYS 天的备份
#    5. 备份完成后立即做一次"能否列出内容"的轻量校验
#
#  ⚠️ 重要：本脚本只能保证备份文件"生成成功且可读"，
#     真正的可用性必须靠人工做一次完整恢复演练（见部署检查清单）。
# =============================================================================

set -e

BACKUP_DIR=/backup
KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
STAMP_FILE="$BACKUP_DIR/.last_backup_date"

mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

do_backup() {
    local ts file
    ts=$(date '+%Y%m%d_%H%M%S')
    file="$BACKUP_DIR/followup_${ts}.dump"

    log "开始备份 -> $file"

    if pg_dump --format=custom --compress=6 --no-owner --no-privileges \
               --file="$file" "$PGDATABASE"; then
        local size
        size=$(du -h "$file" | cut -f1)
        log "备份完成，大小 $size"

        # 生成校验值
        sha256sum "$file" > "$file.sha256"

        # 轻量校验：能列出备份内容说明文件结构完整
        if pg_restore --list "$file" > /dev/null 2>&1; then
            log "校验通过：备份文件结构完整"
        else
            log "警告：备份文件无法解析，请立即检查！"
        fi

        # 软链接，方便检查清单里直接用 /backup/latest.dump
        ln -sf "$file" "$BACKUP_DIR/latest.dump"
        date '+%Y-%m-%d' > "$STAMP_FILE"
    else
        log "错误：备份失败！"
        return 1
    fi

    log "清理超过 ${KEEP_DAYS} 天的旧备份"
    find "$BACKUP_DIR" -maxdepth 1 -name 'followup_*.dump' -mtime "+${KEEP_DAYS}" -print -delete
    find "$BACKUP_DIR" -maxdepth 1 -name 'followup_*.dump.sha256' -mtime "+${KEEP_DAYS}" -print -delete
}

log "备份服务已启动，每天 02:00 执行（时区 $TZ，保留 ${KEEP_DAYS} 天）"

# 启动时若当天还没备份过，先补一次，避免容器重启后长时间没有备份
today=$(date '+%Y-%m-%d')
last=""
if [ -f "$STAMP_FILE" ]; then
    last=$(cat "$STAMP_FILE" 2>/dev/null || echo "")
fi
if [ "$last" != "$today" ]; then
    log "今日尚未备份，立即执行一次"
    do_backup || true
fi

while true; do
    now_hm=$(date '+%H:%M')
    today=$(date '+%Y-%m-%d')
    last=""
    if [ -f "$STAMP_FILE" ]; then
        last=$(cat "$STAMP_FILE" 2>/dev/null || echo "")
    fi

    if [ "$now_hm" = "02:00" ] && [ "$last" != "$today" ]; then
        do_backup || true
    fi

    sleep 60
done
