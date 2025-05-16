#!/bin/bash

# Функция для вывода цветного сообщения
print_message() {
    local color=$1
    local message=$2
    case $color in
        green) echo -e "\e[32m[✓] $message\e[0m" ;;
        red) echo -e "\e[31m[✗] $message\e[0m" ;;
        blue) echo -e "\e[34m[i] $message\e[0m" ;;
        *) echo -e "[ ] $message" ;;
    esac
}

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    print_message red "Ошибка: скрипт должен запускаться с правами root!"
    exit 1
fi

print_message blue "Начинаем установку CPU лимитов для пакетов..."

# Массив с командами
commands=(
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package CloudBusiness --cpu=1000,600,440,360"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package CloudStart --cpu=500,300,220,180"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package CloudMini --cpu=250,150,110,90"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package WP_business --cpu=1000,600,440,360"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package WP_start --cpu=500,300,220,180"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package WP_mini --cpu=250,150,110,90"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package 'Bitrix Start' --cpu=500,300,220,180"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package 'BitrixStart-NVMe' --cpu=500,300,220,180"
    "/usr/share/lve/dbgovernor/governor_package_limitting.py set --package 'Bitrix mini' --cpu=250,150,110,90"
)

total_commands=${#commands[@]}
success_count=0

print_message blue "Всего команд для выполнения: $total_commands"

# Выполняем команды
for ((i=0; i<total_commands; i++)); do
    cmd=${commands[$i]}
    package=$(echo "$cmd" | grep -oP -- '--package \K[^ ]+')
    
    print_message blue "Выполняю команду $((i+1))/$total_commands: Установка лимитов для пакета $package"
    
    if eval "$cmd"; then
        print_message green "Успешно: лимиты для $package установлены"
        ((success_count++))
    else
        print_message red "Ошибка: не удалось установить лимиты для $package"
    fi
    
    echo ""
done

# Итоговый отчёт
print_message blue "===================================="
print_message blue "Итоговый отчёт:"
echo -e "Успешно выполнено: \e[32m$success_count\e[0m из \e[34m$total_commands\e[0m команд"
if [ $success_count -eq $total_commands ]; then
    print_message green "Все команды выполнены успешно!"
else
    print_message red "Некоторые команды завершились с ошибкой"
    print_message blue "Проверьте вывод выше для деталей"
fi
