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

# Создание скрипта мониторинга
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

EMAIL="$EMAIL"
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
    local recipient="\$1"
    local subject="\$2"
    local body="\$3"

    sendEmail -f "\$SMTP_FROM" \\
              -t "\$recipient" \\
              -u "\$subject" \\
              -m "\$body" \\
              -s "\$SMTP_SERVER:\$SMTP_PORT" \\
              -xu "\$SMTP_USER" \\
              -xp "\$SMTP_PASS" \\
              -o tls=no \\
              -o message-content-type=text/plain \\
              -o message-charset=UTF-8
}

log_message() {
    local level="\$1"
    local message="\$2"
    local timestamp
    timestamp=\$(date "+%Y-%m-%d %H:%M:%S")
    echo "[\$timestamp] [\$level] \$message" >> "\$LOG_FILE"
}

monitor_databases() {
    local hostname=\$(hostname)
    local now=\$(date "+%d.%m.%Y %H:%M:%S")
    local raw_output=""

    for dir in "\$MYSQL_DIR"/*; do
        bn=\$(basename "\$dir")
        if echo "\$EXCLUDE_LIST" | grep -qw "\$bn"; then
            continue
        fi

        [ -d "\$dir" ] || continue

        size_gb=\$(du -sBG "\$dir" 2>/dev/null | awk '{print \$1}' | sed 's/G//')
        if [[ "\$size_gb" =~ ^[0-9]+\$ ]] && [ "\$size_gb" -gt "\$THRESHOLD_GB" ]; then
            raw_output="\${raw_output}\n\${size_gb} GB\t\${dir}"
        fi
    done

    if [[ -n "\$raw_output" ]]; then
        local header="🚨 ВНИМАНИЕ: Обнаружены превышения по объёму MySQL-баз данных на сервере \$hostname\n"
        header+="\n==============================================\n"
        header+="Размер    | База данных\n"
        header+="----------|-------------------------------------\n"

        local formatted=""
        while IFS= read -r line; do
            size=\$(echo "\$line" | awk '{print \$1}')
            db=\$(echo "\$line" | awk '{\$1=""; print \$0}' | sed 's/^ *//')
            formatted+="\$(printf \"%-9s | %s\\n\" \"\$size\" \"\$db\")"
        done <<< "\$(echo -e \"\$raw_output\")"

        local footer="==============================================\n"
        footer+="\n⚠️ Согласно пункту 7.1.1 правил пользования, размер одной базы не должен превышать 5 ГБ.\n"
        footer+="📌 Необходимо определить владельцев баз и уведомить их о нарушении."

        local message="\$header\$formatted\$footer"

        echo -e "[ALERT] Обнаружены превышения:\n\$formatted"
        log_message "ALERT" "Обнаружены превышения. Отправка письма."
        send_email "\$EMAIL" "🚨 Большие базы данных на \$hostname" "\$message"
    else
        echo "[OK] Все базы данных меньше \$THRESHOLD_GB ГБ"
        log_message "OK" "Все базы в пределах нормы"
    fi
}

monitor_databases
EOF

# Права и запуск
chmod +x "$SCRIPT_PATH"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Установка cron
crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
( crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH" ) | crontab -

echo "✅ Скрипт установлен: $SCRIPT_PATH"
echo "📩 Email уведомлений: $EMAIL"
echo "🕗 Cron-задача: ежедневно в 08:00"
echo "▶️ Запуск первой проверки прямо сейчас..."

"$SCRIPT_PATH"
