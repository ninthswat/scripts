#!/bin/bash

# Конфигурация
EMAIL="ninthswat@gmail.com"
SMTP_FROM="HostFly Мониторинг <support@hostfly.by>"
THRESHOLD_GB=10
MYSQL_DIR="/var/lib/mysql"
EXCLUDE_LIST="mysql performance_schema information_schema sys"
LOG_FILE="/var/log/mysql_db_monitor.log"

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

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

monitor_databases() {
    local hostname=$(hostname)
    local now=$(date "+%d.%m.%Y %H:%M:%S")
    local output=""

    for dir in "$MYSQL_DIR"/*; do
        bn=$(basename "$dir")
        if echo "$EXCLUDE_LIST" | grep -qw "$bn"; then
            continue
        fi

        [ -d "$dir" ] || continue

        size_gb=$(du -sBG "$dir" 2>/dev/null | awk '{print $1}' | sed 's/G//')
        if [[ "$size_gb" =~ ^[0-9]+$ ]] && [ "$size_gb" -gt "$THRESHOLD_GB" ]; then
            output+="${size_gb} GB\t$dir\n"
        fi
    done

    if [[ -n "$output" ]]; then
        local message="На сервере $hostname были обнаружены базы данных, превышающие $THRESHOLD_GB ГБ:\n\n"
        message+="$output\n\n"
        message+="Согласно п. 7.1.1 правил пользования, размер одной базы не должен превышать 5 ГБ.\n"
        message+="Команде hostfly необходимо установить владельцев данных баз и уведомить их о нарушении."

        echo -e "[ALERT] Обнаружены превышения баз данных:\n$output"
        log_message "ALERT" "Найдены базы > ${THRESHOLD_GB} ГБ. Отправка письма."
        send_email "$EMAIL" "🚨 Большие базы данных на $hostname" "$message"
    else
        echo "[OK] Все базы данных меньше ${THRESHOLD_GB} ГБ"
        log_message "OK" "Все базы данных меньше ${THRESHOLD_GB} ГБ"
    fi
}

monitor_databases
