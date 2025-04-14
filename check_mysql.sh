#!/bin/bash

# Конфигурация (аналогично disk_space_monitor.sh)
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="support@hostfly.by"
RECIPIENT_EMAIL="ninthswat@gmail.com"  # Замените на нужный email
LOG_FILE="/var/log/mysql_monitor.log"
HOSTNAME=$(hostname)

# Проверка зависимостей
if ! command -v sendEmail &>/dev/null; then
    echo "Установка sendEmail..."
    if command -v apt &>/dev/null; then
        apt install -y sendemail libio-socket-ssl-perl libnet-ssleay-perl
    elif command -v yum &>/dev/null; then
        yum install -y sendEmail perl-IO-Socket-SSL perl-Net-SSLeay
    else
        echo "Ошибка: не найден apt или yum" >&2
        exit 1
    fi
fi

# Функция отправки email (как в disk_space_monitor.sh)
send_alert() {
    local subject=$1
    local body=$2
    
    local full_message="Хост: $HOSTNAME\nДата: $(date)\n\n$body\n\nСтатус MySQL:\n$(systemctl status mysql --no-pager 2>&1)"
    
    if ! sendEmail -f "$SMTP_FROM" \
                  -t "$RECIPIENT_EMAIL" \
                  -u "$subject" \
                  -m "$full_message" \
                  -s "$SMTP_SERVER:$SMTP_PORT" \
                  -xu "$SMTP_USER" \
                  -xp "$SMTP_PASS" \
                  -o tls=no \
                  -o message-charset=UTF-8 \
                  >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка отправки письма (проверьте SMTP)" >> "$LOG_FILE"
    fi
}

# Основная логика
if ! mysqladmin ping -h localhost -u root --silent; then
    error_msg="MySQL сервер недоступен. Пытаюсь перезапустить..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $error_msg" >> "$LOG_FILE"
    send_alert "MySQL DOWN" "$error_msg"
    
    systemctl restart mysql
    sleep 5
    
    if mysqladmin ping -h localhost -u root --silent; then
        success_msg="MySQL успешно перезапущен"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $success_msg" >> "$LOG_FILE"
        send_alert "MySQL RESTORED" "$success_msg"
    else
        fail_msg="Не удалось перезапустить MySQL!"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $fail_msg" >> "$LOG_FILE"
        send_alert "MySQL RESTART FAILED" "$fail_msg"
    fi
fi
