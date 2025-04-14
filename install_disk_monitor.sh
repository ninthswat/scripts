#!/bin/bash

# Проверка root
if [ "$(id -u)" -ne 0 ]; then
  echo "Требуются права root! Используйте sudo."
  exit 1
fi

# Настройка лог-файла
LOG_FILE="/var/log/disk_monitor.log"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1  # Живой вывод + запись в лог

clear
echo "=== Установка монитора дискового пространства ==="
echo "Логирование: $LOG_FILE"
echo "-----------------------------------------------"

# Запрос email
while true; do
  read -p "Введите email для уведомлений: " EMAIL
  if [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    break
  else
    echo "Ошибка: введите корректный email (например, user@example.com)"
  fi
done

# Установка зависимостей
echo -e "\n[1/3] Установка sendEmail..."
if command -v apt &>/dev/null; then
  apt-get update
  apt-get install -y sendemail || {
    echo "ОШИБКА: не удалось установить sendEmail"
    exit 1
  }
elif command -v yum &>/dev/null; then
  yum install -y sendEmail || {
    echo "ОШИБКА: не удалось установить sendEmail"
    exit 1
  }
else
  echo "ОШИБКА: система не поддерживается (требуется apt или yum)"
  exit 1
fi
echo "✔ sendEmail установлен"

# Загрузка скрипта
echo -e "\n[2/3] Загрузка монитора..."
SCRIPT_URL="https://raw.githubusercontent.com/ninthswat/scripts/main/disk_space_monitor.sh"
SCRIPT_PATH="/usr/local/bin/disk_space_monitor.sh"

if ! curl -sL "$SCRIPT_URL" -o "$SCRIPT_PATH"; then
  echo "ОШИБКА: не удалось загрузить скрипт"
  exit 1
fi
chmod +x "$SCRIPT_PATH"
echo "✔ Скрипт загружен в $SCRIPT_PATH"

# Настройка cron
echo -e "\n[3/3] Настройка расписания..."
CRON_JOB="0 8,20 * * * $SCRIPT_PATH $EMAIL"
(crontab -l 2>/dev/null | grep -v "disk_space_monitor.sh"; echo "$CRON_JOB") | crontab -

echo -e "\n✔ Установка завершена!"
echo "-----------------------------------------------"
echo "Мониторинг будет запускаться в 08:00 и 20:00"
echo "Проверить логи: tail -f $LOG_FILE"
echo "Тест: $SCRIPT_PATH $EMAIL"
