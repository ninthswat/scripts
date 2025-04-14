#!/bin/bash

# Проверка root-прав
if [ "$(id -u)" -ne 0 ]; then
    echo "Требуются права root. Запустите с sudo!" >&2
    exit 1
fi

# Проверка терминала (интерактивный режим)
if [[ "$1" == "--interactive" ]]; then
    if [ -t 0 ]; then
        # Режим реального терминала
        while true; do
            read -p "Введите email для уведомлений (можно несколько через запятую): " emails
            if [[ "$emails" =~ @ ]]; then
                break
            else
                echo "Ошибка: email должен содержать @" >&2
            fi
        done
    else
        # Режим pipe - перенаправляем ввод с /dev/tty
        exec < /dev/tty
        while true; do
            read -p "Введите email для уведомлений (можно несколько через запятую): " emails
            if [[ "$emails" =~ @ ]]; then
                break
            else
                echo "Ошибка: email должен содержать @" >&2
            fi
        done
    fi
elif [ $# -ge 1 ]; then
    emails="$1"
    if ! [[ "$emails" =~ @ ]]; then
        echo "Ошибка: email должен содержать @" >&2
        exit 1
    fi
else
    echo "Использование:"
    echo "  Автоматический режим: curl ... | sudo bash -s -- \"ваш@email.com\""
    echo "  Интерактивный режим: curl ... | sudo bash -s -- --interactive"
    echo ""
    echo "Для интерактивного режима лучше использовать:"
    echo "  sudo bash <(curl -sSL https://.../install_disk_monitor.sh) --interactive"
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
