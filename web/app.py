"""
扫描文件 Web 管理器
通过浏览器在线查看、预览、下载打印机扫描的文件
"""

import os
import hashlib
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
    target = safe_path(subpath)

    if not os.path.exists(target):
        abort(404)

    if os.path.isfile(target):
        directory = os.path.dirname(subpath)
        filename = os.path.basename(subpath)
        return redirect(url_for("download", subpath=subpath))

    # 列出目录内容
    items = []
    for name in sorted(os.listdir(target)):
        full = os.path.join(target, name)
        rel = os.path.join(subpath, name) if subpath else name
        stat = os.stat(full)
        is_dir = os.path.isdir(full)
        ext = os.path.splitext(name)[1].lower()
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

    # 上级目录
    parent = os.path.dirname(subpath.rstrip("/")) if subpath else None

    return render_template("index.html", items=items, subpath=subpath, parent=parent)


@app.route("/download/<path:subpath>")
@login_required
def download(subpath):
    target = safe_path(subpath)
    if not os.path.isfile(target):
        abort(404)
    directory = os.path.dirname(target)
    filename = os.path.basename(target)
    return send_from_directory(directory, filename, as_attachment=True)


@app.route("/preview/<path:subpath>")
@login_required
def preview(subpath):
    target = safe_path(subpath)
    if not os.path.isfile(target):
        abort(404)
    directory = os.path.dirname(target)
    filename = os.path.basename(target)
    return send_from_directory(directory, filename, as_attachment=False)


@app.route("/delete/<path:subpath>", methods=["POST"])
@login_required
def delete(subpath):
    target = safe_path(subpath)
    if not os.path.isfile(target):
        abort(404)
    os.remove(target)
    parent = os.path.dirname(subpath)
    return redirect(url_for("index", subpath=parent))
