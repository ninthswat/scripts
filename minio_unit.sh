#!/bin/bash

sudo tee /etc/systemd/system/minio.service > /dev/null <<EOF
[Unit]
Description=MinIO Distributed Object Storage
Documentation=https://min.io
Wants=network-online.target
After=network-online.target

[Service]
User=minio-user
Group=minio-user
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server \$MINIO_VOLUMES --console-address "\$MINIO_CONSOLE_ADDRESS" --address "\$MINIO_ADDRESS"

Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Файл unit создан: /etc/systemd/system/minio.service"

echo "🔄 Перезагружаем systemd..."
sudo systemctl daemon-reload

echo "🔐 Включаем автозапуск MinIO..."
sudo systemctl enable minio

echo "▶️ Запускаем MinIO..."
sudo systemctl restart minio

echo "✅ MinIO активен. Проверь статус:"
echo "   sudo systemctl status minio"
