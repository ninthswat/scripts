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
    echo "  Автоматический режим: curl -sSL https://raw.githubusercontent.com/ninthswat/scripts/main/dbsizeabuse.sh | sudo bash -s -- \"ваш@email.com\""
    echo "  Интерактивный режим: curl -sSL https://raw.githubusercontent.com/ninthswat/scripts/main/dbsizeabuse.sh | sudo bash -s -- --interactive"
    echo ""
    echo "Для интерактивного режима лучше использовать:"
    echo "  sudo bash <(curl -sSL https://raw.githubusercontent.com/ninthswat/scripts/main/dbsizeabuse.sh) --interactive"
    exit 1
fi

# Основная установка
echo "Устанавливаю монитор размера баз данных MySQL для: $emails"
wget -qO /usr/local/bin/dbsizeabuse.sh https://raw.githubusercontent.com/ninthswat/scripts/main/dbsizeabuse.sh || {
    echo "Ошибка загрузки скрипта" >&2
    exit 1
}
chmod +x /usr/local/bin/dbsizeabuse.sh

# Настройка cron
CRON_JOB="0 8,20 * * * /usr/local/bin/dbsizeabuse.sh \"$emails\""
(crontab -l 2>/dev/null | grep -v "/usr/local/bin/dbsizeabuse.sh"; echo "$CRON_JOB") | crontab -

# Первый запуск для проверки
echo "Провожу первоначальную проверку..."
/usr/local/bin/dbsizeabuse.sh "$emails"

echo ""
echo "Установка завершена! Мониторинг будет проверять размеры баз данных в 08:00 и 20:00."
echo "Проверка настроек cron: crontab -l"
echo "Ручной запуск проверки: /usr/local/bin/dbsizeabuse.sh \"$emails\""
