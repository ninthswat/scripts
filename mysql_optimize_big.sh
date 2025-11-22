#!/bin/bash
# Оптимизация всех баз MySQL/InnoDB > 10ГБ
# Размер определяется по каталогу /var/lib/mysql/<dbname>
# Использует доступ из ~/.my.cnf
# Логирует размер до/после и время выполнения
# Отправляет отчёт по email только по базам, где были работы

MYSQL_DATA_DIR="/var/lib/mysql"
THRESHOLD_GB=10
LOGFILE="/var/log/mysql_optimize_big.log"
REPORT="/tmp/mysql_optimize_report.txt"

EMAIL="level2@hostfly.by"
FROM="HostFly Мониторинг <support@hostfly.by>"
SUBJECT="Отчёт оптимизации MySQL баз ($(date '+%Y-%m-%d'))"

echo "=== Запуск оптимизации $(date) ===" >> $LOGFILE
echo "Отчёт оптимизации баз данных ($(date))" > $REPORT

worked=false

for dbdir in $MYSQL_DATA_DIR/*; do
    [ -d "$dbdir" ] || continue
    db=$(basename "$dbdir")

    size_bytes=$(du -sb "$dbdir" | awk '{print $1}')
    size_gb=$(echo "scale=2; $size_bytes/1024/1024/1024" | bc)

    if (( $(echo "$size_gb > $THRESHOLD_GB" | bc -l) )); then
        echo "--- База $db (до: ${size_gb}ГБ) ---" >> $LOGFILE
        start_time=$(date +%s)

        mysqlcheck --optimize "$db" >> $LOGFILE 2>&1

        size_bytes_after=$(du -sb "$dbdir" | awk '{print $1}')
        size_gb_after=$(echo "scale=2; $size_bytes_after/1024/1024/1024" | bc)

        end_time=$(date +%s)
        duration=$((end_time - start_time))

        echo "После: ${size_gb_after}ГБ" >> $LOGFILE
        echo "Изменение: $(echo "scale=2; ($size_gb - $size_gb_after)/$size_gb*100" | bc)% уменьшения" >> $LOGFILE
        echo "Время выполнения: ${duration} секунд" >> $LOGFILE

        # Добавляем в отчёт
        echo "База: $db" >> $REPORT
        echo "До: ${size_gb}ГБ, После: ${size_gb_after}ГБ" >> $REPORT
        echo "Уменьшение: $(echo "scale=2; ($size_gb - $size_gb_after)/$size_gb*100" | bc)% | Время: ${duration} сек" >> $REPORT
        echo "----------------------------------------" >> $REPORT

        worked=true
    fi
done

echo "=== Завершено $(date) ===" >> $LOGFILE

# Отправка отчёта только если были работы
if [ "$worked" = true ]; then
(
    echo "To: $EMAIL"
    echo "From: $FROM"
    echo "Subject: $SUBJECT"
    echo
    cat $REPORT
) | sendmail -t
fi
