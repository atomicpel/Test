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
