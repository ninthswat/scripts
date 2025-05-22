#!/bin/bash

SCRIPT_PATH="/usr/local/bin/mysql_db_monitor.sh"
LOG_FILE="/var/log/mysql_db_monitor.log"
CRON_TIME="0 16 * * 3"  # Среда 16:00

# Проверка и установка sendEmail
if ! command -v sendemail &>/dev/null && ! command -v sendEmail &>/dev/null; then
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
LOG_FILE="/var/log/mysql_db_monitor.log"

MYSQL_USER="root"
MYSQL_PASS=""
MYSQL_SOCKET="/var/lib/mysql/mysql.sock"  # Измените путь при необходимости

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
    local output=""

    local query="SELECT table_schema AS db_name, ROUND(SUM(data_length + index_length)/1024/1024/1024, 2) AS size_gb
                 FROM information_schema.tables
                 GROUP BY table_schema
                 HAVING size_gb > \$THRESHOLD_GB
                 ORDER BY size_gb DESC;"

    result=\$(mysql -u "\$MYSQL_USER" \${MYSQL_PASS:+-p\"\$MYSQL_PASS\"} --socket="\$MYSQL_SOCKET" -N -e "\$query")

    while IFS=\$'\\t' read -r db size; do
        output="\${output}\\n\${size} GB\t\${db}"
    done <<< "\$result"

    if [[ -n "\$output" ]]; then
        local message="На сервере \$hostname были обнаружены базы данных, превышающие \$THRESHOLD_GB ГБ:\n\${output}\n\nПросьба установить владельцев данных баз и уведомить их при необходимости."

        message=\$(echo -e "\$message")
        echo -e "[ALERT] Обнаружены превышения баз данных:\$output"
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

# Добавление в cron
crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
( crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH" ) | crontab -

# Запуск
echo "✅ Скрипт установлен: $SCRIPT_PATH"
echo "📩 Email уведомлений: $EMAIL"
echo "🕓 Cron-задача: каждую среду в 16:00"
echo "▶️ Запуск первой проверки прямо сейчас..."
"$SCRIPT_PATH"
