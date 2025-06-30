#!/bin/bash

cat <<EOF | sudo tee /etc/default/minio

# Все диски всех узлов (используй приватные IP)
MINIO_VOLUMES="http://176.1.192.156/mnt/disk1/minio http://176.1.192.156/mnt/disk2/minio \\
               http://176.1.192.157/mnt/disk1/minio http://176.1.192.157/mnt/disk2/minio \\
               http://176.1.192.158/mnt/disk1/minio http://176.1.192.158/mnt/disk2/minio \\
               http://176.1.192.159/mnt/disk1/minio http://176.1.192.159/mnt/disk2/minio"

# Админ логин и пароль
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="h%sC2JYYaq5b*Lm7"

# Интерфейс и консоль
MINIO_ADDRESS=":9000"
MINIO_CONSOLE_ADDRESS=":9001"
EOF

echo "✅ Конфигурация MinIO сохранена в /etc/default/minio"
