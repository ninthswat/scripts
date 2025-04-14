#!/bin/bash

# Конфигурация
RECIPIENT_EMAIL="your_email@example.com"
SENDER_EMAIL="support@hostfly.by"
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASSWORD="s6tGiMzCee745dKO67zgAMT9"

# Функция отправки email через swaks
send_alert() {
    local subject=$1
    local body=$2
    
    echo "$body" | swaks \
        --to "$RECIPIENT_EMAIL" \
        --from "$SENDER_EMAIL" \
        --server "$SMTP_SERVER" \
        --port "$SMTP_PORT" \
        --auth LOGIN \
        --auth-user "$SMTP_USER" \
        --auth-password "$SMTP_PASSWORD" \
        --tls \
        --h-Subject "$subject" \
        --body -
}

# Проверка MySQL
if ! mysqladmin ping -h localhost -u root --silent; then
    error_msg="$(date) - MySQL сервер недоступен. Попытка перезапуска..."
    echo "$error_msg" >> /var/log/mysql_monitor.log
    
    send_alert "MySQL Server Down Alert" "$error_msg"
    
    systemctl restart mysql
    sleep 5
    
    if mysqladmin ping -h localhost -u root --silent; then
        success_msg="$(date) - MySQL сервер успешно перезапущен."
        echo "$success_msg" >> /var/log/mysql_monitor.log
        send_alert "MySQL Server Restored" "$success_msg"
    else
        fail_msg="$(date) - Не удалось перезапустить MySQL сервер!"
        echo "$fail_msg" >> /var/log/mysql_monitor.log
        send_alert "MySQL Server Restart Failed" "$fail_msg"
    fi
fi
