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

# Запрос email
read -p "Введите email для уведомлений: " EMAIL
if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "[$(date '+%d.%m.%Y %H:%M:%S')] Ошибка: некорректный email" >> "$LOG_FILE"
  echo "Ошибка: некорректный email"
  exit 1
fi

# Установка зависимостей
echo "Установка sendEmail..." | tee -a "$LOG_FILE"
if command -v apt &>/dev/null; then
  apt-get install -y sendemail >> "$LOG_FILE" 2>&1 || {
    echo "[$(date '+%d.%m.%Y %H:%M:%S')] Ошибка установки sendEmail" >> "$LOG_FILE"
    exit 1
  }
elif command -v yum &>/dev/null; then
  yum install -y sendEmail >> "$LOG_FILE" 2>&1 || {
    echo "[$(date '+%d.%m.%Y %H:%M:%S')] Ошибка установки sendEmail" >> "$LOG_FILE"
    exit 1
  }
fi

# Установка скрипта
SCRIPT_URL="https://raw.githubusercontent.com/ninthswat/scripts/main/disk_space_monitor.sh"
SCRIPT_PATH="/usr/local/bin/disk_space_monitor.sh"

echo "Загрузка скрипта..." | tee -a "$LOG_FILE"
curl -sL "$SCRIPT_URL" -o "$SCRIPT_PATH" || {
  echo "[$(date '+%d.%m.%Y %H:%M:%S')] Ошибка загрузки скрипта" >> "$LOG_FILE"
  exit 1
}
chmod +x "$SCRIPT_PATH"

# Настройка cron
CRON_JOB="0 8,20 * * * $SCRIPT_PATH $EMAIL"
(crontab -l 2>/dev/null | grep -v "disk_space_monitor.sh"; echo "$CRON_JOB") | crontab -

echo "[$(date '+%d.%m.%Y %H:%M:%S')] Установка завершена для $EMAIL" >> "$LOG_FILE"
echo "Мониторинг установлен! Проверка в 08:00 и 20:00"
echo "Логи: tail -f $LOG_FILE"
