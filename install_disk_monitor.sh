#!/bin/bash

# Проверка root-прав
if [ "$(id -u)" -ne 0 ]; then
    echo "Требуются права root. Запустите с sudo!" >&2
    exit 1
fi

# Запрос email с базовой валидацией
while true; do
    read -p "Введите email для уведомлений (можно несколько через запятую): " emails
    if [[ "$emails" =~ @ ]]; then
        break
    else
        echo "Ошибка: email должен содержать @" >&2
    fi
done

# Скачивание и установка основного скрипта
echo "Устанавливаю монитор дискового пространства..."
wget -qO /usr/local/bin/disk_space_monitor.sh https://raw.githubusercontent.com/username/repo/main/disk_space_monitor.sh
chmod +x /usr/local/bin/disk_space_monitor.sh

# Первый запуск с email
/usr/local/bin/disk_space_monitor.sh "$emails"

echo "Установка завершена! Мониторинг будет проверять диски в 08:00 и 20:00."
echo "Проверка настроек: crontab -l"
