# Storage-Pool fuer Garage-Objektdaten

Die reinen Objektdaten von Garage (`data_dir`, die eigentlichen Backup-Bytes)
liegen auf einem **LVM-Pool** aus einer oder mehreren HDDs, der bei Bedarf um
weitere Platten erweitert wird. Die Metadaten (`meta_dir`, klein und
latenzempfindlich) bleiben bewusst auf der Systemplatte in einem normalen
Docker-Volume.

## Warum LVM linear (JBOD)

- Einfachste Erweiterung: neue Platte rein, ein Script ausfuehren, Kapazitaet
  ist online sofort verfuegbar - kein Rebuild/Resilver, keine Wartezeit.
- Kein RAID/Parity-Overhead - die volle Kapazitaet jeder Platte zaehlt.
- Bewusster Trade-off: **keine Redundanz**. Faellt eine Platte im Pool aus,
  ist das gesamte logische Volume betroffen (nicht nur die Dateien dieser
  einen Platte, wie es z.B. bei mergerfs waere). Das ist hier akzeptiert,
  weil die Backups selbst schon die Redundanz der Gesamtarchitektur sind -
  dieser Server haelt ohnehin nur eine Kopie (Garage laeuft mit
  `replication_factor = 1`).

## Einmaliges Setup (erste Platte)

```bash
lsblk                              # richtige, leere Platte identifizieren!
sudo ./scripts/lvm-init-pool.sh /dev/sdX
```

Das Script:
1. legt eine GPT-Partitionstabelle mit einer Partition an,
2. erstellt PV -> Volume Group `vg_backup` -> Logical Volume `lv_garage_data`,
3. formatiert mit XFS,
4. traegt den Mount per UUID in `/etc/fstab` ein und mountet unter
   `/mnt/backup-pool` (bzw. `BACKUP_POOL_MOUNT` aus `.env`, falls gesetzt).

Danach `docker compose up -d` (bzw. neu starten, falls schon gelaufen) -
`garage-data` wird dann von diesem Mount aus in den Container gebunden.

## Spaeter eine weitere Platte hinzufuegen

```bash
lsblk                              # neue, leere Platte identifizieren!
sudo ./scripts/lvm-add-disk.sh /dev/sdY
```

Das Script haengt die neue Platte an `vg_backup`, erweitert
`lv_garage_data` und vergroessert das XFS-Dateisystem online -
Garage/Docker muessen dafuer nicht gestoppt werden.

## Kontrolle

```bash
sudo vgs vg_backup      # Volume Group: Gesamt-/freie Kapazitaet
sudo lvs vg_backup      # Logical Volume
df -h /mnt/backup-pool  # tatsaechlich genutzter/freier Platz im Dateisystem
```

## Wichtig

- Beide Scripts **loeschen die angegebene Platte vollstaendig**. Immer erst
  mit `lsblk` pruefen, dass das richtige Geraet angegeben wird.
- Faellt eine Platte im Pool aus, ist der gesamte Pool betroffen (siehe
  oben). Ein Ausfall ersetzt also nicht die Notwendigkeit, wichtige Daten
  zusaetzlich woanders zu sichern - dieser Server *ist* bereits das Backup,
  er sollte selbst kein Single Point of Failure fuer die einzige Kopie sein.
