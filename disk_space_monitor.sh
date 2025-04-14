#!/bin/bash

# Конфигурация
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="support@hostfly.by"
SMTP_TEST_EMAIL="support@hostfly.by"
LOG_FILE="/var/log/disk_monitor.log"
HOSTNAME=$(hostname)

# Инициализация лога
exec >> "$LOG_FILE" 2>&1
echo -e "\n[$(date '+%d.%m.%Y %H:%M:%S')] Запуск проверки"

# Проверка SMTP
check_smtp() {
  echo "[$(date '+%d.%m.%Y %H:%M:%S')] Проверка SMTP..."
  if sendEmail -f "$SMTP_FROM" \
              -t "$SMTP_TEST_EMAIL" \
              -u "Тест SMTP с $HOSTNAME" \
              -m "Проверка подключения" \
              -s "$SMTP_SERVER:$SMTP_PORT" \
              -xu "$SMTP_USER" \
              -xp "$SMTP_PASS" \
              -o tls=no \
              -o timeout=10 \
              -o message-charset=UTF-8; then
    echo "[$(date '+%d.%m.%Y %H:%M:%S')] ✔ SMTP доступен"
    return 0
  else
    echo "[$(date '+%d.%m.%Y %H:%M:%S')] ✖ Ошибка SMTP"
    return 1
  fi
}

# Отправка уведомления
send_alert() {
  local priority=$1
  local subject=$2
  local message=$3

  local full_message=$(echo -e "
🖥️ Сервер: $HOSTNAME
📅 Дата: $(date '+%d.%m.%Y %H:%M:%S')
🚨 Уровень: $priority

$message

💾 Состояние дисков:
$(df -h /)

📂 Топ-10 каталогов:
$(du -Sh / 2>/dev/null | sort -rh | head -n 10)
")

  echo "[$(date '+%d.%m.%Y %H:%M:%S')] Отправка: $subject"
  sendEmail -f "$SMTP_FROM" \
            -t "$EMAIL" \
            -u "🖥️ $HOSTNAME: $subject" \
            -m "$full_message" \
            -s "$SMTP_SERVER:$SMTP_PORT" \
            -xu "$SMTP_USER" \
            -xp "$SMTP_PASS" \
            -o tls=no \
            -o timeout=10 \
            -o message-charset=UTF-8
}

# Проверка диска
check_space() {
  local output=$(df -h / | awk 'NR==2 {print $5 " " $6}')
  local used_percent=$(echo "$output" | awk '{print $1}' | cut -d'%' -f1)
  local partition=$(echo "$output" | awk '{print $2}')
  
  if [ "$used_percent" -ge 95 ]; then
    send_alert "‼️ КРИТИЧЕСКИЙ" \
              "Диск заполнен на $used_percent%" \
              "Раздел $partition: ${used_percent}% занято"
  elif [ "$used_percent" -ge 90 ]; then
    send_alert "⚠️ ВНИМАНИЕ" \
              "
