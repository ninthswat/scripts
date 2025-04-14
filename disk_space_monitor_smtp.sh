#!/bin/bash

# Конфигурация SMTP
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="diskwatch@hostfly.by"  # Обновлённый адрес отправителя

# Проверка аргументов
if [ "$#" -ne 1 ]; then
    echo "Использование: $0 <email_получателя>"
    echo "Пример: $0 admin@example.com"
    exit 1
fi

EMAIL="$1"
SCRIPT_PATH="/usr/local/bin/disk_space_monitor.sh"
CRON_JOB="0 8,20 * * * $SCRIPT_PATH $EMAIL"
HOSTNAME=$(hostname)
LANG=ru_RU.UTF-8
LC_ALL=ru_RU.UTF-8

# Проверка зависимостей
check_dependencies() {
    if ! command -v sendEmail &>/dev/null; then
        echo "Устанавливаю sendEmail для SMTP..."
        if command -v apt &>/dev/null; then
            sudo apt install -y sendemail libio-socket-ssl-perl libnet-ssleay-perl
        elif command -v yum &>/dev/null; then
            sudo yum install -y sendEmail perl-IO-Socket-SSL perl-Net-SSLeay
        else
            echo "Ошибка: не найден apt или yum для установки sendEmail" >&2
            exit 1
        fi
    fi
}

send_email() {
    local priority=$1
    local subject=$2
    local message=$3
    
    local full_message=$(echo -e "Хост: $HOSTNAME\nДата: $(date)\nПриоритет: $priority\n\n$message\n\nДополнительная информация:\n$(df -h)\n\nТоп 10 самых больших каталогов:\n$(du -Sh / 2>/dev/null | sort -rh | head -n 10)")
    
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

check_disk_space() {
    df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev' | awk '{print $5 " " $6}' | while read -r output; do
        used_percent=$(echo "$output" | awk '{print $1}' | cut -d'%' -f1)
        partition=$(echo "$output" | awk '{print $2}')
        
        if [ "$used_percent" -ge 95 ]; then
            send_email "Критический" \
                      "CRITICAL: Заполнение диска ($used_percent%) на $partition" \
                      "Раздел $partition заполнен на $used_percent%.\nТребуется немедленное вмешательство!"
        elif [ "$used_percent" -ge 90 ]; then
            send_email "Высокий" \
                      "WARNING: Заполнение диска ($used_percent%) на $partition" \
                      "Раздел $partition заполнен на $used_percent%.\nРекомендуется очистить место в ближайшее время."
        fi
    done
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
    echo "Установка монитора дискового пространства"
    echo "Получатель уведомлений: $EMAIL"
    
    check_dependencies
    
    echo "Копируем скрипт в $SCRIPT_PATH"
    cp -f "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    install_cron_job
    
    echo "Установка завершена. Для теста запустите: $SCRIPT_PATH $EMAIL"
fi

[ "$0" = "$BASH_SOURCE" ] && [ "$1" != "--install" ] && check_disk_space
