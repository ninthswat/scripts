#!/bin/bash
echo "Установка монитора MySQL..."
URL="https://raw.githubusercontent.com/ninthswat/scripts/main/check_mysql.sh"

# Запрашиваем email
read -p "Введите email для уведомлений: " EMAIL

# Скачиваем и устанавливаем
wget -qO /usr/local/bin/check_mysql.sh "$URL" && \
chmod +x /usr/local/bin/check_mysql.sh && \
sed -i "s/YOUR_EMAIL_PLACEHOLDER/$EMAIL/" /usr/local/bin/check_mysql.sh && \
touch /var/log/mysql_monitor.log && \
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/check_mysql.sh") | crontab - && \
echo "Установлено! Мониторинг MySQL активен." || \
echo "Ошибка установки!"
