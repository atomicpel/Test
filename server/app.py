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
