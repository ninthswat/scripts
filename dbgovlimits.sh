#!/bin/bash

# Устанавливаем лимиты CPU для различных пакетов
/usr/share/lve/dbgovernor/governor_package_limitting.py set --package CloudBusiness --cpu=1000,600,440,360
/usr/share/lve/dbgovernor/governor_package_limitting.py set --package CloudStart --cpu=500,300,220,180
/usr/share/lve/dbgovernor/governor_package_limitting.py set --package CloudMini --cpu=250,150,110,90

/usr/share/lve/dbgovernor/governor_package_limitting.py set --package WP_business --cpu=1000,600,440,360
/usr/share/lve/dbgovernor/governor_package_limitting.py set --package WP_start --cpu=500,300,220,180
/usr/share/lve/dbgovernor/governor_package_limitting.py set --package WP_mini --cpu=250,150,110,90

/usr/share/lve/dbgovernor/governor_package_limitting.py set --package 'Bitrix Start' --cpu=500,300,220,180
/usr/share/lve/dbgovernor/governor_package_limitting.py set --package 'BitrixStart-NVMe' --cpu=500,300,220,180
/usr/share/lve/dbgovernor/governor_package_limitting.py set --package 'Bitrix mini' --cpu=250,150,110,90

echo "Все команды выполнены успешно"
