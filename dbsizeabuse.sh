#!/bin/bash

# Конфигурация SMTP
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="HostFly. Мониторинг <support@hostfly.by>"

# Порог для оповещения (в ГБ)
THRESHOLD_GB=10

# Проверка аргументов
if [ "$#" -ne 1 ]; then
    echo "Использование: $0 <email_получателя>"
    echo "Пример: $0 admin@example.com"
    exit 1
fi

EMAIL="$1"
SCRIPT_PATH="/usr/local/bin/mysql_db_monitor.sh"
CRON_JOB="0 8,20 * * * $SCRIPT_PATH $EMAIL"
HOSTNAME=$(hostname)
LANG=ru_RU.UTF-8
LC_ALL=ru_RU.UTF-8

send_email() {
    local priority=$1
    local subject=$2
    local message=$3
    
    local russian_date=$(date "+%d.%m.%Y %H:%M:%S")
    local policy_notice="\n\nТребуется:\n1. Установить владельцев данных баз данных\n2. Оповестить их о нарушении правил пользования (п. 7.1.1 - одна база не более 5 ГБ)\n3. Принять меры для уменьшения размера баз данных"
    local full_message=$(echo -e "Хост: $HOSTNAME\nДата: $russian_date\nПриоритет: $priority\n\n$message$policy_notice")
    
    if sendEmail -f "$SMTP_FROM" \
                -t "$EMAIL" \
                -u "$subject" \
                -m "$full_message" \
                -s "$SMTP_SERVER:$SMTP_PORT" \
                -xu "$SMTP_USER" \
                -xp "$SMTP_PASS" \
                -o tls=no \
                -o message-content-type=text/plain \
                -o message-charset=UTF-8; then
        echo "Уведомление отправлено на $EMAIL"
    else
        echo "Ошибка отправки письма!" >&2
        exit 1
    fi
}

check_db_sizes() {
    # Получаем список баз данных, превышающих порог
    local large_dbs=$(mysql -N -e "SELECT 
        table_schema AS 'Database', 
        ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS 'Size_GB'
        FROM information_schema.TABLES 
        GROUP BY table_schema 
        HAVING SUM(data_length + index_length) > ${THRESHOLD_GB} * 1024 * 1024 * 1024 
        ORDER BY Size_GB DESC" 2>/dev/null)

    if [ -n "$large_dbs" ]; then
        local db_list=$(echo "$large_dbs" | awk '{print $1 " (" $2 " ГБ)"}' | tr '\n' ', ' | sed 's/, $//')
        local count=$(echo "$large_dbs" | wc -l)
        local total_size=$(echo "$large_dbs" | awk '{sum += $2} END {print sum}')
        
        send_email "Высокий" \
                  "ПРЕДУПРЕЖДЕНИЕ: На сервере $(hostname) обнаружены большие БД (>${THRESHOLD_GB} ГБ)" \
                  "Обнаружено $count баз данных, превышающих порог ${THRESHOLD_GB} ГБ.\nОбщий размер: ${total_size} ГБ\n\nСписок баз данных:\n$large_dbs"
    else
        echo "Базы данных не превышают порог ${THRESHOLD_GB} ГБ."
    fi
}

install_cron_job() {
    crontab -l | grep -v "$(basename "$SCRIPT_PATH")" | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    
    if crontab -l | grep -q "$(basename "$SCRIPT_PATH")"; then
        echo "Задание cron успешно установлено:"
        echo "Проверка будет выполняться в 08:00 и 20:00"
    else
        echo "Ошибка при добавлении задания в cron!" >&2
        exit 1
    fi
}

# Установочная часть
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "Установка монитора размера баз данных MySQL"
    echo "Получатель уведомлений: $EMAIL"
    echo "Порог оповещения: ${THRESHOLD_GB} ГБ"
    
    echo "Копируем скрипт в $SCRIPT_PATH"
    cp -f "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    install_cron_job
    
    echo "Установка завершена. Для теста запустите: $SCRIPT_PATH $EMAIL"
fi

[ "$0" = "$BASH_SOURCE" ] && [ "$1" != "--install" ] && check_db_sizes
