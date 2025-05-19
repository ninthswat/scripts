#!/bin/bash

# --- Конфигурация ---
SMTP_FROM="HostFly Мониторинг <support@hostfly.by>"
SCRIPT_PATH="/usr/local/bin/mysql_db_monitor.sh"
THRESHOLD_GB=10
MYSQL_DIR="/var/lib/mysql"
CRON_TIME="0 8 * * *"
EXCLUDE_LIST="mysql performance_schema information_schema sys"

# --- Функция отправки письма ---
send_email() {
    local recipient="$1"
    local subject="$2"
    local body="$3"

    {
        echo "To: $recipient"
        echo "From: $SMTP_FROM"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo -e "$body"
    } | /usr/sbin/sendmail -t
}

# --- Логика мониторинга баз данных ---
monitor_databases() {
    local recipient="$1"
    local hostname=$(hostname)
    local now=$(date "+%d.%m.%Y %H:%M:%S")

    local exclude_pattern=$(echo "$EXCLUDE_LIST" | tr ' ' '\n' | sed 's|^|'"$MYSQL_DIR"'/|' | tr '\n' '|' | sed 's/|$//')

    local output=$(du -sBG "$MYSQL_DIR"/* 2>/dev/null | grep -Ev "$exclude_pattern" | awk -v threshold="$THRESHOLD_GB" '
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

        send_email "$recipient" "🚨 Большие базы данных на $hostname" "$message"
    fi
}

# --- Установка скрипта ---
install_script() {
    read -p "Введите email для уведомлений: " EMAIL
    if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-z]{2,}$ ]]; then
        echo "Некорректный email." >&2
        exit 1
    fi

    cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash
EMAIL="$EMAIL"
SMTP_FROM="$SMTP_FROM"
THRESHOLD_GB=$THRESHOLD_GB
MYSQL_DIR="$MYSQL_DIR"
EXCLUDE_LIST="$EXCLUDE_LIST"

send_email() {
    local recipient="\$1"
    local subject="\$2"
    local body="\$3"

    {
        echo "To: \$recipient"
        echo "From: \$SMTP_FROM"
        echo "Subject: \$subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo -e "\$body"
    } | /usr/sbin/sendmail -t
}

monitor_databases() {
    local hostname=\$(hostname)
    local now=\$(date "+%d.%m.%Y %H:%M:%S")
    local exclude_pattern=\$(echo "\$EXCLUDE_LIST" | tr ' ' '\n' | sed 's|^|\$MYSQL_DIR/|' | tr '\n' '|' | sed 's/|$//')

    local output=\$(du -sBG "\$MYSQL_DIR"/* 2>/dev/null | grep -Ev "\$exclude_pattern" | awk -v threshold="\$THRESHOLD_GB" '
        \$1 ~ /[0-9]+G/ {
            size = substr(\$1, 1, length(\$1)-1)
            if (size + 0 > threshold) {
                print size " GB\t" \$2
            }
        }')

    if [[ -n "\$output" ]]; then
        local message="На сервере \$hostname были обнаружены базы данных, превышающие \$THRESHOLD_GB ГБ:\n\n"
        message+="\$output\n\n"
        message+="Согласно п. 7.1.1 правил пользования, размер одной базы не должен превышать 5 ГБ.\n"
        message+="Команде hostfly необходимо установить владельцев данных баз и уведомить их о нарушении."

        send_email "\$EMAIL" "🚨 Большие базы данных на \$hostname" "\$message"
    fi
}

monitor_databases
EOF

    chmod +x "$SCRIPT_PATH"
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_TIME $SCRIPT_PATH") | crontab -
    echo "✅ Скрипт установлен как $SCRIPT_PATH"
    echo "🕗 Cron: ежедневно в 08:00"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    install_script
fi
