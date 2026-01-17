# -*- coding: utf-8 -*-
"""
YouTube uploader (single file) - 完全版
（最終・途中経過/説明文表示対応 + modeスイッチ + mp4指定 + today再帰検索(y/N)）

要件反映：
- mp4 と 90%以上一致する txt を同一ディレクトリから探索してメタデータに使う（正規化あり）
- txt のタイトル行ルール：
    * 1行目が空行（空白のみ含む）なら 2行目をタイトル
    * タイトル文字列から全角【】を除去
    * タイトルに使った行以外を description にする
- 見つからなければ「複数fallback」で拾う（同名 / 正規化名 / _bgm / ._bgm など）
- ★説明文も表示（全文）
- ★途中経過も報告（進捗% + 経過時間）
- resumable upload + 一時エラー時リトライ
- done 移動（衝突時 (1)(2)...）
- ★オプション付けなくても実行できる（credentials_file は環境変数 or 既定パス）
- ★mp4 指定：
    * --mp4 <path> が最優先
    * 次に位置引数
    * どちらも無ければカレントの最新 mp4 を自動選択
- ★類似判定で使った txt が同名でなくても、その txt 自体も done に移動（ただし同一フォルダ内のみ）
- ★txt探索のデバッグ表示（上位候補を表示）
- ★--mode スイッチで joyuu/kankyou/yakuza/kashu/none を切り替え（prefix/tags/category まとめて切替）
- ★--dry_run でアップロードせず確認のみ
- ★--loose_txt で類似判定を緩める（例: 0.90 → 0.80）
- ★today 再帰検索：
    * 同フォルダ類似検索→fallback の後、today_root を再帰検索して候補提示
    * --confirm_today で候補を y/N で採用確認
    * --today_recursive はデフォルトON（無効化は --no_today_recursive）
"""

import os
import re
import time
import shutil
import argparse
from datetime import timedelta
from typing import Tuple, List, Optional

import chardet
from difflib import SequenceMatcher

from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow


# =========================
# 既定値（必要ならここだけ編集）
# =========================
DEFAULT_CREDENTIALS_FILE = os.environ.get(
    "YT_CREDENTIALS_FILE",
    r"D:\client_secret_487095582016-s9mbp3bkvft6cidq2nn6nted181p7pef.apps.googleusercontent.com.json"
)
DEFAULT_TOKEN_FILE = os.environ.get("YT_TOKEN_FILE", "token.json")

# 「mode=none」のときの標準（環境変数があればそれを優先）
DEFAULT_PREFIX = os.environ.get("YT_TITLE_PREFIX", "【歌手】")
DEFAULT_TAGS = os.environ.get("YT_TAGS", "自動アップロード,YouTube API")

DEFAULT_PRIVACY = os.environ.get("YT_PRIVACY_STATUS", "public")  # public/unlisted/private
DEFAULT_CATEGORY = os.environ.get("YT_CATEGORY_ID", "22")
DEFAULT_PORT = int(os.environ.get("YT_OAUTH_PORT", "8080"))
DEFAULT_TXT_SIMILARITY = float(os.environ.get("YT_TXT_SIMILARITY", "0.90"))
DEFAULT_DONE_DIR = os.environ.get("YT_DONE_DIR", "done")

DEFAULT_TODAY_ROOT = os.environ.get(
    "YT_TODAY_ROOT",
    r"C:\Users\user\OneDrive\＊【エコビズ】\today"
)

# =========================
# mode プリセット
#  - ここを増やすだけでスイッチ追加できる
# =========================
MODE_PRESETS = {
    "joyuu": {
        "prefix": "【女優】",
        "tags": ["女優", "昭和", "映画", "日本文化"],
        "category_id": "22",
    },
    "kashu": {
        "prefix": "【歌手】",
        "tags": ["歌手", "音楽", "昭和歌謡"],
        "category_id": "10",  # Music
    },
    "kankyou": {
        "prefix": "【環境】",
        "tags": ["環境問題", "社会", "記録", "日本"],
        "category_id": "25",  # News & Politics
    },
    "yakuza": {
        "prefix": "【任侠】【渡世】",
        "tags": ["裏社会", "昭和史", "ノンフィクション"],
        "category_id": "22",
    },
    "none": {
        # none は DEFAULT_* を使う（ここは参照しない）
        "prefix": "",
        "tags": [],
        "category_id": DEFAULT_CATEGORY,
    },
}

# =========================
# 設定
# =========================
SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]
RETRIABLE_STATUS = {500, 502, 503, 504}


