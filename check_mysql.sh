#!/bin/bash

# Конфигурация SMTP
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="support@hostfly.by"
RECIPIENT_EMAIL="ninthswat@gmail.com"  # Автоматически заменяется при установке
LOG_FILE="/var/log/mysql_monitor.log"
HOSTNAME=$(hostname)

# Функция отправки email (русские темы)
send_alert() {
    local subject=$1
    local body=$2
    
    local full_message="Сервер: $HOSTNAME\nДата: $(date '+%Y-%m-%d %H:%M:%S')\n\n$body\n\nСтатус MySQL:\n$(systemctl status mysql --no-pager 2>&1)"
    
    sendEmail -f "$SMTP_FROM" \
              -t "$RECIPIENT_EMAIL" \
              -u "$subject" \
              -m "$full_message" \
              -s "$SMTP_SERVER:$SMTP_PORT" \
              -xu "$SMTP_USER" \
              -xp "$SMTP_PASS" \
              -o tls=no \
              -o message-charset=UTF-8 >/dev/null 2>&1 || \
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка отправки письма" >> "$LOG_FILE"
}

# Основная логика с русскими уведомлениями
if ! mysqladmin ping -h localhost -u root --silent; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - MySQL сервер недоступен" >> "$LOG_FILE"
    send_alert "ВНИМАНИЕ: MySQL не отвечает" "Сервер MySQL перестал отвечать на запросы. Пытаюсь перезапустить..."
    
    systemctl restart mysql
    sleep 5
    
    if mysqladmin ping -h localhost -u root --silent; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - MySQL успешно перезапущен" >> "$LOG_FILE"
        send_alert "ВОССТАНОВЛЕНО: MySQL работает" "Сервер MySQL был успешно перезапущен"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка перезапуска MySQL!" >> "$LOG_FILE"
        send_alert "КРИТИЧЕСКО: Ошибка перезапуска MySQL" "Не удалось перезапустить сервер MySQL! Требуется ручное вмешательство."
    fi
fi
