#!/bin/bash

# Проверка root-прав
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен запускаться с правами root!" >&2
  exit 1
fi

# Конфигурация SMTP (такая же как в disk_space_monitor.sh)
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="support@hostfly.by"

# Запрос email для уведомлений
read -p "Введите email для получения уведомлений: " RECIPIENT_EMAIL

# Конфигурационные параметры
SCRIPT_PATH="/usr/local/bin/check_mysql.sh"
LOG_FILE="/var/log/mysql_monitor.log"
CRON_JOB="* * * * * $SCRIPT_PATH"
HOSTNAME=$(hostname)

# Проверка и установка зависимостей
check_dependencies() {
    if ! command -v sendEmail &>/dev/null; then
        echo "Устанавливаю sendEmail для SMTP..."
        if command -v apt &>/dev/null; then
            apt-get install -y sendemail libio-socket-ssl-perl libnet-ssleay-perl
        elif command -v yum &>/dev/null; then
            yum install -y sendEmail perl-IO-Socket-SSL perl-Net-SSLeay
        else
            echo "Ошибка: не найден apt или yum для установки sendEmail" >&2
            exit 1
        fi
    fi
}

# Функция отправки email через sendEmail
send_alert() {
    local subject=$1
    local body=$2
    
    local full_message=$(echo -e "Хост: $HOSTNAME\nДата: $(date)\n\n$body\n\nСтатус MySQL:\n$(systemctl status mysql --no-pager)")
    
    if sendEmail -f "$SMTP_FROM" \
                -t "$RECIPIENT_EMAIL" \
                -u "$subject" \
                -m "$full_message" \
                -s "$SMTP_SERVER:$SMTP_PORT" \
                -xu "$SMTP_USER" \
                -xp "$SMTP_PASS" \
                -o tls=no \
                -o message-content-type=text/plain \
                -o message-charset=UTF-8; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Уведомление отправлено на $RECIPIENT_EMAIL" >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка отправки письма!" >> "$LOG_FILE"
    fi
}

# Основная логика мониторинга
check_mysql() {
    if ! mysqladmin ping -h localhost -u root --silent; then
        error_msg="MySQL сервер недоступен. Пытаюсь перезапустить..."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $error_msg" >> "$LOG_FILE"
        send_alert "MySQL Server Down Alert" "$error_msg"
        
        systemctl restart mysql
        sleep 5
        
        if mysqladmin ping -h localhost -u root --silent; then
            success_msg="MySQL успешно перезапущен"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $success_msg" >> "$LOG_FILE"
            send_alert "MySQL Server Restored" "$success_msg"
        else
            fail_msg="Не удалось перезапустить MySQL!"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $fail_msg" >> "$LOG_FILE"
            send_alert "MySQL Server Restart Failed" "$fail_msg"
        fi
    fi
}

# Установка
install() {
    check_dependencies
    
    echo "Копируем скрипт в $SCRIPT_PATH"
    cp -f "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    (crontab -l 2>/dev/null | grep -v -F "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -
    
    echo "Установка завершена!"
    echo "Скрипт мониторинга: $SCRIPT_PATH"
    echo "Лог-файл: $LOG_FILE"
    echo "Cron job: $CRON_JOB"
    echo "Уведомления будут отправляться на: $RECIPIENT_EMAIL"
}

# Если скрипт запущен напрямую (не через source)
if [ "$0" = "$BASH_SOURCE" ]; then
    if [ "$1" = "--install" ]; then
        install
    else
        check_mysql
    fi
fi