# =========================
# Utility
# =========================
def fmt_elapsed(sec: float) -> str:
    return str(timedelta(seconds=int(sec)))


def safe_title(s: str) -> str:
    return re.sub(r"[\x00-\x1f\x7f]", "", s).strip()


def unique_path(dst_path: str) -> str:
    if not os.path.exists(dst_path):
        return dst_path
    base, ext = os.path.splitext(dst_path)
    i = 1
    while True:
        cand = f"{base}({i}){ext}"
        if not os.path.exists(cand):
            return cand
        i += 1


def pick_latest_mp4(dir_path: str) -> Optional[str]:
    try:
        cands = []
        for name in os.listdir(dir_path):
            if name.lower().endswith(".mp4"):
                full = os.path.join(dir_path, name)
                if os.path.isfile(full):
                    cands.append(full)
        if not cands:
            return None
        cands.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        return cands[0]
    except Exception:
        return None


def normalize_stem(stem: str) -> str:
    """
    mp4/txt のベース名比較用の正規化（誤爆しにくい版）
    - 先頭の長い数字（例: 20260106114609-）を除去（タイムスタンプ対策）
    - 末尾のドット地雷除去
    - よく付く末尾サフィックス（bgm/wide/short 等）を“繰り返し”剥がす
    """
    s = stem.strip()

    # 先頭の長い数字（タイムスタンプ等）を除去
    s = re.sub(r"^\d{8,14}[-_ ]*", "", s)

    # 末尾ドット連発除去
    s = re.sub(r"\.+$", "", s)

    # サフィックス剥がし（連結してることがあるので繰り返す）
    while True:
        before = s
        s = re.sub(r"([._-])?(bgm|wide|short|tts|sub|final)$", "", s, flags=re.IGNORECASE)
        s = re.sub(r"\.+$", "", s)
        if s == before:
            break

    return s.strip()


def similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio()


def read_text_lines_best_effort(txt_file: str) -> Optional[List[str]]:
    if not txt_file or not os.path.exists(txt_file):
        return None

    with open(txt_file, "rb") as f:
        raw = f.read()

    enc_guess = None
    try:
        enc_guess = chardet.detect(raw).get("encoding")
    except Exception:
        pass

    candidates = []
    if enc_guess:
        candidates.append(enc_guess)
    candidates += ["utf-8-sig", "utf-8", "cp932", "shift_jis", "euc_jp"]

    tried = set()
    for enc in candidates:
        if not enc or enc.lower() in tried:
            continue
        tried.add(enc.lower())
        try:
            return raw.decode(enc, errors="strict").splitlines(True)
        except Exception:
            pass

    return None


def get_metadata_from_textfile(txt_file: str, fallback_title: str) -> Tuple[str, str]:
    """
    - 1行目が空行なら 2行目をタイトル
    - タイトルから全角【】を除去
    - タイトル行以外を description にする
    """
    lines = read_text_lines_best_effort(txt_file)
    if lines is None:
        return fallback_title, ""

    stripped = [l.rstrip("\r\n") for l in lines]

    title = fallback_title
    title_index = None

    if len(stripped) >= 1 and stripped[0].strip():
        title = stripped[0].strip()
        title_index = 0
    elif len(stripped) >= 2 and stripped[1].strip():
        title = stripped[1].strip()
        title_index = 1
    else:
        return fallback_title, ""

    title = title.replace("【", "").replace("】", "").strip()

    desc_lines = [line for i, line in enumerate(stripped) if i != title_index]
    description = "\n".join(desc_lines).strip()

    return title, description


def debug_top_txt_candidates(dir_path: str, mp4_stem_norm: str, limit: int = 5):
    try:
        names = [n for n in os.listdir(dir_path) if n.lower().endswith(".txt")]
    except Exception:
        return

    scores = []
    for name in names:
        txt_stem_norm = normalize_stem(os.path.splitext(name)[0])
        r = similarity(mp4_stem_norm, txt_stem_norm)
        scores.append((r, name, txt_stem_norm))

    scores.sort(reverse=True, key=lambda x: x[0])
    print(f"txt候補 上位{min(limit, len(scores))}件（mp4_norm='{mp4_stem_norm}'）:")
    for r, name, norm in scores[:limit]:
        print(f"  {r:.3f}  {name}  (norm='{norm}')")


