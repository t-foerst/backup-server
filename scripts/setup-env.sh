#!/usr/bin/env bash
# Erstellt .env aus .env.example und befuellt alle Garage-Secrets mit
# zufaelligen Werten. NETBIRD_SETUP_KEY muss danach noch manuell eingetragen
# werden.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo ".env existiert bereits - wird nicht ueberschrieben."
  echo "Zum Neugenerieren der Secrets erst .env loeschen oder Werte manuell anpassen."
  exit 0
fi

cp .env.example .env

sed -i "s|^GARAGE_RPC_SECRET=.*|GARAGE_RPC_SECRET=$(openssl rand -hex 32)|" .env
sed -i "s|^GARAGE_ADMIN_TOKEN=.*|GARAGE_ADMIN_TOKEN=$(openssl rand -base64 32)|" .env
sed -i "s|^GARAGE_DEFAULT_ACCESS_KEY=.*|GARAGE_DEFAULT_ACCESS_KEY=GK$(openssl rand -hex 12)|" .env
sed -i "s|^GARAGE_DEFAULT_SECRET_KEY=.*|GARAGE_DEFAULT_SECRET_KEY=$(openssl rand -hex 32)|" .env

echo ".env wurde erstellt, Garage-Secrets sind gesetzt."
echo "Noch offen: NETBIRD_SETUP_KEY in .env eintragen (und NETBIRD_MANAGEMENT_URL, falls selbst gehostet)."
