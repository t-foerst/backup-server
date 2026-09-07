# backup-server

Backup-Server auf Docker-Basis:

- **[Garage](https://garagehq.deuxfleurs.fr/)** als S3-kompatibler Objektspeicher (Single-Node, keine Replikation)
- **[Netbird](https://netbird.io/)** als VPN-Client, der diesen Server einem bestehenden Netbird-Netzwerk beitreten laesst
- **[node_exporter](https://github.com/prometheus/node_exporter)** fuer Host-Metriken (CPU, RAM, Disk, Netzwerk) via Prometheus

Backup-Clients (restic, rclone, borg, Duplicati, ...) laufen auf euren anderen Rechnern und schreiben ueber das Netbird-VPN per S3-Protokoll auf diesen Server. Dieses Repo stellt nur die Infrastruktur bereit - die eigentlichen Backup-Jobs konfiguriert ihr auf den Client-Rechnern selbst.

## Architektur

```
Backup-Client (restic/rclone/...)
        │  Netbird VPN (WireGuard)
        ▼
  Netbird-Interface auf diesem Host
        │
        ▼
  Garage S3 API (Port 3900)
```

`netbird` laeuft mit `network_mode: host`, damit das WireGuard-Interface direkt im Netzwerk-Namespace des Hosts entsteht. `garage` veroeffentlicht seine Ports regulaer ueber Docker, wodurch sie auf allen Host-Interfaces erreichbar sind - **auch auf einer eventuell vorhandenen oeffentlichen IP**. `node-exporter` laeuft ebenfalls mit `network_mode: host` (Standard fuer akkurate Netzwerk-/Disk-Metriken) und ist daher genauso auf allen Interfaces unter Port `9100` erreichbar. Schraenkt das nach Bedarf per Host-Firewall auf das Netbird-Subnetz (Standard: `100.64.0.0/10`) und `localhost` ein, wenn der Server oeffentlich erreichbar ist.

## Voraussetzungen

- Docker Engine + Docker Compose Plugin
- Ein Netbird-Account (Netbird Cloud, https://app.netbird.io) mit einem Setup-Key (Settings -> Setup Keys)

## Einrichtung

1. `.env` anlegen und mit zufaelligen Secrets fuellen:

   ```bash
   ./scripts/setup-env.sh
   ```

2. In `.env` den `NETBIRD_SETUP_KEY` eintragen (aus dem Netbird-Dashboard). Bei selbst gehostetem Netbird-Management zusaetzlich `NETBIRD_MANAGEMENT_URL` anpassen.

3. Starten:

   ```bash
   docker compose up -d
   ```

4. Pruefen, ob der Peer im Netbird-Netzwerk angekommen ist:

   ```bash
   docker compose exec netbird netbird status
   ```

   Dort steht auch die Netbird-IP dieses Servers (typischerweise `100.x.x.x`) - das ist die Adresse, unter der Backup-Clients den Server erreichen.

5. Beim ersten Start legt Garage automatisch einen Bucket (`GARAGE_DEFAULT_BUCKET`, Standard `backups`) sowie einen dazu passenden Access-Key/Secret-Key an (`GARAGE_DEFAULT_ACCESS_KEY` / `GARAGE_DEFAULT_SECRET_KEY` aus `.env`).

## Backup-Client konfigurieren

Beispiel mit restic:

```bash
export AWS_ACCESS_KEY_ID=<GARAGE_DEFAULT_ACCESS_KEY>
export AWS_SECRET_ACCESS_KEY=<GARAGE_DEFAULT_SECRET_KEY>
restic -r s3:http://<netbird-ip>:3900/<GARAGE_DEFAULT_BUCKET> init
```

Wichtig fuer jedes S3-Tool:

- **Path-style Addressing** verwenden (`http://host:3900/bucket/...`), nicht virtual-hosted-style - Garage ist standardmaessig darauf konfiguriert.
- Region: `garage` (siehe `garage/garage.toml`, `s3_region`)
- Endpoint: `http://<netbird-ip>:3900` (kein TLS - der Datenverkehr laeuft ja bereits verschluesselt durch das WireGuard-VPN)

## Verwaltung

Weitere Buckets/Keys anlegen:

```bash
docker compose exec garage /garage bucket create <name>
docker compose exec garage /garage key create <name>
docker compose exec garage /garage bucket allow --read --write --owner <bucket> --key <key>
```

Status/Uebersicht:

```bash
docker compose exec garage /garage status
docker compose exec garage /garage bucket list
docker compose exec garage /garage key list
```

## Monitoring (Prometheus)

`node-exporter` stellt Host-Metriken unter `http://<netbird-ip>:9100/metrics` bereit. In eurem Prometheus als Scrape-Target eintragen:

```yaml
scrape_configs:
  - job_name: backup-server
    static_configs:
      - targets: ["<netbird-ip>:9100"]
```

## Daten & Updates

- Metadaten (`garage-meta`) liegen in einem Docker-Volume auf der Systemplatte. Die eigentlichen Objektdaten liegen auf einem erweiterbaren LVM-Pool aus HDDs, der unter `BACKUP_POOL_MOUNT` (`.env`, Standard `/mnt/backup-pool`) eingehaengt und per Bind-Mount in den Garage-Container gegeben wird. Einrichtung und das spaetere Hinzufuegen weiterer Platten: siehe [STORAGE.md](./STORAGE.md).
- Updates: `docker compose pull && docker compose up -d`
- Image-Versionen sind gepinnt (`dxflrs/garage:v2.3.0`, `prom/node-exporter:v1.9.1`), `netbirdio/netbird:latest` folgt dagegen immer der neuesten Version - bei Bedarf in `docker-compose.yml` auf einen festen Tag umstellen.
