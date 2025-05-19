#!/bin/bash

# --- SMTP-конфигурация ---
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="HostFly. Мониторинг <support@hostfly.by>"

SCRIPT_PATH="/usr/local/bin/mysql_db_monitor.sh"
THRESHOLD_GB=10
MYSQL_DIR="/var/lib/mysql"
CRON_TIME="0 8 * * *"

# --- Функция отправки письма ---
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

# --- Логика мониторинга баз данных ---
monitor_databases() {
    local recipient="$1"
    local hostname=$(hostname)
    local now=$(date "+%d.%m.%Y %H:%M:%S")

    local output=$(du -sBG "$MYSQL_DIR"/* 2>/dev/null | awk -v threshold="$THRESHOLD_GB" '
        $1 ~ /[0-9]+G/ {
            size = substr($1, 1, length($1)-1)
            if (size + 0 > threshold) {
                print size " GB\t" $2
            }
        }')

    if [[ -n "$output" ]]; then
        local message="На сервере $hostname были обнаружены базы данных, превышающие $THRESHOLD_GB ГБ:\n\n"
        message+="$output\n\n"
        message+="Согласно п. 7.1.1 правил пользования, размер одной базы не должен превышать 5 ГБ.\n"
        message+="Команде hostfly необходимо установить владельцев данных баз и уведомить их о нарушении."

        send_email "$recipient" \
                   "🚨 Большие базы данных на $hostname" \
                   "$message"
    fi
}

# --- Установка скрипта ---
install_script() {
    read -p "Введите email для уведомлений: " EMAIL
    if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-z]{2,}$ ]]; then
        echo "Некорректный email." >&2
        exit 1
    fi

    # Создание исполняемого скрипта мониторинга
    cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash
EMAIL="$EMAIL"
SMTP_SERVER="$SMTP_SERVER"
SMTP_PORT="$SMTP_PORT"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
SMTP_FROM="$SMTP_FROM"

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

monitor_databases() {
    local hostname=\$(hostname)
    local now=\$(date "+%d.%m.%Y %H:%M:%S")

    local output=\$(du -sBG /var/lib/mysql/* 2>/dev/null | awk -v threshold=$THRESHOLD_GB '
        \$1 ~ /[0-9]+G/ {
            size = substr(\$1, 1, length(\$1)-1)
            if (size + 0 > threshold) {
                print size " GB\t" \$2
            }
        }')

    if [[ -n "\$output" ]]; then
        local message="На сервере \$hostname были обнаружены базы данных, превышающие $THRESHOLD_GB ГБ:\n\n"
        message+="\$output\n\n"
        message+="Согласно п. 7.1.1 правил пользования, размер одной базы не должен превышать 5 ГБ.\n"
        message+="Команде hostfly необходимо установить владельцев данных баз и уведомить их о нарушении."

        send_email "\$EMAIL" \
                   "🚨 Большие базы данных на \$hostname" \
                   "\$message"
    fi
}

monitor_databases
EOF

    chmod +x "$SCRIPT_PATH"

    # Добавление в cron
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_TIME $SCRIPT_PATH") | crontab -

    echo "✅ Скрипт установлен в $SCRIPT_PATH"
    echo "🕗 Проверка будет выполняться ежедневно в 08:00"
}

# --- Запуск установки, если скрипт вызван напрямую ---
if [ "$0" = "$BASH_SOURCE" ]; then
    install_script
fi
