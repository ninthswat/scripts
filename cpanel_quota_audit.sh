#!/bin/bash

SCRIPT_PATH="/usr/local/bin/cpanel_quota_audit.sh"
CRON_TIME="0 4 * * 4"
LOG_FILE="/var/log/cpanel_quota_audit.log"

# Проверка и установка sendEmail
if ! command -v sendEmail &>/dev/null; then
    echo "[INFO] Устанавливаю sendEmail..."
    if command -v apt &>/dev/null; then
        apt update && apt install -y sendemail
    elif command -v yum &>/dev/null; then
        yum install -y sendEmail
    else
        echo "[ERROR] Не найден apt или yum для установки sendEmail"
        exit 1
    fi
fi

# Ввод email
read -p "Введите email для уведомлений: " EMAIL
if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "❌ Некорректный email."
    exit 1
fi

# Создание основного скрипта
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

EMAIL="$EMAIL"
THRESHOLD_GB=100
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="Disk Monitor <noreply@hostfly.by>"

send_email() {
    local subject="\$1"
    local body="\$2"
    sendEmail -f "\$SMTP_FROM" -t "\$EMAIL" -u "\$subject" -m "\$body" \\
              -s "\$SMTP_SERVER:\$SMTP_PORT" -xu "\$SMTP_USER" -xp "\$SMTP_PASS" \\
              -o tls=no -o message-content-type=text/plain -o message-charset=UTF-8
}

log() {
    echo "[\$(date '+%F %T')] \$1" >> /var/log/cpanel_quota_audit.log
}

run_audit() {
    local hostname=\$(hostname)
    local report=""
    report+="📌 Согласно п. 7.1.1 правил пользования, безлимитное пространство предоставляется только для веб-файлов, активной электронной почты и содержимого сайтов.\n"
    report+="Оно не может использоваться для хранения, раздачи, архивирования данных или как внешнее хранилище (в т.ч. email или FTP).\n"
    report+="📣 Команде HOSTFLY необходимо определить, имеются ли факты нарушения, и при необходимости уведомить владельцев услуг.\n\n"
    report+="----------------------------------------\n"

    for user in \$(ls /var/cpanel/users); do
        homedir="/home/\$user"
        [ -d "\$homedir" ] || continue

        quota_output=\$(quota -s "\$user" 2>/dev/null)

        # Пропустить, если хотя бы один limit != 0K
        if echo "\$quota_output" | awk '\$1 ~ /^\\/dev/ && \$4 != "0K"' | grep -q .; then
            continue
        fi

        max_bytes=\$(echo "\$quota_output" | awk '
        \$1 ~ /^\\/dev/ {
            unit = substr(\$2, length(\$2), 1)
            val = substr(\$2, 1, length(\$2)-1)
            if (unit == "K") bytes = val * 1024
            else if (unit == "M") bytes = val * 1024 * 1024
            else if (unit == "G") bytes = val * 1024 * 1024 * 1024
            if (bytes > max) max = bytes
        }
        END { print max }')

        usage_gb=\$(awk "BEGIN {print \$max_bytes / 1024 / 1024 / 1024}")
        usage_gb_int=\$(awk "BEGIN {print int(\$usage_gb)}")

        [ "\$usage_gb_int" -lt "\$THRESHOLD_GB" ] && continue

        report+="Пользователь: \$user\nДомашняя директория: \$homedir\nИспользование: \${usage_gb_int} GB\n\n"
    done

    if [[ "\$report" =~ "Пользователь:" ]]; then
        log "Отправка отчёта: превышение > \$THRESHOLD_GB ГБ"
        send_email "🚨 Безлимитные аккаунты с превышением на \$hostname" "\$report"
    else
        log "Нет пользователей с превышением квоты"
    fi
}

run_audit
EOF

# Установка прав и cron
chmod +x "$SCRIPT_PATH"
touch "$LOG_FILE" && chmod 644 "$LOG_FILE"
crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
( crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH" ) | crontab -

echo "✅ Скрипт установлен: $SCRIPT_PATH"
echo "📩 Email уведомлений: $EMAIL"
echo "📆 Cron: четверг в 04:00"
echo "▶️ Запуск первой проверки..."
"$SCRIPT_PATH"
