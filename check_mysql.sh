#!/bin/bash

# Проверка root-прав
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен запускаться с правами root!" >&2
  exit 1
fi

# Установка зависимостей
echo "Устанавливаем зависимости..."
apt-get update >/dev/null 2>&1
apt-get install -y swaks curl mysql-client >/dev/null 2>&1

# Запрос email для уведомлений
read -p "Введите email для получения уведомлений: " RECIPIENT_EMAIL

# Конфигурационные параметры
SCRIPT_PATH="/usr/local/bin/check_mysql.sh"
LOG_FILE="/var/log/mysql_monitor.log"
CRON_JOB="* * * * * $SCRIPT_PATH"

# Создаем скрипт мониторинга
cat > $SCRIPT_PATH << 'EOL'
#!/bin/bash

# Конфигурация (автоматически подставляется при установке)
RECIPIENT_EMAIL="{{RECIPIENT_EMAIL}}"
SENDER_EMAIL="support@hostfly.by"
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASSWORD="s6tGiMzCee745dKO67zgAMT9"

# Функция отправки уведомлений
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
        --tls-off \
        --h-Subject "$subject" \
        --body -
}

# Основная логика мониторинга
if ! mysqladmin ping -h localhost -u root --silent; then
    error_msg="$(date '+%Y-%m-%d %H:%M:%S') - MySQL сервер недоступен. Пытаюсь перезапустить..."
    echo "$error_msg" >> {{LOG_FILE}}
    send_alert "MySQL Server Down Alert" "$error_msg"
    
    systemctl restart mysql
    sleep 5
    
    if mysqladmin ping -h localhost -u root --silent; then
        success_msg="$(date '+%Y-%m-%d %H:%M:%S') - MySQL успешно перезапущен"
        echo "$success_msg" >> {{LOG_FILE}}
        send_alert "MySQL Server Restored" "$success_msg"
    else
        fail_msg="$(date '+%Y-%m-%d %H:%M:%S') - Не удалось перезапустить MySQL!"
        echo "$fail_msg" >> {{LOG_FILE}}
        send_alert "MySQL Server Restart Failed" "$fail_msg"
    fi
fi
EOL

# Заменяем плейсхолдеры
sed -i "s|{{RECIPIENT_EMAIL}}|$RECIPIENT_EMAIL|g" $SCRIPT_PATH
sed -i "s|{{LOG_FILE}}|$LOG_FILE|g" $SCRIPT_PATH

# Настройка прав
chmod +x $SCRIPT_PATH
touch $LOG_FILE
chmod 644 $LOG_FILE

# Добавляем в cron
(crontab -l 2>/dev/null | grep -v -F "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -

echo "Установка завершена!"
echo "Скрипт мониторинга: $SCRIPT_PATH"
echo "Лог-файл: $LOG_FILE"
echo "Cron job: $CRON_JOB"
echo "Уведомления будут отправляться на: $RECIPIENT_EMAIL"
