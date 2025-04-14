#!/bin/bash
clear
echo "=== Установка монитора MySQL ==="

# Проверка root-прав
if [ "$(id -u)" -ne 0 ]; then
  echo "Требуются права root! Используйте sudo." >&2
  exit 1
fi

# Запрос email с валидацией
while true; do
  read -p "Введите email для уведомлений: " EMAIL
  if [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    break
  else
    echo "Ошибка: введите корректный email (например, user@example.com)"
  fi
done

# Установка зависимостей
echo -n "Устанавливаю зависимости..."
if command -v apt &>/dev/null; then
  apt-get update >/dev/null && \
  apt-get install -y sendemail libio-socket-ssl-perl libnet-ssleay-perl >/dev/null
elif command -v yum &>/dev/null; then
  yum install -y sendEmail perl-IO-Socket-SSL perl-Net-SSLeay >/dev/null
else
  echo " [ОШИБКА] Не найден apt или yum" >&2
  exit 1
fi
echo " [OK]"

# Скачивание и настройка скрипта
echo -n "Настраиваю мониторинг..."
SCRIPT_URL="https://raw.githubusercontent.com/ninthswat/scripts/main/check_mysql.sh"
TMP_SCRIPT="/tmp/check_mysql_$$.sh"

curl -sL "$SCRIPT_URL" -o "$TMP_SCRIPT" || {
  echo " [ОШИБКА] Не удалось скачать скрипт" >&2
  exit 1
}

# Подстановка email и перемещение
sed -i "s/^RECIPIENT_EMAIL=.*/RECIPIENT_EMAIL=\"$EMAIL\"/" "$TMP_SCRIPT"
install -m 755 "$TMP_SCRIPT" /usr/local/bin/check_mysql.sh
rm -f "$TMP_SCRIPT"

# Настройка cron
(crontab -l 2>/dev/null | grep -v "check_mysql.sh"; echo "* * * * * /usr/local/bin/check_mysql.sh") | crontab -

# Создание лог-файла
touch /var/log/mysql_monitor.log
chmod 644 /var/log/mysql_monitor.log

echo " [OK]"
echo "Установка завершена!"
echo "Лог-файл: /var/log/mysql_monitor.log"
echo "Проверка: tail -f /var/log/mysql_monitor.log"
