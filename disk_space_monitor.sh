#!/bin/bash

# Конфигурация SMTP
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="HostFly. Мониторинг <support@hostfly.by>"

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

# Проверка и настройка CentOS 7 репозиториев
check_centos7_repos() {
    if [ -f /etc/centos-release ]; then
        CENTOS_VERSION=$(grep -oP '(?<=release )\d' /etc/centos-release)
        if [ "$CENTOS_VERSION" -eq 7 ]; then
            echo "Обнаружен CentOS 7, настраиваю репозитории на vault.centos.org..."
            sudo sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
            sudo sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
            echo "Очищаю кеш yum..."
            sudo yum clean all
        fi
    fi
}

# Проверка зависимостей
check_dependencies() {
    if ! command -v sendEmail &>/dev/null; then
        echo "Устанавливаю sendEmail для SMTP..."
        if command -v apt &>/dev/null; then
            sudo apt install -y sendemail
        elif command -v yum &>/dev/null; then
            check_centos7_repos  # Добавляем проверку перед установкой через yum
            sudo yum install -y sendEmail
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
    
    local russian_date=$(date "+%d.%m.%Y %H:%M:%S")
    local full_message=$(echo -e "Хост: $HOSTNAME\nДата: $russian_date\nПриоритет: $priority\n\n$message\n\nДополнительная информация:\n$(df -h /)\n\nТоп 10 самых больших каталогов в корне:\n$(du -Sh / 2>/dev/null | sort -rh | head -n 10)")
    
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
    # Получаем информацию только о корневом разделе
    output=$(df -h / | awk 'NR==2 {print $5 " " $6}')
    used_percent=$(echo "$output" | awk '{print $1}' | cut -d'%' -f1)
    partition=$(echo "$output" | awk '{print $2}')
    
    if [ "$used_percent" -ge 95 ]; then
        send_email "Критический" \
                  "КРИТИЧЕСКОЕ ПРЕДУПРЕЖДЕНИЕ: Заполнение корневого раздела $(hostname) ($used_percent%)" \
                  "Корневой раздел $partition заполнен на $used_percent%.\nТребуется немедленное вмешательство!"
    elif [ "$used_percent" -ge 90 ]; then
        send_email "Высокий" \
                  "ПРЕДУПРЕЖДЕНИЕ: Заполнение корневого раздела $(hostname) ($used_percent%)" \
                  "Корневой раздел $partition заполнен на $used_percent%.\nРекомендуется очистить место в ближайшее время."
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
