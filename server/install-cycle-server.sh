#!/usr/bin/env bash
# Установка сервера синхронизации «Мой цикл» на Ubuntu (VPS) с Caddy.
# Запуск:  sudo bash install-cycle-server.sh cycle.atomicpel.cloud-ip.cc
# Файл самодостаточный: код сервера встроен внутрь. Повторный запуск
# обновляет сервер, токен и данные сохраняются.
# Домен должен уже указывать на этот сервер. HTTPS-сертификат получает
# уже работающий Caddy — nginx и certbot НЕ ставятся.
# В Caddyfile добавляется один блок для домена (с резервной копией и
# проверкой конфигурации перед перезагрузкой; остальные сайты не трогаются).
set -euo pipefail

if [[ "${1:-}" == "--code" ]]; then
  echo "https://${2:-ДОМЕН}#$(sudo grep '^CYCLE_TOKEN=' /etc/cycle-sync.env | cut -d= -f2-)"
  exit 0
fi

DOMAIN="${1:-}"
PORT_FROM=8095          # с какого порта искать свободный
ENV_FILE=/etc/cycle-sync.env
CADDYFILE=/etc/caddy/Caddyfile
MARK_BEGIN="# >>> cycle-sync (Мой цикл) — блок управляется install-cycle-server.sh"
MARK_END="# <<< cycle-sync"
APP_DIR=/opt/cycle-sync
DATA_DIR=/var/lib/cycle-sync

if [[ -z "$DOMAIN" ]]; then
  echo "Укажите домен: sudo bash install-cycle-server.sh cycle.example.com"; exit 1
fi
if [[ $EUID -ne 0 ]]; then echo "Запустите через sudo"; exit 1; fi

# ---------- проверки до каких-либо изменений
command -v caddy >/dev/null 2>&1 || { echo "!!! Не найден caddy"; exit 1; }
[[ -f "$CADDYFILE" ]] || { echo "!!! Не найден $CADDYFILE"; exit 1; }
systemctl is-active --quiet caddy || { echo "!!! Служба caddy не запущена"; exit 1; }

# кто держит 80/443 — должен быть Caddy
for p in 80 443; do
  owner=$(ss -Hltnp "sport = :$p" 2>/dev/null | grep -o 'users:(("[^"]*' | head -1 | cut -d'"' -f2 || true)
  if [[ -n "$owner" && "$owner" != "caddy" ]]; then
    echo "!!! Порт $p занят процессом «$owner», а не Caddy — сертификат может не выдаться."
  fi
done

