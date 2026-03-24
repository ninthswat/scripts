#!/bin/bash
# ============================================================
# migrate-vm.sh — Virtuozzo 7 → Proxmox VE
# Запуск: с nas1 или любой source-ноды Virtuozzo
#
# Использование:
#   ./migrate-vm.sh <UUID_или_имя_VM> <user@PVE_HOST> <STORAGE> [VMID]
#
# Примеры:
#   ./migrate-vm.sh {84d85317-5edd-4edf-83ce-ec1673297cad} root@10.130.100.41 nvme-lvm-vol1
#   ./migrate-vm.sh lampa-max root@10.130.100.41 nvme-lvm-vol1 5005
#   ./migrate-vm.sh lampa-max root@10.130.100.41 nvme-lvm-vol1 --dry-run
# ============================================================

set -euo pipefail

# --- Цвета и логирование ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PVE_SSH_PORT=1288
VMID_MIN=5002
DRY_RUN=0
AUTO_YES=0
LOG_FILE="/dev/null"

log()  { echo -e "$(date '+%H:%M:%S') ${BOLD}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "$(date '+%H:%M:%S') ${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "$(date '+%H:%M:%S') ${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "$(date '+%H:%M:%S') ${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
step() { echo -e "\n$(date '+%H:%M:%S') ${CYAN}${BOLD}>>> $*${NC}" | tee -a "$LOG_FILE"; }
dry()  { echo -e "$(date '+%H:%M:%S') ${YELLOW}[DRY-RUN]${NC} $*" | tee -a "$LOG_FILE"; }

pve_ssh() { ssh -p "$PVE_SSH_PORT" -o StrictHostKeyChecking=no "$PVE_TARGET" "$@"; }
pve_dry() { dry "SSH $PVE_TARGET: $*"; }

run_pve() {
    if [[ $DRY_RUN -eq 1 ]]; then pve_dry "$@"; else pve_ssh "$@"; fi
}

# --- Парсинг аргументов ---
usage() {
    echo "Использование: $0 <UUID_или_имя> <user@PVE_HOST> <STORAGE> [VMID] [--dry-run]"
    echo "  UUID_или_имя  — UUID в {фигурных скобках} или имя VM"
    echo "  user@PVE_HOST — целевая нода PVE (напр. root@10.130.100.41)"
    echo "  STORAGE       — хранилище на PVE (напр. nvme-lvm-vol1)"
    echo "  VMID          — (опционально) конкретный ID, иначе авто от $VMID_MIN"
    echo "  --dry-run     — показать что будет делать без выполнения"
    exit 1
}

[[ $# -lt 3 ]] && usage

VM_ARG="$1"
PVE_TARGET="$2"
STORAGE="$3"
VMID_ARG=""

for arg in "${@:4}"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=1
    elif [[ "$arg" == "--yes" || "$arg" == "-y" ]]; then
        AUTO_YES=1
    else
        VMID_ARG="$arg"
    fi
done

# --- Проверка зависимостей ---
step "Шаг 0: Проверка зависимостей"
for cmd in prlctl qemu-img ssh; do
    command -v "$cmd" &>/dev/null || err "Не найден: $cmd"
done
ok "Все зависимости на месте"

# --- Поиск VM на Virtuozzo ---
step "Шаг 1: Получение информации о VM"

# Разрешаем UUID в фигурных скобках или имя
if [[ "$VM_ARG" =~ ^\{?[0-9a-f-]{36}\}?$ ]]; then
    UUID="${VM_ARG//[\{\}]/}"
    UUID="{$UUID}"
else
    UUID=$(prlctl list -a --output ctid,name | awk -v name="$VM_ARG" '$2==name{print $1}' | head -1)
    [[ -z "$UUID" ]] && err "VM '$VM_ARG' не найдена"
fi

log "UUID: $UUID"

VM_INFO=$(prlctl list -i "$UUID" 2>/dev/null) || err "Не удалось получить информацию о VM $UUID"

# Отключаем -e на время парсинга (grep выходит с 1 при отсутствии совпадений)
set +e
VM_NAME=$(echo "$VM_INFO"   | awk '/^Name:/{print $2}')
VM_CPU=$(echo "$VM_INFO"    | grep -oP 'cpus=\K\d+'              | head -1)
VM_RAM=$(echo "$VM_INFO"    | grep -oP 'memory \K\d+'            | head -1)  # в MB
VM_MAC=$(echo "$VM_INFO"    | grep -oP 'mac=\K[0-9A-Fa-f]+'     | head -1)
VM_STATUS=$(echo "$VM_INFO" | awk '/^State:/{print $2}')
VM_IPS=$(echo "$VM_INFO"    | grep -oP "ips='[^']+'" | grep -oP "'[^']+'" | tr -d "'" | tr ' ' '\n' | grep -v '^$' | paste -sd ', ')
set -e
SRC_HOST=$(hostname -f 2>/dev/null || hostname)

# Нормализуем MAC (Virtuozzo может выдавать без разделителей)
if [[ ${#VM_MAC} -eq 12 ]]; then
    VM_MAC=$(echo "$VM_MAC" | sed 's/../&:/g;s/:$//')
fi

[[ -z "$VM_NAME" ]] && err "Не удалось определить имя VM"
# Proxmox требует DNS-совместимое имя: только a-z0-9 и дефис (не подчёркивание)
VM_NAME_SAFE=$(echo "$VM_NAME" | tr '_' '-' | tr '[:upper:]' '[:lower:]')
[[ -z "$VM_CPU"  ]] && VM_CPU=2
[[ -z "$VM_RAM"  ]] && VM_RAM=2048
[[ -z "$VM_MAC"  ]] && warn "MAC не определён — будет сгенерирован автоматически"

# Диск
DISK_PATH="/vz/vmprivate/${UUID//[\{\}]/}/harddisk.hdd"
[[ -f "$DISK_PATH" ]] || err "Диск не найден: $DISK_PATH"

DISK_SIZE_REAL=$(du -sh "$DISK_PATH" | cut -f1)
DISK_SIZE_VIRT=$(qemu-img info "$DISK_PATH" 2>/dev/null | awk '/virtual size/{print $3,$4}')
DISK_FORMAT=$(qemu-img info "$DISK_PATH" 2>/dev/null | awk '/file format/{print $3}')

# Инициализируем лог (после получения VM_NAME)
LOG_FILE="/var/log/pve-migrate-${VM_NAME}.log"
: > "$LOG_FILE"  # создаём/очищаем

log "Имя VM:      $VM_NAME"
log "CPU:         $VM_CPU"
log "RAM:         ${VM_RAM} MB"
log "MAC:         ${VM_MAC:-авто}"
log "Статус:      $VM_STATUS"
log "Диск:        $DISK_PATH"
log "Формат:      $DISK_FORMAT"
log "Реальный:    $DISK_SIZE_REAL"
log "Виртуальный: $DISK_SIZE_VIRT"
[[ $DRY_RUN -eq 1 ]] && warn "РЕЖИМ DRY-RUN — изменений не будет"

# --- Авто-определение VMID ---
step "Шаг 2: Определение VMID"

if [[ -n "$VMID_ARG" ]]; then
    VMID="$VMID_ARG"
    log "VMID задан вручную: $VMID"
else
    if [[ $DRY_RUN -eq 1 ]]; then
        VMID="$VMID_MIN"
        dry "VMID = $VMID (dry-run, реальная проверка пропущена)"
    else
        USED_IDS=$(pve_ssh "pvesh get /cluster/resources --type vm 2>/dev/null | grep -oP '\"vmid\":\s*\K\d+'" 2>/dev/null || echo "")
        VMID=$VMID_MIN
        while echo "$USED_IDS" | grep -qw "$VMID"; do
            (( VMID++ ))
        done
        ok "Следующий свободный VMID: $VMID"
    fi
fi

LOG_FILE="/var/log/pve-migrate-${VM_NAME}-${VMID}.log"

# --- Подтверждение ---
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Миграция: $VM_NAME → PVE VMID $VMID${NC}"
echo -e "${BOLD}========================================${NC}"
echo -e "  Источник:  $UUID"
echo -e "  Цель:      $PVE_TARGET  (port $PVE_SSH_PORT)"
echo -e "  Storage:   $STORAGE"
echo -e "  Диск:      $DISK_SIZE_REAL реальных / $DISK_SIZE_VIRT виртуальных"
echo -e "  CPU/RAM:   $VM_CPU core / ${VM_RAM} MB"
[[ $DRY_RUN -eq 1 ]] && echo -e "  ${YELLOW}DRY-RUN: реальных изменений не будет${NC}"
echo ""

if [[ $DRY_RUN -eq 0 && $AUTO_YES -eq 0 ]]; then
    read -rp "Продолжить? [y/N] " CONFIRM </dev/tty
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { log "Отменено пользователем"; exit 0; }
fi

# --- Остановка VM ---
step "Шаг 3: Остановка VM на Virtuozzo"

if [[ "$VM_STATUS" == "running" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "prlctl stop $UUID"
    else
        log "Останавливаем $VM_NAME..."
        prlctl stop "$UUID" || err "Не удалось остановить VM"
        # Ждём stopped
        for i in $(seq 1 30); do
            STATUS=$(prlctl status "$UUID" 2>/dev/null | awk '{print $NF}')
            [[ "$STATUS" == "stopped" ]] && break
            sleep 2
        done
        STATUS=$(prlctl status "$UUID" 2>/dev/null | awk '{print $NF}')
        [[ "$STATUS" == "stopped" ]] || err "VM не остановилась за 60 секунд"
        ok "VM остановлена"
    fi
else
    log "VM уже остановлена (статус: $VM_STATUS)"
fi

# --- Копирование QCOW2 на PVE ---
step "Шаг 4: Копирование диска на PVE (без конвертации)"

REMOTE_QCOW="/tmp/migrate-${VMID}.qcow2"

if [[ $DRY_RUN -eq 1 ]]; then
    dry "cat $DISK_PATH | ssh -p $PVE_SSH_PORT $PVE_TARGET 'dd of=$REMOTE_QCOW bs=4M'"
else
    log "Копирование $DISK_SIZE_REAL → $PVE_TARGET:$REMOTE_QCOW"
    if command -v pv &>/dev/null; then
        pv "$DISK_PATH" | ssh -p "$PVE_SSH_PORT" -o StrictHostKeyChecking=no "$PVE_TARGET" \
            "dd of=$REMOTE_QCOW bs=4M 2>/dev/null"
    else
        cat "$DISK_PATH" | ssh -p "$PVE_SSH_PORT" -o StrictHostKeyChecking=no "$PVE_TARGET" \
            "dd of=$REMOTE_QCOW bs=4M status=progress"
    fi
    ok "Копирование завершено"
fi

# --- Конвертация QCOW2 → raw на PVE ---
step "Шаг 5: Конвертация QCOW2 → raw на PVE"

REMOTE_RAW="/tmp/migrate-${VMID}.raw"

run_pve "qemu-img convert -p -f qcow2 -O raw $REMOTE_QCOW $REMOTE_RAW && rm -f $REMOTE_QCOW"
ok "Конвертация завершена"

# --- Создание VM на PVE ---
step "Шаг 6: Создание VM $VMID на PVE"

MAC_PARAM=""
[[ -n "$VM_MAC" ]] && MAC_PARAM=",macaddr=$VM_MAC"

run_pve "qm create $VMID \
    --name $VM_NAME_SAFE \
    --cores $VM_CPU \
    --sockets 1 \
    --memory $VM_RAM \
    --net0 virtio,bridge=vmbr0${MAC_PARAM} \
    --ostype l26 \
    --scsihw virtio-scsi-single \
    --agent enabled=1 \
    --numa 1"

ok "VM $VMID создана"

# --- Импорт диска ---
step "Шаг 7: Импорт диска"

run_pve "qm importdisk $VMID $REMOTE_RAW $STORAGE --format raw"
run_pve "qm set $VMID --scsi0 ${STORAGE}:vm-${VMID}-disk-0,discard=on,iothread=1,ssd=1"
run_pve "qm set $VMID --ide2 ${STORAGE}:cloudinit"
run_pve "qm set $VMID --boot order=scsi0"
run_pve "qm set $VMID --hotplug disk,network,usb,memory,cpu"
run_pve "rm -f $REMOTE_RAW"

# --- Заметка о происхождении VM ---
UUID_CLEAN="${UUID//[\{\}]/}"
MIGRATE_DATE=$(date '+%Y-%m-%d %H:%M %Z')
MIGRATE_NOTE=$(printf 'Migrated from Virtuozzo\n\nSource node: %s\n\nOriginal name: %s\n\nUUID: %s\n\nIPs: %s\n\nDate: %s' \
    "$SRC_HOST" "$VM_NAME" "$UUID_CLEAN" "${VM_IPS:-unknown}" "$MIGRATE_DATE")
NOTE_B64=$(printf '%s' "$MIGRATE_NOTE" | base64 -w 0)
run_pve "qm set $VMID --description \"\$(echo '$NOTE_B64' | base64 -d)\""

ok "Диск импортирован и подключён"

# --- Запуск VM ---
step "Шаг 8: Запуск VM"

run_pve "qm start $VMID"
ok "VM $VMID запущена"

# --- Проверка ---
step "Шаг 9: Проверка"

if [[ $DRY_RUN -eq 0 ]]; then
    sleep 5
    STATUS=$(pve_ssh "qm status $VMID 2>/dev/null" || echo "unknown")
    log "Статус на PVE: $STATUS"

    # Проверка guest agent
    OSINFO=$(pve_ssh "qm guest cmd $VMID get-osinfo 2>/dev/null" || echo "")
    if [[ -n "$OSINFO" ]]; then
        ok "Guest agent отвечает"
        echo "$OSINFO" | grep -E '"pretty-name"|"name"' | tee -a "$LOG_FILE" || true
    else
        warn "Guest agent не отвечает (возможно VM ещё загружается)"
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}  Миграция $VM_NAME завершена!${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "  VMID:    $VMID"
echo -e "  Нода:    $PVE_TARGET"
echo -e "  Storage: $STORAGE"
echo -e "  Лог:     $LOG_FILE"
echo ""
