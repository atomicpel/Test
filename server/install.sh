#!/usr/bin/env bash
# Установка сервера синхронизации «Мой цикл» на Ubuntu (VPS).
# Запуск:  sudo bash install.sh cycle.atomicpel.cloud-ip.cc
# Домен должен уже указывать на этот сервер.
set -euo pipefail

DOMAIN="${1:-}"
PORT=8095
APP_DIR=/opt/cycle-sync
DATA_DIR=/var/lib/cycle-sync

if [[ -z "$DOMAIN" ]]; then
  echo "Укажите домен: sudo bash install.sh cycle.example.com"; exit 1
fi
if [[ $EUID -ne 0 ]]; then echo "Запустите через sudo"; exit 1; fi

apt-get update -qq
apt-get install -y -qq python3-venv nginx certbot python3-certbot-nginx

id cycle >/dev/null 2>&1 || useradd --system --home "$DATA_DIR" --shell /usr/sbin/nologin cycle
mkdir -p "$APP_DIR" "$DATA_DIR"
cp "$(dirname "$0")/app.py" "$(dirname "$0")/requirements.txt" "$APP_DIR/"
chown -R cycle:cycle "$DATA_DIR"
chmod 700 "$DATA_DIR"

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"

# Токен создаётся один раз и сохраняется
ENV_FILE=/etc/cycle-sync.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "CYCLE_TOKEN=$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')" > "$ENV_FILE"
  echo "CYCLE_DB=$DATA_DIR/cycle.db" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

cat > /etc/systemd/system/cycle-sync.service <<EOF
[Unit]
Description=Cycle sync server
After=network.target

[Service]
User=cycle
EnvironmentFile=$ENV_FILE
ExecStart=$APP_DIR/venv/bin/uvicorn app:app --host 127.0.0.1 --port $PORT --app-dir $APP_DIR
Restart=always
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/nginx/sites-available/cycle-sync <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 5m;
    location /api/ {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location / { return 404; }
}
EOF
ln -sf /etc/nginx/sites-available/cycle-sync /etc/nginx/sites-enabled/cycle-sync

systemctl daemon-reload
systemctl enable --now cycle-sync
systemctl restart cycle-sync
nginx -t && systemctl reload nginx

certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect || \
  echo "!!! certbot не смог получить сертификат — проверьте, что $DOMAIN указывает на этот сервер, и запустите: certbot --nginx -d $DOMAIN"

sleep 1
echo
echo "=============================================="
echo " Готово. Проверка: curl https://$DOMAIN/api/health"
echo " Адрес сервера для приложения: https://$DOMAIN"
grep CYCLE_TOKEN "$ENV_FILE" | sed 's/CYCLE_TOKEN=/ Токен для приложения: /'
echo "=============================================="