def find_similar_txt(mp4_path: str, threshold: float = 0.80, debug: bool = True) -> Optional[str]:
    dir_path = os.path.dirname(os.path.abspath(mp4_path))
    mp4_stem_raw = os.path.splitext(os.path.basename(mp4_path))[0]
    mp4_stem_norm = normalize_stem(mp4_stem_raw)

    best_match = None
    best_ratio = 0.0

    try:
        names = os.listdir(dir_path)
    except Exception:
        return None

    for name in names:
        if not name.lower().endswith(".txt"):
            continue
        txt_stem_raw = os.path.splitext(name)[0]
        txt_stem_norm = normalize_stem(txt_stem_raw)
        r = similarity(mp4_stem_norm, txt_stem_norm)
        if r >= threshold and r > best_ratio:
            best_ratio = r
            best_match = os.path.join(dir_path, name)

    if best_match:
        print(f"類似txt検出: {os.path.basename(best_match)}（一致率 {best_ratio:.2f} / threshold {threshold:.2f}）")
        return best_match

    if debug:
        print(f"類似txt未検出: mp4='{mp4_stem_raw}' -> norm='{mp4_stem_norm}', threshold={threshold:.2f}")
        debug_top_txt_candidates(dir_path, mp4_stem_norm, limit=5)

    return None


def build_fallback_txt_candidates(mp4_path: str) -> List[str]:
    dir_path = os.path.dirname(os.path.abspath(mp4_path))
    base_noext = os.path.splitext(mp4_path)[0]
    stem_raw = os.path.splitext(os.path.basename(mp4_path))[0]
    stem_norm = normalize_stem(stem_raw)

    # ありがちな派生（"" は重複を増やすので入れない）
    suffixes = ["_bgm", "._bgm", ".bgm", "_wide", "._wide", "_short", "._short", "_tts", "._tts"]

    cands = []

    # 1) 完全同名（フルパス）
    cands.append(base_noext + ".txt")

    # 2) 正規化名（素）
    cands.append(os.path.join(dir_path, stem_norm + ".txt"))

    # 3) 正規化名 + サフィックス違い（bgm 等）
    for s in suffixes:
        cands.append(os.path.join(dir_path, stem_norm + s + ".txt"))

    # 4) 元のstem_rawから末尾ドットだけ落としたもの
    stem_trimdot = re.sub(r"\.+$", "", stem_raw)
    cands.append(os.path.join(dir_path, stem_trimdot + ".txt"))

    # 5) 元のstem_rawそのまま
    cands.append(os.path.join(dir_path, stem_raw + ".txt"))

    # 重複排除（順序維持）
    seen = set()
    out = []
    for p in cands:
        ap = os.path.abspath(p)
        if ap not in seen:
            seen.add(ap)
            out.append(p)
    return out


# =========================
# today 再帰検索（txt）
# =========================
def iter_txt_files_recursive(root_dir: str) -> List[str]:
    out: List[str] = []
    if not root_dir or not os.path.isdir(root_dir):
        return out
    for cur, _dirs, files in os.walk(root_dir):
        for fn in files:
            if fn.lower().endswith(".txt"):
                out.append(os.path.join(cur, fn))
    return out


def find_similar_txt_in_root_recursive(
    mp4_path: str,
    root_dir: str,
    threshold: float,
    limit: int = 10,
) -> List[Tuple[float, str, str]]:
    mp4_stem_raw = os.path.splitext(os.path.basename(mp4_path))[0]
    mp4_stem_norm = normalize_stem(mp4_stem_raw)

    cands: List[Tuple[float, str, str]] = []
    for txt_path in iter_txt_files_recursive(root_dir):
        stem = os.path.splitext(os.path.basename(txt_path))[0]
        stem_norm = normalize_stem(stem)
        r = similarity(mp4_stem_norm, stem_norm)
        if r >= threshold:
            cands.append((r, txt_path, stem_norm))

    cands.sort(key=lambda x: x[0], reverse=True)
    return cands[:limit]


def ask_yes_no(prompt: str, default_no: bool = True) -> bool:
    # default_no=True のとき Enter は N 扱い
    suffix = " [y/N]: " if default_no else " [Y/n]: "
    s = input(prompt + suffix).strip().lower()
    if not s:
        return (not default_no)
    return s in ("y", "yes")


