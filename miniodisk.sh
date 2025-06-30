#!/bin/bash

DISKS=(/dev/sdb /dev/sdc)
MOUNTPOINTS=(/mnt/disk1 /mnt/disk2)

for i in ${!DISKS[@]}; do
  DEV=${DISKS[$i]}
  MP=${MOUNTPOINTS[$i]}

  echo "🔹 Проверка устройства: $DEV"
  if [ ! -b "$DEV" ]; then
    echo "❌ Диск $DEV не найден! Проверь имя."
    exit 1
  fi

  echo "🔹 Создаём таблицу GPT и раздел..."
  sudo parted $DEV --script mklabel gpt mkpart primary xfs 0% 100%

  PART=${DEV}1

  echo "🔹 Форматируем $PART в XFS..."
  sudo mkfs.xfs -f $PART

  echo "🔹 Создаём маунтпоинт $MP ..."
  sudo mkdir -p $MP

  UUID=$(sudo blkid -s UUID -o value $PART)

  echo "🔹 Добавляем в fstab..."
  echo "UUID=$UUID $MP xfs defaults,nofail 0 0" | sudo tee -a /etc/fstab

done

echo "🔹 Монтируем всё..."
sudo mount -a

echo "✅ Готово! Проверим:"
df -h | grep disk
