#!/usr/bin/env bash
# Erweitert den bestehenden LVM-Pool (vg_backup) um eine weitere, leere
# Festplatte und vergroessert das Dateisystem online - ohne Downtime,
# Garage/Docker koennen dabei weiterlaufen.
#
# ACHTUNG: Loescht die angegebene Platte komplett!
#
# Aufruf: sudo ./scripts/lvm-add-disk.sh /dev/sdY

set -euo pipefail

VG_NAME="vg_backup"
LV_NAME="lv_garage_data"
MOUNTPOINT="${BACKUP_POOL_MOUNT:-/mnt/backup-pool}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte mit sudo/als root ausfuehren." >&2
  exit 1
fi

DISK="${1:-}"
if [ -z "$DISK" ] || [ ! -b "$DISK" ]; then
  echo "Nutzung: $0 /dev/sdY  (Blockgeraet der neuen, leeren Platte)" >&2
  exit 1
fi

if ! vgs "$VG_NAME" >/dev/null 2>&1; then
  echo "FEHLER: Volume Group '$VG_NAME' existiert nicht. Erst lvm-init-pool.sh ausfuehren." >&2
  exit 1
fi

if mount | grep -q "^${DISK}"; then
  echo "FEHLER: $DISK (oder eine Partition davon) ist aktuell gemountet. Abbrechen." >&2
  exit 1
fi

echo "Folgende Platte wird KOMPLETT GELOESCHT und zu '${VG_NAME}' hinzugefuegt:"
echo
lsblk "$DISK"
echo
read -r -p "Wirklich fortfahren? Tippe genau 'YES' zum Bestaetigen: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Abgebrochen."
  exit 1
fi

parted -s "$DISK" mklabel gpt mkpart primary 0% 100%
sleep 1
PART="${DISK}1"
[ -b "$PART" ] || PART="${DISK}p1"

pvcreate -y "$PART"
vgextend "$VG_NAME" "$PART"
lvextend -l +100%FREE "/dev/${VG_NAME}/${LV_NAME}"

# Online-Vergroesserung des XFS-Dateisystems (funktioniert bei gemountetem FS)
xfs_growfs "$MOUNTPOINT"

echo
echo "Fertig. Neue Kapazitaet:"
df -h "$MOUNTPOINT"
vgs "$VG_NAME"
