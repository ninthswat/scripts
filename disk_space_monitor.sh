#!/bin/bash

# Конфигурация
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="support@hostfly.by"
SMTP_TEST_EMAIL="support@hostfly.by"
LOG_FILE="/var/log/disk_monitor.log"
HOSTNAME=$(hostname)

# Проверка SMTP
check_smtp() {
    echo "[$(date '+%d.%m.%Y %H:%M:%S')] Проверка SMTP..." >> "$LOG_FILE"
    if sendEmail -f "$SMTP_FROM" \
                -t "$SMTP_TEST_EMAIL" \
                -u "Тест SMTP с сервера $HOSTNAME" \
                -m "Проверка подключения к почтовому серверу" \
                -s "$SMTP_SERVER:$SMTP_PORT" \
                -xu "$SMTP_USER" \
                -xp "$SMTP_PASS" \
                -o tls=no \
                -o timeout=10 \
                -o message-charset=UTF-8 \
                >> "$LOG_FILE" 2>&1; then
        echo "[$(date '+%d.%m.%Y %H:%M:%S')] SMTP проверка: УСПЕШНО" >> "$LOG_FILE"
        return 0
    else
        echo "[$(date '+%d.%m.%Y %H:%M:%S')] SMTP проверка: ОШИБКА" >> "$LOG_FILE"
        return 1
    fi
}

# Отправка уведомления
send_alert() {
    local priority=$1
    local subject=$2
    local message=$3

    local full_message=$(echo -e "
📢 Сервер: $HOSTNAME
📅 Дата: $(date '+%d.%m.%Y %H:%M:%S')
🚨 Приоритет: $priority

$message

💾 Состояние дисков:
$(df -h /)

📂 10 самых больших каталогов:
$(du -Sh / 2>/dev/null | sort -rh | head -n 10)
")

    echo "[$(date '+%d.%m.%Y %H:%M:%S')] Отправка письма: $subject" >> "$LOG_FILE"
    sendEmail -f "$SMTP_FROM" \
              -t "$EMAIL" \
              -u "🖥️ $HOSTNAME: $subject" \
              -m "$full_message" \
              -s "$SMTP_SERVER:$SMTP_PORT" \
              -xu "$SMTP_USER" \
              -xp "$SMTP_PASS" \
              -o tls=no \
              -o timeout=10 \
              -o message-charset=UTF-8 \
              >> "$LOG_FILE" 2>&1
}

# Проверка диска
check_space() {
    output=$(df -h / | awk 'NR==2 {print $5 " " $6}')
    used_percent=$(echo "$output" | awk '{print $1}' | cut -d'%' -f1)
    partition=$(echo "$output" | awk '{print $2}')
    
    if [ "$used_percent" -ge 95 ]; then
        send_alert "‼️ КРИТИЧЕСКИЙ УРОВЕНЬ" \
                  "Заполнение диска $used_percent%" \
                  "Раздел $partition заполнен на $used_percent%"
    elif [ "$used_percent" -ge 90 ]; then
        send_alert "⚠️ ВЫСОКИЙ УРОВЕНЬ" \
                  "Заполнение диска $used_percent%" \
                  "Раздел $partition заполнен на $used_percent%"
    fi
}

# Основной поток
if [ "$#" -ne 1 ]; then
    echo "Использование: $0 <email_получателя>" | tee -a "$LOG_FILE"
    exit 1
fi

EMAIL="$1"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

if ! check_smtp; then
    echo "[$(date '+%d.%m.%Y %H:%M:%S')] Остановка: проблемы с SMTP" >> "$LOG_FILE"
    exit 1
fi

check_space
