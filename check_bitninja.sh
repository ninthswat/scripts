#!/bin/bash

# Конфигурация SMTP
SMTP_SERVER="post.hostflyby.net"
SMTP_PORT="2525"
SMTP_USER="hfl/dn"
SMTP_PASS="s6tGiMzCee745dKO67zgAMT9"
SMTP_FROM="support@hostfly.by"
RECIPIENT_EMAIL="ninthswat@gmail.com"
LOG_FILE="/var/log/bitninja_monitor.log"
HOSTNAME=$(hostname)

# Переменные для сбора ошибок
ERROR_REASONS=()

# Функция отправки email
send_alert() {
    local subject=$1
    local body=$2
    
    local full_message="Сервер: $HOSTNAME\nДата: $(date '+%Y-%m-%d %H:%M:%S')\n\n$body\n\nПричины перезапуска:\n${ERROR_REASONS[*]}\n\nСтатус BitNinja:\n$(systemctl status bitninja --no-pager 2>&1)"
    
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
    local process_name=$1
    local description=$2
    
    if ! pgrep -f "$process_name" >/dev/null; then
        local error_msg="[$(date '+%Y-%m-%d %H:%M:%S')] Отсутствует процесс: $description ($process_name)"
        echo "$error_msg" >> "$LOG_FILE"
        ERROR_REASONS+=("$error_msg")
        return 1
    fi
    return 0
}

# Проверка основных процессов BitNinja
check_process "bitninja \[Main\]" "Основной процесс BitNinja" || ERRORS=1
check_process "/opt/bitninja-mq/bin/bitninja-mq-server" "Сервер очередей BitNinja" || ERRORS=1
check_process "bitninja-dispatcher" "Диспетчер BitNinja" || ERRORS=1
check_process "/opt/bitninja-process-analysis/bitninja-process-analysis" "Анализ процессов" || ERRORS=1

# Проверка ключевых модулей защиты
check_process "bitninja \[IpFilter\]" "Модуль IpFilter" || ERRORS=1
check_process "bitninja \[MalwareDetection\]" "Модуль MalwareDetection" || ERRORS=1
check_process "bitninja \[WAFManager\]" "Модуль WAFManager" || ERRORS=1
check_process "bitninja \[Shogun\]" "Модуль Shogun" || ERRORS=1

# Проверка воркеров YARA
if [ $(pgrep -f "worker-yara.py /var/lib/bitninja/MalwareDetection/yara.yar" | wc -l) -lt 3 ]; then
    error_msg="[$(date '+%Y-%m-%d %H:%M:%S')] Слишком мало процессов worker-yara.py для MalwareDetection (меньше 3)"
    echo "$error_msg" >> "$LOG_FILE"
    ERROR_REASONS+=("$error_msg")
    ERRORS=1
fi

if ! pgrep -f "worker-yara.py /opt/bitninja/modules/SqlScanner/bin/rules.yar" >/dev/null; then
    error_msg="[$(date '+%Y-%m-%d %H:%M:%S')] Отсутствуют процессы worker-yara.py для SqlScanner"
    echo "$error_msg" >> "$LOG_FILE"
    ERROR_REASONS+=("$error_msg")
    ERRORS=1
fi

# Проверка Nginx (WAF)
if ! pgrep -f "nginx: master process /opt/bitninja-waf/sbin/nginx" >/dev/null; then
    error_msg="[$(date '+%Y-%m-%d %H:%M:%S')] Nginx (WAF) не запущен"
    echo "$error_msg" >> "$LOG_FILE"
    ERROR_REASONS+=("$error_msg")
    ERRORS=1
fi

# Действия при обнаружении проблем
if [ ${#ERROR_REASONS[@]} -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Обнаружены проблемы, перезапускаю BitNinja..." >> "$LOG_FILE"
    
    # Формируем список причин для письма
    reasons_for_email=$(printf "%s\n" "${ERROR_REASONS[@]}")
    
    send_alert "ВНИМАНИЕ: Проблемы с BitNinja" "Обнаружены следующие проблемы:\n\n$reasons_for_email\n\nПытаюсь перезапустить BitNinja..."
    
    systemctl restart bitninja
    sleep 10
    
    # Проверка после перезапуска
    if pgrep -f "bitninja \[Main\]" >/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - BitNinja успешно перезапущен" >> "$LOG_FILE"
        send_alert "ВОССТАНОВЛЕНО: BitNinja работает" "Сервис BitNinja был успешно перезапущен после следующих проблем:\n\n$reasons_for_email"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка перезапуска BitNinja!" >> "$LOG_FILE"
        send_alert "КРИТИЧЕСКО: Ошибка перезапуска BitNinja" "Не удалось перезапустить BitNinja после следующих проблем:\n\n$reasons_for_email\n\nТребуется ручное вмешательство!"
    fi
fi
