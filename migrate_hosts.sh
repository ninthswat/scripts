#!/bin/bash

# Целевой сервер для миграции
TARGET_SERVER="10.10.10.14"

# Файл для логирования (будет создан в текущей директории)
LOG_FILE="migration.log"

# Пауза между миграциями (в секундах)
MIGRATION_DELAY=2

# Список хостов для миграции
HOSTS=(
  "srv.namehunter.ru"
  "server.webcenter.by"
  "cloud.3rrr.ninja"
  "testtravel.testing.com"
  "Evgeni.goncharov.com"
  "pay.in-belarus.com"
  "sm28b.by"
  "baineel.com"
  "stendton.admin.com"
  "vm135.by2.by"
  "server.heat.by"
  "bots.by"
  "backend"
  "server.time-online.ru"
  "proxy-by"
  "server.andraktiv.com"
  "calisto"
  "izener.by"
  "cloud.j2moto.by"
  "belrusmarket.ru"
  "opt.rondopack.by"
  "vps.backup-pap.by"
  "radiodom"
  "server.erpeor.by"
  "tsobako.me"
  "qi-center.by"
  "skania"
  "by.ivi.ru"
  "sstp2.pallam.dev"
  "alpa-server"
  "BYLX"
  "cloud.rivalsvarka.by"
  "cloud.foerch.by"
  "yamaguchi-massage.by"
  "excavator01.stroyexcavator.by"
  "admin.iparts.by"
  "belarusnode1.com"
  "server.nedorogo.by"
  "fox3.by"
  "cloud.brpo.by"
  "server.itop.by"
  "vm110.by2.by"
  "server2.onalogahby.com"
  "server.dmitryshundrik.com"
  "rdb3.belsmeta.by"
)

# Создаем/очищаем файл лога
echo "=== Начало миграции $(date) ===" > "$LOG_FILE"

# Процесс миграции
for host in "${HOSTS[@]}"; do
  echo "Мигрируем $host на $TARGET_SERVER..."
  echo "[$(date)] Начало миграции $host" >> "$LOG_FILE"
  
  if prlctl migrate "$host" "$TARGET_SERVER" >> "$LOG_FILE" 2>&1; then
    echo "Успешно: $host" | tee -a "$LOG_FILE"
  else
    echo "ОШИБКА: $host (см. $LOG_FILE)" | tee -a "$LOG_FILE"
  fi
  
  # Пауза между миграциями
  echo "Ожидание $MIGRATION_DELAY сек..."
  sleep "$MIGRATION_DELAY"
done

echo "=== Все операции завершены ===" >> "$LOG_FILE"
echo "Готово! Результаты в $LOG_FILE"
