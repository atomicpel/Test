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
if [[ "${1:-}" == "--publish-code" ]]; then
  echo "https://${2:-ДОМЕН}#$(sudo grep '^CYCLE_PUBLISH_TOKEN=' /etc/cycle-sync.env | cut -d= -f2-)"
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

Кроме того, сервер раздаёт само приложение и его обновления:
  GET  /app                 — страница скачивания
  GET  /app/MyCycle.apk     — последняя версия
  GET  /app/version.json    — номер версии (по нему приложение ищет обновления)
  POST /api/publish         — загрузка новой версии из сборки GitHub
                              (отдельный токен CYCLE_PUBLISH_TOKEN)
"""
import hashlib
import html
import json
import os
import secrets
import sqlite3
import threading
import time

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field

DB_PATH = os.environ.get("CYCLE_DB", "/var/lib/cycle-sync/cycle.db")
TOKEN = os.environ.get("CYCLE_TOKEN", "")
PUBLISH_TOKEN = os.environ.get("CYCLE_PUBLISH_TOKEN", "")
APP_DIR = os.environ.get("CYCLE_APP_DIR",
                         os.path.join(os.path.dirname(DB_PATH) or ".", "app"))
APK = "MyCycle.apk"
MAX_APK = 150 * 1024 * 1024
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


# ---------------------------------------------------------------- приложение


def _version() -> dict | None:
    try:
        with open(os.path.join(APP_DIR, "version.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _no_cache(resp):
    resp.headers["Cache-Control"] = "no-cache"
    return resp


@app.post("/api/publish")
async def publish(
    request: Request,
    authorization: str = Header(default=""),
    x_version: str = Header(default=""),
    x_build: int = Header(default=0),
):
    """Загрузка нового APK. Тело запроса — сам файл."""
    if not PUBLISH_TOKEN:
        raise HTTPException(503, "Публикация не настроена (CYCLE_PUBLISH_TOKEN)")
    given = authorization.removeprefix("Bearer ").strip()
    if not secrets.compare_digest(given, PUBLISH_TOKEN):
        raise HTTPException(401, "Неверный токен публикации")
    if x_build <= 0 or not x_version:
        raise HTTPException(400, "Нужны заголовки X-Version и X-Build")
    os.makedirs(APP_DIR, exist_ok=True)
    tmp = os.path.join(APP_DIR, f".upload-{secrets.token_hex(4)}")
    h = hashlib.sha256()
    size = 0
    try:
        with open(tmp, "wb") as f:
            async for chunk in request.stream():
                size += len(chunk)
                if size > MAX_APK:
                    raise HTTPException(413, "Файл слишком большой")
                h.update(chunk)
                f.write(chunk)
        with open(tmp, "rb") as f:
            if f.read(2) != b"PK":
                raise HTTPException(400, "Это не APK")
        os.replace(tmp, os.path.join(APP_DIR, APK))
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    info = {
        "version": x_version,
        "build": x_build,
        "size": size,
        "sha256": h.hexdigest(),
        "url": f"/app/{APK}",
        "published": int(time.time() * 1000),
    }
    vtmp = os.path.join(APP_DIR, ".version.json")
    with open(vtmp, "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False)
    os.replace(vtmp, os.path.join(APP_DIR, "version.json"))
    return info


@app.get("/app/version.json")
def version_json():
    v = _version()
    if not v:
        raise HTTPException(404, "Версия ещё не опубликована")
    return _no_cache(FileResponse(os.path.join(APP_DIR, "version.json"),
                                  media_type="application/json"))


@app.get(f"/app/{APK}")
def apk():
    path = os.path.join(APP_DIR, APK)
    if not os.path.exists(path):
        raise HTTPException(404, "Версия ещё не опубликована")
    v = _version() or {}
    name = f"MyCycle-{v.get('version', '')}.apk".replace("-.apk", ".apk")
    return _no_cache(FileResponse(
        path, media_type="application/vnd.android.package-archive", filename=name))


@app.get("/app/")
def app_slash():
    return RedirectResponse("/app", status_code=308)


@app.get("/app", response_class=HTMLResponse)
def app_page():
    v = _version()
    if v:
        ver = html.escape(str(v.get("version", "")))
        mb = f"{v.get('size', 0) / 1048576:.1f}"
        body = (f'<p class="v">Версия {ver} · {mb} МБ</p>'
                f'<a class="btn" href="/app/{APK}">Скачать APK</a>'
                '<p class="h">После скачивания откройте файл и разрешите установку '
                'из этого источника. Обновление ставится поверх, записи сохраняются.</p>')
    else:
        body = '<p class="v">Версия ещё не опубликована.</p>'
    return f"""<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Мой цикл</title><style>
body{{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:#222225;color:#f2f2f5;font-family:system-ui,sans-serif;text-align:center}}
main{{padding:24px;max-width:360px}}
.ring{{width:120px;height:120px;border-radius:50%;border:14px solid #d2a679;margin:0 auto 18px;
box-sizing:border-box;display:flex;align-items:center;justify-content:center;font-size:40px}}
h1{{font-size:24px;margin:0 0 6px}}.v{{color:#a1a1aa;margin:0 0 22px}}
.btn{{display:inline-block;background:#8ea7e9;color:#1b1b1f;text-decoration:none;font-weight:700;
padding:14px 28px;border-radius:30px}}.h{{color:#a1a1aa;font-size:14px;margin-top:22px;line-height:1.4}}
</style></head><body><main><div class="ring">💧</div><h1>Мой цикл</h1>{body}</main></body></html>"""
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
# отдельный токен, которым сборка на GitHub выкладывает новые версии
if ! grep -q '^CYCLE_PUBLISH_TOKEN=' "$ENV_FILE"; then
  echo "CYCLE_PUBLISH_TOKEN=$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')" >> "$ENV_FILE"
fi
sed -i '/^CYCLE_PORT=/d; /^CYCLE_APP_DIR=/d' "$ENV_FILE"
echo "CYCLE_PORT=$PORT" >> "$ENV_FILE"
echo "CYCLE_APP_DIR=$DATA_DIR/app" >> "$ENV_FILE"
mkdir -p "$DATA_DIR/app" && chown cycle:cycle "$DATA_DIR/app"

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
	# новая версия приложения из сборки GitHub
	handle /api/publish {
		request_body {
			max_size 200MB
		}
		reverse_proxy 127.0.0.1:$PORT
	}
	handle /api/* {
		request_body {
			max_size 5MB
		}
		reverse_proxy 127.0.0.1:$PORT
	}
	# страница и файл для скачивания приложения
	handle /app* {
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
echo
PUB=$(grep '^CYCLE_PUBLISH_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
echo " СКАЧАТЬ ПРИЛОЖЕНИЕ:  $SCHEME://$DOMAIN/app"
echo
echo " ДЛЯ ОБНОВЛЕНИЙ С ЭТОГО СЕРВЕРА — секрет в GitHub"
echo " (репозиторий → Settings → Secrets and variables → Actions → New repository secret)"
echo "   Имя:      CYCLE_PUBLISH"
echo "   Значение: $SCHEME://$DOMAIN#$PUB"
echo " Показать ещё раз:  sudo bash $0 --publish-code $DOMAIN"
echo "=============================================="
