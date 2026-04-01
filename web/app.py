"""
扫描文件 Web 管理器
通过浏览器在线查看、预览、下载打印机扫描的文件
"""

import json
import os
import secrets
from datetime import datetime
from functools import wraps

from flask import (
    Flask, render_template, send_from_directory,
    request, redirect, url_for, session, abort,
)

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", secrets.token_hex(32))

# ---------- 配置 ----------
SCAN_DIR = os.environ.get("SCAN_DIR", "/home/scanner/ftp/scans")
WEB_USER = os.environ.get("WEB_USER", "admin")
WEB_PASS = os.environ.get("WEB_PASS", "admin123")
HIDDEN_DB = os.environ.get("HIDDEN_DB", os.path.join(os.path.dirname(__file__), ".hidden_files.json"))
# ---------------------------

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".tiff", ".tif"}
PDF_EXT = {".pdf"}


def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return wrapper


def safe_path(subpath):
    """防止路径穿越"""
    base = os.path.realpath(SCAN_DIR)
    target = os.path.realpath(os.path.join(base, subpath))
    if not target.startswith(base):
        abort(403)
    return target


def normalize_relpath(subpath):
    normalized = os.path.normpath(subpath).replace("\\", "/").lstrip("/")
    if normalized in ("", "."):
        return ""
    return normalized


def build_fingerprint(stat):
    return {
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }


def load_hidden_files():
    if not os.path.exists(HIDDEN_DB):
        return {}

    try:
        with open(HIDDEN_DB, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}

    if not isinstance(data, dict):
        return {}

    hidden_files = {}
    for relpath, fingerprint in data.items():
        normalized = normalize_relpath(relpath)
        if not normalized or not isinstance(fingerprint, dict):
            continue

        size = fingerprint.get("size")
        mtime_ns = fingerprint.get("mtime_ns")
        if not isinstance(size, int) or not isinstance(mtime_ns, int):
            continue

        hidden_files[normalized] = {
            "size": size,
            "mtime_ns": mtime_ns,
        }

    return hidden_files


def save_hidden_files(hidden_files):
    directory = os.path.dirname(HIDDEN_DB)
    if directory:
        os.makedirs(directory, exist_ok=True)

    temp_path = f"{HIDDEN_DB}.tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(hidden_files, f, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(temp_path, HIDDEN_DB)


def is_hidden_file(hidden_files, relpath, stat):
    normalized = normalize_relpath(relpath)
    if not normalized:
        return False
    return hidden_files.get(normalized) == build_fingerprint(stat)


def human_size(size_bytes):
    for unit in ("B", "KB", "MB", "GB"):
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} TB"


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        if secrets.compare_digest(username, WEB_USER) and secrets.compare_digest(password, WEB_PASS):
            session["logged_in"] = True
            return redirect(url_for("index"))
        error = "用户名或密码错误"
    return render_template("login.html", error=error)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
@app.route("/browse/")
@app.route("/browse/<path:subpath>")
@login_required
def index(subpath=""):
    subpath = normalize_relpath(subpath)
    target = safe_path(subpath)
    hidden_files = load_hidden_files()

    if not os.path.exists(target):
        os.makedirs(target, exist_ok=True)

    if os.path.isfile(target):
        if is_hidden_file(hidden_files, subpath, os.stat(target)):
            abort(404)
        return redirect(url_for("download", subpath=subpath))

    # 列出目录内容
    items = []
    hidden_files_changed = False
    for name in sorted(os.listdir(target)):
        full = os.path.join(target, name)
        rel = normalize_relpath(os.path.join(subpath, name) if subpath else name)
        stat = os.stat(full)
        is_dir = os.path.isdir(full)
        ext = os.path.splitext(name)[1].lower()

        if not is_dir:
            if is_hidden_file(hidden_files, rel, stat):
                continue
            if rel in hidden_files:
                hidden_files.pop(rel, None)
                hidden_files_changed = True

        items.append({
            "name": name,
            "path": rel,
            "is_dir": is_dir,
            "size": human_size(stat.st_size) if not is_dir else "-",
            "size_bytes": stat.st_size,
            "mtime": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M"),
            "is_image": ext in IMAGE_EXTS,
            "is_pdf": ext in PDF_EXT,
        })

    if hidden_files_changed:
        save_hidden_files(hidden_files)

    # 上级目录
    parent = os.path.dirname(subpath.rstrip("/")) if subpath else None

    return render_template("index.html", items=items, subpath=subpath, parent=parent)


@app.route("/download/<path:subpath>")
@login_required
def download(subpath):
    subpath = normalize_relpath(subpath)
    target = safe_path(subpath)
    if not os.path.isfile(target):
        abort(404)
    if is_hidden_file(load_hidden_files(), subpath, os.stat(target)):
        abort(404)
    directory = os.path.dirname(target)
    filename = os.path.basename(target)
    return send_from_directory(directory, filename, as_attachment=True)


@app.route("/preview/<path:subpath>")
@login_required
def preview(subpath):
    subpath = normalize_relpath(subpath)
    target = safe_path(subpath)
    if not os.path.isfile(target):
        abort(404)
    if is_hidden_file(load_hidden_files(), subpath, os.stat(target)):
        abort(404)
    directory = os.path.dirname(target)
    filename = os.path.basename(target)
    return send_from_directory(directory, filename, as_attachment=False)


@app.route("/delete/<path:subpath>", methods=["POST"])
@login_required
def delete(subpath):
    subpath = normalize_relpath(subpath)
    target = safe_path(subpath)
    if not os.path.isfile(target):
        abort(404)

    hidden_files = load_hidden_files()
    hidden_files[subpath] = build_fingerprint(os.stat(target))
    save_hidden_files(hidden_files)

    parent = os.path.dirname(subpath)
    return redirect(url_for("index", subpath=parent))