# домен не должен уже обслуживаться другим сайтом в Caddyfile
CADDY_OTHER=$(sed "/^$MARK_BEGIN/,/^$MARK_END/d" "$CADDYFILE")
DOMAIN_RE=${DOMAIN//./\\.}
if grep -qE "(^|[[:space:],/])${DOMAIN_RE}([[:space:],:{]|$)" <<<"$CADDY_OTHER"; then
  echo "!!! $DOMAIN уже есть в $CADDYFILE у другого сайта. Выберите другой поддомен."
  exit 1
fi

# порт: занят ли кем-то, кроме нашей службы, или упомянут в чужих блоках Caddy
port_taken() {
  local port=$1
  ss -Hltn "sport = :$port" 2>/dev/null | grep -q . && return 0
  grep -qE ":$port([^0-9]|$)" <<<"$CADDY_OTHER" && return 0
  return 1
}
OLD_PORT=$(grep -s '^CYCLE_PORT=' "$ENV_FILE" | cut -d= -f2- || true)
systemctl stop cycle-sync 2>/dev/null || true   # чтобы свой же порт не считался занятым
PORT=""
for cand in $OLD_PORT $(seq $PORT_FROM $((PORT_FROM + 100))); do
  if port_taken "$cand"; then
    echo "Порт $cand занят — пропускаю"
  else
    PORT=$cand; break
  fi
done
[[ -n "$PORT" ]] || { echo "!!! Не нашёл свободный порт"; exit 1; }
echo "Порт сервера синхронизации: 127.0.0.1:$PORT"

apt-get update -qq
apt-get install -y -qq python3-venv curl

id cycle >/dev/null 2>&1 || useradd --system --home "$DATA_DIR" --shell /usr/sbin/nologin cycle
mkdir -p "$APP_DIR" "$DATA_DIR"
cat > "$APP_DIR/app.py" <<'PYEOF'
"""Сервер синхронизации для приложения «Мой цикл».

Хранит записи вида key -> JSON (дни, настройки) в SQLite.
Каждое изменение получает возрастающий номер ревизии (rev),
клиенты забирают всё, что новее их последней ревизии.
Конфликты решаются по updated_at (последняя правка побеждает).
"""
import json
import os
import secrets
import sqlite3
import threading
import time

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

DB_PATH = os.environ.get("CYCLE_DB", "/var/lib/cycle-sync/cycle.db")
TOKEN = os.environ.get("CYCLE_TOKEN", "")
MAX_CHANGES = 5000

app = FastAPI(title="cycle-sync", docs_url=None, redoc_url=None, openapi_url=None)
_lock = threading.Lock()


def db() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute(
        """CREATE TABLE IF NOT EXISTS records(
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            rev INTEGER NOT NULL
        )"""
    )
    con.execute("CREATE INDEX IF NOT EXISTS records_rev ON records(rev)")
    return con


def check_token(authorization: str = Header(default="")) -> None:
    if not TOKEN:
        raise HTTPException(500, "CYCLE_TOKEN не задан на сервере")
    given = authorization.removeprefix("Bearer ").strip()
    if not secrets.compare_digest(given, TOKEN):
        raise HTTPException(401, "Неверный токен")


class Change(BaseModel):
    key: str = Field(max_length=100)
    value: object | None = None
    updated_at: int
    deleted: bool = False


class SyncRequest(BaseModel):
    since: int = 0
    changes: list[Change] = Field(default_factory=list, max_length=MAX_CHANGES)


@app.get("/api/health")
def health():
    return {"ok": True, "time": int(time.time() * 1000)}


@app.post("/api/sync", dependencies=[Depends(check_token)])
def sync(req: SyncRequest):
    with _lock:
        con = db()
        try:
            cur_rev = con.execute("SELECT COALESCE(MAX(rev),0) FROM records").fetchone()[0]
            for ch in req.changes:
                row = con.execute(
                    "SELECT updated_at FROM records WHERE key=?", (ch.key,)
                ).fetchone()
                if row and row[0] >= ch.updated_at:
                    continue  # на сервере версия новее или та же
                cur_rev += 1
                con.execute(
                    """INSERT INTO records(key,value,updated_at,deleted,rev)
                       VALUES(?,?,?,?,?)
                       ON CONFLICT(key) DO UPDATE SET value=excluded.value,
                       updated_at=excluded.updated_at, deleted=excluded.deleted,
                       rev=excluded.rev""",
                    (ch.key, json.dumps(ch.value, ensure_ascii=False),
                     ch.updated_at, int(ch.deleted), cur_rev),
                )
            con.commit()
            rows = con.execute(
                "SELECT key,value,updated_at,deleted,rev FROM records WHERE rev>? ORDER BY rev",
                (req.since,),
            ).fetchall()
        finally:
            con.close()
    return {
        "rev": cur_rev,
        "changes": [
            {"key": k, "value": json.loads(v) if v else None,
             "updated_at": u, "deleted": bool(d)}
            for k, v, u, d, _ in rows
        ],
    }
PYEOF
cat > "$APP_DIR/requirements.txt" <<'REQEOF'
fastapi>=0.110
uvicorn>=0.29
REQEOF
chown -R cycle:cycle "$DATA_DIR"
chmod 700 "$DATA_DIR"

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"

# Токен создаётся один раз и сохраняется
if [[ ! -f "$ENV_FILE" ]]; then
  echo "CYCLE_TOKEN=$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')" > "$ENV_FILE"
  echo "CYCLE_DB=$DATA_DIR/cycle.db" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi
sed -i '/^CYCLE_PORT=/d' "$ENV_FILE"
echo "CYCLE_PORT=$PORT" >> "$ENV_FILE"

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

systemctl daemon-reload
systemctl enable --now cycle-sync
systemctl restart cycle-sync

# ---------- Caddy: свой блок между метками (повторный запуск его заменяет)
BAK="$CADDYFILE.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$CADDYFILE" "$BAK"
{
  sed "/^$MARK_BEGIN/,/^$MARK_END/d" "$BAK"
  cat <<EOF

$MARK_BEGIN
$DOMAIN {
	encode gzip
	request_body {
		max_size 5MB
	}
	handle /api/* {
		reverse_proxy 127.0.0.1:$PORT
	}
	handle {
		respond 404
	}
}
$MARK_END
EOF
} > "$CADDYFILE.new"
if caddy validate --adapter caddyfile --config "$CADDYFILE.new" >/dev/null 2>&1; then
  cat "$CADDYFILE.new" > "$CADDYFILE"     # права и владелец файла сохраняются
  rm -f "$CADDYFILE.new"
  systemctl reload caddy
  echo "Caddy: $DOMAIN -> 127.0.0.1:$PORT (резервная копия: $BAK)"
else
  echo "!!! Caddy не принял конфигурацию, $CADDYFILE не изменён. Ошибка:"
  caddy validate --adapter caddyfile --config "$CADDYFILE.new" 2>&1 | tail -5
  rm -f "$CADDYFILE.new"
  exit 1
fi

# Caddy получает сертификат за несколько секунд
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS "https://$DOMAIN/api/health" >/dev/null 2>&1 && break
  sleep 3
done

sleep 1
echo
TOKEN=$(grep '^CYCLE_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
SCHEME=https
curl -fsS "https://$DOMAIN/api/health" >/dev/null 2>&1 || SCHEME=http
echo "=============================================="
echo " Сервер: 127.0.0.1:$PORT (служба cycle-sync), сайт: $DOMAIN через Caddy"
echo " Проверка: curl $SCHEME://$DOMAIN/api/health"
curl -fsS "$SCHEME://$DOMAIN/api/health" && echo
echo
echo " КОД ПОДКЛЮЧЕНИЯ (скопируйте целиком в приложение):"
echo
echo "   $SCHEME://$DOMAIN#$TOKEN"
echo
echo " Показать код ещё раз:  sudo bash $0 --code $DOMAIN"
echo "=============================================="
