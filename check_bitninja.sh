#!/bin/bash

# Конфигурация SMTP
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="support@hostfly.by"
RECIPIENT_EMAIL="ninthswat@gmail.com"  # Автоматически заменяется при установке
LOG_FILE="/var/log/bitninja_monitor.log"
HOSTNAME=$(hostname)

# Функция отправки email (русские темы)
send_alert() {
    local subject=$1
    local body=$2
    
    local full_message="Сервер: $HOSTNAME\nДата: $(date '+%Y-%m-%d %H:%M:%S')\n\n$body\n\nСтатус BitNinja:\n$(systemctl status bitninja --no-pager 2>&1)"
    
    sendEmail -f "$SMTP_FROM" \
              -t "$RECIPIENT_EMAIL" \
              -u "$subject" \
              -m "$full_message" \
              -s "$SMTP_SERVER:$SMTP_PORT" \
              -xu "$SMTP_USER" \
              -xp "$SMTP_PASS" \
              -o tls=no \
              -o message-charset=UTF-8 >/dev/null 2>&1 || \
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка отправки письма" >> "$LOG_FILE"
}

# Функция проверки процесса
check_process() {
    if ! pgrep -f "$1" >/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Процесс '$1' не запущен!" >> "$LOG_FILE"
        return 1
    fi
    return 0
}

# Проверка основных процессов BitNinja
ERRORS=0

# 1. Критичные сервисы
check_process "bitninja \[Main\]" || ERRORS=1
check_process "/opt/bitninja-mq/bin/bitninja-mq-server" || ERRORS=1
check_process "bitninja-dispatcher" || ERRORS=1
check_process "/opt/bitninja-process-analysis/bitninja-process-analysis" || ERRORS=1

# 2. Ключевые модули защиты
check_process "bitninja \[IpFilter\]" || ERRORS=1
check_process "bitninja \[MalwareDetection\]" || ERRORS=1
check_process "bitninja \[WAFManager\]" || ERRORS=1
check_process "bitninja \[Shogun\]" || ERRORS=1

# 3. Проверка воркеров
if [ $(pgrep -f "worker-yara.py /var/lib/bitninja/MalwareDetection/yara.yar" | wc -l) -lt 3 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Мало процессов worker-yara.py для MalwareDetection!" >> "$LOG_FILE"
    ERRORS=1
fi

if ! pgrep -f "worker-yara.py /opt/bitninja/modules/SqlScanner/bin/rules.yar" >/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Нет процессов worker-yara.py для SqlScanner!" >> "$LOG_FILE"
    ERRORS=1
fi

if ! pgrep -f "sync-rpc/lib/worker.js" >/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Нет Node.js worker для SandboxScanner!" >> "$LOG_FILE"
    ERRORS=1
fi

# 4. Проверка Nginx (WAF)
if ! pgrep -f "nginx: master process /opt/bitninja-waf/sbin/nginx" >/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Nginx (WAF) не запущен!" >> "$LOG_FILE"
    ERRORS=1
fi

# Действия при обнаружении проблем
if [ "$ERRORS" -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Обнаружены проблемы, перезапускаю BitNinja..." >> "$LOG_FILE"
    send_alert "ВНИМАНИЕ: Проблемы с BitNinja" "Обнаружены упавшие процессы BitNinja. Пытаюсь перезапустить..."
    
    systemctl restart bitninja
    sleep 10
    
    # Проверка после перезапуска
    if pgrep -f "bitninja \[Main\]" >/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - BitNinja успешно перезапущен" >> "$LOG_FILE"
        send_alert "ВОССТАНОВЛЕНО: BitNinja работает" "Сервис BitNinja был успешно перезапущен."
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка перезапуска BitNinja!" >> "$LOG_FILE"
        send_alert "КРИТИЧЕСКО: Ошибка перезапуска BitNinja" "Не удалось перезапустить BitNinja! Требуется ручное вмешательство."
    fi
fi