# =========================
# Auth
# =========================
def authenticate(token_file: str, credentials_file: str, port: int) -> Optional[Credentials]:
    if not credentials_file or not os.path.exists(credentials_file):
        print("エラー: credentials_file が見つかりません。")
        print(f"  現在の設定: {credentials_file}")
        print("  対策: 環境変数 YT_CREDENTIALS_FILE を設定するか、--credentials_file を指定してください。")
        return None

    creds = None
    if os.path.exists(token_file):
        try:
            creds = Credentials.from_authorized_user_file(token_file, SCOPES)
        except Exception:
            creds = None

    if not creds or not creds.valid:
        try:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(credentials_file, SCOPES)
                creds = flow.run_local_server(
                    port=port,
                    access_type="offline",
                    prompt="consent",
                )

            with open(token_file, "w", encoding="utf-8") as f:
                f.write(creds.to_json())
        except Exception as e:
            print(f"認証エラー: {e}")
            return None

    return creds


# =========================
# Upload
# =========================
def upload_video(
    file_path: str,
    title: str,
    description: str,
    category_id: str,
    privacy_status: str,
    tags: List[str],
    token_file: str,
    credentials_file: str,
    port: int,
    show_progress: bool,
    max_retries: int = 8,
) -> Optional[str]:
    creds = authenticate(token_file, credentials_file, port)
    if not creds:
        return None

    youtube = build("youtube", "v3", credentials=creds)

    request_body = {
        "snippet": {
            "title": safe_title(title),
            "description": description or "",
            "tags": tags,
            "categoryId": category_id,
        },
        "status": {"privacyStatus": privacy_status},
    }

    media = MediaFileUpload(file_path, resumable=True, mimetype="video/*")
    request = youtube.videos().insert(part="snippet,status", body=request_body, media_body=media)

    response = None
    retry = 0

    start_time = time.time()
    last_percent = -1

    print("アップロード開始（途中経過を表示します）")

    while response is None:
        try:
            status, response = request.next_chunk()
            if status and show_progress:
                percent = int(status.progress() * 100)
                if percent != last_percent:
                    elapsed = time.time() - start_time
                    print(f"  進捗: {percent:3d}%  経過時間: {fmt_elapsed(elapsed)}")
                    last_percent = percent

        except HttpError as e:
            code = getattr(e.resp, "status", None)
            if code in RETRIABLE_STATUS and retry < max_retries:
                wait = (2 ** retry) + (0.2 * retry)
                elapsed = time.time() - start_time
                print(f"  一時エラー(Http {code})。{wait:.1f}s 待機（経過 {fmt_elapsed(elapsed)}）")
                time.sleep(wait)
                retry += 1
                continue
            print(f"エラー: アップロード中に問題: {e}")
            return None

        except Exception as e:
            if retry < max_retries:
                wait = (2 ** retry) + (0.2 * retry)
                elapsed = time.time() - start_time
                print(f"  一時エラー({e})。{wait:.1f}s 待機（経過 {fmt_elapsed(elapsed)}）")
                time.sleep(wait)
                retry += 1
                continue
            print(f"エラー: アップロード中に問題: {e}")
            return None

    total = time.time() - start_time
    print(f"アップロード完了（総時間 {fmt_elapsed(total)}）")

    return response.get("id")


# =========================
# Move to done
# =========================
def move_to_done(paths: List[str], done_dir: str):
    existing = [p for p in paths if p and os.path.exists(p)]
    if not existing:
        return

    base_dir = os.path.dirname(os.path.abspath(existing[0]))
    done = os.path.join(base_dir, done_dir)
    os.makedirs(done, exist_ok=True)

    for p in existing:
        dst = unique_path(os.path.join(done, os.path.basename(p)))
        shutil.move(p, dst)


def move_related_to_done(mp4_path: str, used_txt: Optional[str], done_dir: str):
    base, _ = os.path.splitext(mp4_path)
    related = [mp4_path, base + ".txt", base + ".srt", base + ".mp3"]

    mp4_dir = os.path.dirname(os.path.abspath(mp4_path))

    # 類似で使った txt が同名でない場合も移動（ただし mp4 と同じフォルダ内のみ）
    if used_txt:
        used_txt_abs = os.path.abspath(used_txt)
        base_txt_abs = os.path.abspath(base + ".txt")

        if used_txt_abs != base_txt_abs:
            used_txt_dir = os.path.dirname(used_txt_abs)
            if used_txt_dir == mp4_dir:
                related.append(used_txt_abs)
            else:
                print(f"注意: used_txt が別フォルダのため移動しません: {used_txt_abs}")

    move_to_done(related, done_dir)


