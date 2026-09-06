#!/usr/bin/env bash
# Initialisiert den LVM-Pool fuer die Garage-Objektdaten auf einer einzelnen,
# leeren Festplatte und mountet ihn unter /mnt/backup-pool (bzw. dem in
# BACKUP_POOL_MOUNT konfigurierten Pfad).
#
# Einmalig beim allerersten Setup ausfuehren. Fuer spaetere zusaetzliche
# Platten stattdessen lvm-add-disk.sh benutzen.
#
# ACHTUNG: Loescht die angegebene Platte komplett!
#
# Aufruf: sudo ./scripts/lvm-init-pool.sh /dev/sdX

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
  echo "Nutzung: $0 /dev/sdX  (Blockgeraet der neuen, leeren Platte)" >&2
  exit 1
fi

if vgs "$VG_NAME" >/dev/null 2>&1; then
  echo "FEHLER: Volume Group '$VG_NAME' existiert bereits. Fuer weitere Platten lvm-add-disk.sh benutzen." >&2
  exit 1
fi

if mount | grep -q "^${DISK}"; then
  echo "FEHLER: $DISK (oder eine Partition davon) ist aktuell gemountet. Abbrechen." >&2
  exit 1
fi

echo "Folgende Platte wird KOMPLETT GELOESCHT und als neuer LVM-Pool initialisiert:"
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
vgcreate "$VG_NAME" "$PART"
lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME"

mkfs.xfs -f "/dev/${VG_NAME}/${LV_NAME}"

mkdir -p "$MOUNTPOINT"
UUID=$(blkid -s UUID -o value "/dev/${VG_NAME}/${LV_NAME}")

if ! grep -q "$UUID" /etc/fstab; then
  echo "UUID=${UUID}  ${MOUNTPOINT}  xfs  defaults  0  2" >> /etc/fstab
fi

mount -a

echo
echo "Fertig. Pool ist eingehaengt unter ${MOUNTPOINT}:"
df -h "$MOUNTPOINT"
