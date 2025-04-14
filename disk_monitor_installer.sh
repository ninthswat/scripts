#!/bin/bash

# Скрипт для мониторинга свободного места на диске с исправленной установкой в cron

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

# Функции для работы с почтой
determine_mail_method() {
    if command -v mail >/dev/null 2>&1; then
        echo "mail"
    elif command -v sendmail >/dev/null 2>&1; then
        echo "sendmail"
    else
        echo "none"
    fi
}

send_email() {
    local priority=$1
    local subject=$2
    local message=$3
    local mail_method=$(determine_mail_method)
    
    local full_message=$(echo -e "Хост: $HOSTNAME\nДата: $(date)\nПриоритет: $priority\n\n$message\n\nДополнительная информация:\n$(df -h)\n\nТоп 10 самых больших каталогов:\n$(du -Sh / 2>/dev/null | sort -rh | head -n 10)")
    
    if [ "$mail_method" == "mail" ]; then
        echo -e "$full_message" | mail -s "$(echo -e "$subject\nContent-Type: text/plain; charset=UTF-8")" "$EMAIL"
    elif [ "$mail_method" == "sendmail" ]; then
        (
            echo "From: disk_monitor@$HOSTNAME"
            echo "To: $EMAIL"
            echo "Subject: $subject"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo "X-Priority: $([ "$priority" == "Критический" ] && echo "1" || echo "3")"
            echo ""
            echo -e "$full_message"
        ) | sendmail -f "disk_monitor@$HOSTNAME" "$EMAIL"
    else
        echo "Не удалось отправить уведомление: не найден ни mail, ни sendmail" >&2
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
    # Удаляем старые записи этого скрипта из cron
    crontab -l | grep -v "$(basename "$SCRIPT_PATH")" | crontab -
    
    # Добавляем новую запись
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
    
    # Проверка почтовых утилит
    mail_method=$(determine_mail_method)
    if [ "$mail_method" == "none" ]; then
        echo "Требуется установка почтовых утилит:" >&2
        echo "Debian/Ubuntu: sudo apt install mailutils" >&2
        echo "CentOS/RHEL: sudo yum install mailx postfix" >&2
        exit 1
    fi
    
    # Установка скрипта
    echo "Копируем скрипт в $SCRIPT_PATH"
    cp -f "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    install_cron_job
    
    echo "Установка завершена. Для теста запустите: $SCRIPT_PATH $EMAIL"
fi

# Основная логика
[ "$0" = "$BASH_SOURCE" ] && [ "$1" != "--install" ] && check_disk_space