# =========================
# Main flow
# =========================
def resolve_mp4_path(mp4_arg: Optional[str], positional_path: Optional[str]) -> Optional[str]:
    """
    mp4 指定の優先順位:
      1) --mp4
      2) 位置引数
      3) カレントの最新 mp4
    """
    if mp4_arg:
        return mp4_arg
    if positional_path:
        return positional_path
    latest = pick_latest_mp4(os.getcwd())
    return latest


def upload_single_video(
    file_path: Optional[str],
    category_id: str,
    privacy_status: str,
    prefix: str,
    tags: List[str],
    token_file: str,
    credentials_file: str,
    port: int,
    done_dir: str,
    no_move: bool,
    show_progress: bool,
    txt_similarity: float,
    dry_run: bool,
    today_root: Optional[str],
    today_recursive: bool,
    confirm_today: bool,
):
    if not file_path:
        print("エラー: mp4 が指定されていません。かつ、カレントディレクトリに mp4 が見つかりません。")
        return

    file_path = os.path.abspath(file_path)
    if not os.path.isfile(file_path):
        print(f"エラー: 指定された mp4 が無効です: {file_path}")
        return

    fallback_title = os.path.splitext(os.path.basename(file_path))[0]

    # ① 同フォルダ：類似txt検索
    used_txt = find_similar_txt(file_path, txt_similarity, debug=True)

    # ② 同フォルダ：fallback候補を試す
    if not used_txt:
        for cand in build_fallback_txt_candidates(file_path):
            if os.path.exists(cand):
                used_txt = cand
                print(f"fallback候補でtxt検出: {os.path.basename(used_txt)}")
                break

    # ③ today 再帰検索（デフォルトON）
    if (not used_txt) and today_recursive and today_root:
        print(f"today再帰検索: {today_root}")
        hits = find_similar_txt_in_root_recursive(
            mp4_path=file_path,
            root_dir=today_root,
            threshold=txt_similarity,
            limit=10,
        )
        if hits:
            print(f"today候補（上位{len(hits)}件）:")
            for r, path, norm in hits:
                print(f"  {r:.3f}  {path}  (norm='{norm}')")

            if confirm_today:
                for r, path, _norm in hits:
                    if ask_yes_no(f"このtxtを採用しますか？ {os.path.basename(path)}  一致率={r:.3f}"):
                        used_txt = path
                        print(f"採用: {used_txt}")
                        break
            else:
                used_txt = hits[0][1]
                print(f"today最上位を採用: {used_txt}")
        else:
            print("todayでも類似txtは見つかりませんでした。")

    # txt からメタデータ確定
    if used_txt:
        title, desc = get_metadata_from_textfile(used_txt, fallback_title)
    else:
        title, desc = fallback_title, ""

    if prefix:
        title = f"{prefix}{title}"

    print(f"アップロード開始: {file_path}")
    print(f"  使用txt: {used_txt if used_txt else 'なし（fallback）'}")
    print(f"  タイトル: {title}")
    print(f"  category_id: {category_id}")
    print(f"  tags: {', '.join(tags) if tags else '（なし）'}")

    if desc:
        print("  説明文（全文）:")
        print("  --------------------")
        for line in desc.splitlines():
            print(f"  {line}")
        print("  --------------------")
    else:
        print("  説明文: （空）")

    # dry_run
    if dry_run:
        print("dry_run 指定のため、アップロードは行いません。")
        return

    vid = upload_video(
        file_path=file_path,
        title=title,
        description=desc,
        category_id=category_id,
        privacy_status=privacy_status,
        tags=tags,
        token_file=token_file,
        credentials_file=credentials_file,
        port=port,
        show_progress=show_progress,
    )

    if vid:
        print(f"アップロード完了: videoId={vid}")
        print(f"URL: https://www.youtube.com/watch?v={vid}")
        if not no_move:
            move_related_to_done(file_path, used_txt, done_dir)
            print(f"ファイル移動完了: ./{done_dir}/")
    else:
        print("アップロード失敗（ファイルは移動しません）")


def parse_tags_csv(s: Optional[str]) -> List[str]:
    if not s:
        return []
    return [t.strip() for t in s.split(",") if t.strip()]


