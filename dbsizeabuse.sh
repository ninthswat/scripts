#!/bin/bash

SCRIPT_PATH="/usr/local/bin/mysql_db_monitor.sh"
LOG_FILE="/var/log/mysql_db_monitor.log"
CRON_TIME="0 8 * * *"

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

# Создание основного скрипта
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash

EMAIL="{{EMAIL}}"
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="HostFly Мониторинг <support@hostfly.by>"

THRESHOLD_GB=10
MYSQL_DIR="/var/lib/mysql"
EXCLUDE_LIST="mysql performance_schema information_schema sys"
LOG_FILE="/var/log/mysql_db_monitor.log"

send_email() {
    local recipient="$1"
    local subject="$2"
    local body="$3"

    sendEmail -f "$SMTP_FROM" \
              -t "$recipient" \
              -u "$subject" \
              -m "$body" \
              -s "$SMTP_SERVER:$SMTP_PORT" \
              -xu "$SMTP_USER" \
              -xp "$SMTP_PASS" \
              -o tls=no \
              -o message-content-type=text/plain \
              -o message-charset=UTF-8
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

monitor_databases() {
    local hostname
    hostname=$(hostname)
    local now
    now=$(date "+%d.%m.%Y %H:%M:%S")
    local output=""

    for dir in "$MYSQL_DIR"/*; do
        bn=$(basename "$dir")
        if echo "$EXCLUDE_LIST" | grep -qw "$bn"; then
            continue
        fi

        [ -d "$dir" ] || continue

        size_gb=$(du -sBG "$dir" 2>/dev/null | awk '{print $1}' | sed 's/G//')
        if [[ "$size_gb" =~ ^[0-9]+$ ]] && [ "$size_gb" -gt "$THRESHOLD_GB" ]; then
            output="${output}$(printf \"%s GB\t%s\n\" \"$size_gb\" \"$dir\")"
        fi
    done

    if [[ -n "$output" ]]; then
        local message="На сервере $hostname были обнаружены базы данных, превышающие $THRESHOLD_GB ГБ:\n\n"
        message+="$output\n\n"
        message+="Согласно п. 7.1.1 правил пользования, размер одной базы не должен превышать 5 ГБ.\n"
        message+="Команде hostfly необходимо установить владельцев данных баз и уведомить их о нарушении."

        echo -e "[ALERT] Обнаружены превышения:\n$output"
        log_message "ALERT" "Обнаружены превышения. Отправка письма."
        send_email "$EMAIL" "🚨 Большие базы данных на $hostname" "$message"
    else
        echo "[OK] Все базы данных меньше $THRESHOLD_GB ГБ"
        log_message "OK" "Все базы в пределах нормы"
    fi
}

monitor_databases
EOF

# Подставим email в шаблон
sed -i "s/{{EMAIL}}/$EMAIL/" "$SCRIPT_PATH"

# Права
chmod +x "$SCRIPT_PATH"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Обновление cron
crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
( crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH" ) | crontab -

echo "✅ Скрипт установлен: $SCRIPT_PATH"
echo "📩 Email уведомлений: $EMAIL"
echo "🕗 Cron-задача: ежедневно в 08:00"
echo "▶️ Запуск первой проверки прямо сейчас..."

# Запуск сразу
"$SCRIPT_PATH"
