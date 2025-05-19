#!/bin/bash

SCRIPT_PATH="/usr/local/bin/cpanel_quota_audit.sh"
CRON_TIME="0 4 * * 1"  # Понедельник 04:00
LOG_FILE="/var/log/cpanel_quota_audit.log"

# Проверка и установка sendEmail
if ! command -v sendEmail &>/dev/null; then
    echo "[INFO] sendEmail не найден, устанавливаю..."
    if command -v apt &>/dev/null; then
        apt update && apt install -y sendemail
    elif command -v yum &>/dev/null; then
        yum install -y sendEmail
    else
        echo "[ERROR] Не удалось установить sendEmail: не найден apt или yum"
        exit 1
    fi
fi

# Запрос email
read -p "Введите email для уведомлений: " EMAIL
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-z]{2,}$ ]]; then
    echo "❌ Некорректный email." >&2
    exit 1
fi

# Создание скрипта проверки
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash

EMAIL="{{EMAIL}}"
THRESHOLD_GB=100
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="Disk Monitor <noreply@hostfly.by>"

send_email() {
    local subject="$1"
    local body="$2"

    sendEmail -f "$SMTP_FROM" \
              -t "$EMAIL" \
              -u "$subject" \
              -m "$body" \
              -s "$SMTP_SERVER:$SMTP_PORT" \
              -xu "$SMTP_USER" \
              -xp "$SMTP_PASS" \
              -o tls=no \
              -o message-content-type=text/plain \
              -o message-charset=UTF-8
}

log() {
    echo "[$(date '+%F %T')] $1" >> /var/log/cpanel_quota_audit.log
}

run_audit() {
    local hostname=$(hostname)
    local report=""
    local no_limit_users=()

    log "Начат аудит квот"

    # Список пользователей без квоты
    for userfile in /var/cpanel/users/*; do
        user=$(basename "$userfile")
        limit=$(grep -i "^QUOTA=" "$userfile" | cut -d= -f2)
        if [[ -z "$limit" || "$limit" == "0" ]]; then
            no_limit_users+=("$user")
        fi
    done

    for user in "${no_limit_users[@]}"; do
        homedir="/home/$user"
        [ -d "$homedir" ] || continue

        usage_kb=$(du -sk "$homedir" 2>/dev/null | awk '{print $1}')
        usage_gb=$((usage_kb / 1024 / 1024))

        if [ "$usage_gb" -gt "$THRESHOLD_GB" ]; then
            report+="Пользователь: $user\n"
            report+="Домашняя директория: $homedir\n"
            report+="Использование: ${usage_gb} GB\n"

            top_files=$(find "$homedir" -type f -printf "%s %p\n" 2>/dev/null | sort -rn | head -n 10 | awk '{ printf "%6.2f MB\t%s\n", $1/1024/1024, $2 }')
            top_dirs=$(du -sh "$homedir"/* 2>/dev/null | sort -rh | head -n 10)

            category_usage=$(du -sh "$homedir"/{mail,public_html,.cpanel,.trash,logs} 2>/dev/null | awk '{printf "%-10s %s\n", $1, $2}')
            top_extensions=$(find "$homedir" -type f 2>/dev/null | awk -F. '/\./ {print $NF}' | awk '{count[$1]++} END {for (e in count) print count[e], e}' | sort -rn | head -n 10)
            ext_sizes=$(find "$homedir" -type f -exec du -b {} + 2>/dev/null | awk -F. '{ext=$NF} {a[ext]+=$1} END {for (e in a) printf "%8.2f MB\t%s\n", a[e]/1024/1024, e}' | sort -rn | head -10)

            report+="\nТоп 10 файлов:\n$top_files\n"
            report+="\nТоп 10 папок:\n$top_dirs\n"
            report+="\nИспользование по категориям:\n$category_usage\n"
            report+="\nТоп 10 типов файлов (по частоте):\n$top_extensions\n"
            report+="\nОбщий объём по расширениям:\n$ext_sizes\n"
            report+="\n----------------------------------------\n"
        fi
    done

    if [[ -n "$report" ]]; then
        log "Найдены пользователи без квот с превышением > ${THRESHOLD_GB} ГБ"
        send_email "🚨 Пользователи без лимита, превысившие ${THRESHOLD_GB} ГБ на $hostname" "$report"
    else
        log "Все пользователи в пределах квот"
    fi
}

run_audit
EOF

# Подстановка email
sed -i "s|{{EMAIL}}|$EMAIL|" "$SCRIPT_PATH"

# Права
chmod +x "$SCRIPT_PATH"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Установка cron
crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
( crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH" ) | crontab -

echo "✅ Скрипт установлен: $SCRIPT_PATH"
echo "📩 Email уведомлений: $EMAIL"
echo "📆 Проверка будет выполняться: еженедельно по понедельникам в 04:00"
echo "▶️ Запуск первой проверки прямо сейчас..."

"$SCRIPT_PATH"