def resolve_effective_settings(args) -> Tuple[str, str, List[str], float]:
    """
    mode + CLI + DEFAULT を合成して最終値を作る（CLIが最優先）
    返り値: (prefix, category_id, tags, txt_similarity)
    """
    mode = args.mode or "none"

    # ベース（mode）
    if mode != "none":
        conf = MODE_PRESETS.get(mode, MODE_PRESETS["kashu"])
        base_prefix = conf["prefix"]
        base_category = conf["category_id"]
        base_tags = conf["tags"][:]
    else:
        base_prefix = DEFAULT_PREFIX
        base_category = DEFAULT_CATEGORY
        base_tags = parse_tags_csv(DEFAULT_TAGS)

    # CLI があれば上書き（明示指定のみ）
    prefix = base_prefix if args.prefix is None else args.prefix
    category_id = base_category if args.category_id is None else args.category_id

    # tags は --tags 指定があれば完全上書き、なければ mode/default を使用
    if args.tags is None:
        tags = base_tags
    else:
        tags = parse_tags_csv(args.tags)

    # txt similarity（--loose_txt があれば下げる）
    txt_similarity = DEFAULT_TXT_SIMILARITY if args.txt_similarity is None else float(args.txt_similarity)
    if args.loose_txt:
        txt_similarity = min(txt_similarity, 0.80)

    return prefix, category_id, tags, txt_similarity


# =========================
# CLI
# =========================
if __name__ == "__main__":
    p = argparse.ArgumentParser(
        description="YouTube uploader（単発：類似txt/空行/【】除去/説明文表示/進捗表示/mode切替/mp4指定/today再帰(y/N)）"
    )

    # mp4（明示指定）
    p.add_argument("--mp4", default=None, help="アップロードする mp4 のパス（位置引数より優先）")

    # mp4（位置引数：残して互換維持）
    p.add_argument("path", nargs="?", default=None, help="mp4 のパス（省略可。未指定なら最新mp4）")

    # mode
    p.add_argument(
        "--mode",
        default="none",
        choices=list(MODE_PRESETS.keys()),
        help="種別スイッチ（joyuu / kashu / kankyou / yakuza / none）"
    )

    # 以降は全部「明示指定があれば上書き」したいので default=None
    p.add_argument("--category_id", default=None, help="YouTube categoryId（未指定なら mode/DEFAULT から決定）")
    p.add_argument("--privacy_status", default=DEFAULT_PRIVACY, choices=["public", "unlisted", "private"])
    p.add_argument("--prefix", default=None, help="タイトル接頭辞（未指定なら mode/DEFAULT から決定）")
    p.add_argument("--tags", default=None, help="タグCSV（未指定なら mode/DEFAULT から決定）")

    p.add_argument("--token_file", default=DEFAULT_TOKEN_FILE)
    p.add_argument("--credentials_file", default=DEFAULT_CREDENTIALS_FILE)
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--done_dir", default=DEFAULT_DONE_DIR)

    p.add_argument("--no_move", action="store_true")
    p.add_argument("--no_progress", action="store_true")

    p.add_argument("--txt_similarity", type=float, default=None, help="類似txtのしきい値（例: 0.90）")
    p.add_argument("--loose_txt", action="store_true", help="類似判定を緩める（最小 0.80 まで）")
    p.add_argument("--dry_run", action="store_true", help="アップロードせず、採用txt/タイトル/説明文だけ表示")

    # today 再帰検索（デフォルトON）
    p.add_argument("--today_root", default=DEFAULT_TODAY_ROOT, help="today ルート（再帰検索用）")
    p.add_argument(
        "--today_recursive",
        dest="today_recursive",
        action="store_true",
        default=True,
        help="today を再帰検索して txt 候補を探す（既定で ON）"
    )
    p.add_argument(
        "--no_today_recursive",
        dest="today_recursive",
        action="store_false",
        help="today 再帰検索を無効化する"
    )
    p.add_argument("--confirm_today", action="store_true", help="today 候補の採用を y/N で確認する")

    args = p.parse_args()

    prefix, category_id, tags, txt_similarity = resolve_effective_settings(args)

    mp4_path = resolve_mp4_path(args.mp4, args.path)
    if mp4_path and not (args.mp4 or args.path):
        print(f"mp4未指定 → 最新mp4を自動選択: {mp4_path}")

    upload_single_video(
        file_path=mp4_path,
        category_id=category_id,
        privacy_status=args.privacy_status,
        prefix=prefix,
        tags=tags,
        token_file=args.token_file,
        credentials_file=args.credentials_file,
        port=args.port,
        done_dir=args.done_dir,
        no_move=args.no_move,
        show_progress=not args.no_progress,
        txt_similarity=txt_similarity,
        dry_run=args.dry_run,
        today_root=args.today_root,
        today_recursive=args.today_recursive,
        confirm_today=args.confirm_today,
    )
