#!/bin/bash

# Проверка root-прав
if [ "$(id -u)" -ne 0 ]; then
    echo "Требуются права root. Запустите с sudo!" >&2
    exit 1
fi

# Если запущен через pipe и нет аргументов - сообщить о правильном использовании
if [ -t 0 ] && [ $# -eq 0 ]; then
    echo "Использование (интерактивный режим):"
    echo "  curl -sSL https://.../install_disk_monitor.sh | sudo bash -s -- --interactive"
    echo ""
    echo "Использование (с указанием email):"
    echo "  curl -sSL https://.../install_disk_monitor.sh | sudo bash -s -- \"ваш@email.com\""
    exit 1
fi

# Обработка аргументов
if [[ "$1" == "--interactive" ]]; then
    # Интерактивный ввод
    while true; do
        read -p "Введите email для уведомлений (можно несколько через запятую): " emails
        if [[ "$emails" =~ @ ]]; then
            break
        else
            echo "Ошибка: email должен содержать @" >&2
        fi
    done
elif [ $# -ge 1 ]; then
    # Email передан как аргумент
    emails="$1"
    if ! [[ "$emails" =~ @ ]]; then
        echo "Ошибка: email должен содержать @" >&2
        exit 1
    fi
else
    echo "Ошибка: требуется указать email" >&2
    exit 1
fi

# Основная установка
echo "Устанавливаю монитор дискового пространства для: $emails"
wget -qO /usr/local/bin/disk_space_monitor.sh https://raw.githubusercontent.com/ninthswat/scripts/main/disk_space_monitor.sh || {
    echo "Ошибка загрузки скрипта" >&2
    exit 1
}
chmod +x /usr/local/bin/disk_space_monitor.sh

/usr/local/bin/disk_space_monitor.sh "$emails"

echo "Установка завершена! Мониторинг будет проверять диски в 08:00 и 20:00."
echo "Проверка настроек: crontab -l"
