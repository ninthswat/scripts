#!/bin/bash
echo "=== Установка монитора MySQL ==="

# Запрос email
read -p "Введите email для уведомлений: " EMAIL
[ -z "$EMAIL" ] && { echo "Ошибка: email не может быть пустым"; exit 1; }

# Скачивание основного скрипта
echo "Скачиваю check_mysql.sh..."
curl -sL https://raw.githubusercontent.com/ninthswat/scripts/main/check_mysql.sh -o /tmp/check_mysql.sh || { echo "Ошибка загрузки"; exit 1; }

# Настройка email
sed -i "s/RECIPIENT_EMAIL=.*/RECIPIENT_EMAIL=\"$EMAIL\"/" /tmp/check_mysql.sh

# Установка
echo "Устанавливаю в /usr/local/bin..."
sudo mv /tmp/check_mysql.sh /usr/local/bin/check_mysql.sh
sudo chmod +x /usr/local/bin/check_mysql.sh

# Настройка cron
echo "Настраиваю cron..."
(sudo crontab -l 2>/dev/null | grep -v "check_mysql.sh"; echo "* * * * * /usr/local/bin/check_mysql.sh") | sudo crontab -

# Создание лог-файла
sudo touch /var/log/mysql_monitor.log
sudo chmod 644 /var/log/mysql_monitor.log

echo "Готово! Мониторинг MySQL активирован для $EMAIL"
