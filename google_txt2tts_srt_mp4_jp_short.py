# -*- coding: utf-8 -*-
"""
【YouTubeショート版】 txt → 文分割 → Google TTS(文ごと) → MP3結合 → SRT生成 → 縦型(720x1280)黒背景+字幕MP4

表示:
- 各工程の開始/完了/経過時間
- TTS進捗
- 最後に総処理時間を必ず表示

安全化:
- MP4音声は「結合した1本のmp3」を使用（1文目だけ問題の解消）
- SRTは正規フォーマット(00:00:00,000)
- subtitlesパス地雷回避：SRTを _tts_tmp/sub.srt にコピーして subtitles=filename= で渡す
- Windowsドライブ ":" を "\:" にエスケープ
"""

import os
import sys
import re
import shutil
import random
import subprocess
import chardet
import time
from typing import List, Tuple

from google.cloud import texttospeech
from mutagen.mp3 import MP3

# ================== 設定 ==================
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = r"D:\central-web-428404-n2-6a98d3a64225.json"

TMP_DIR = "_tts_tmp"

# ショート縦型
W = 720
H = 1280

# 字幕折り返し（ショート版は短め）
SRT_WRAP_CHARS = 13

# 長文をTTS安全側で分割
MAX_TTS_CHARS_PER_CHUNK = 160

# 文末に「間」を入れたい場合（不要なら全部 0.0 に）
PAUSE_SEC_DEFAULT = 0.0
PAUSE_SEC = {
    "。": 0.0,
    "！": 0.0,
    "？": 0.0,
    "…": 0.0,
    "、": 0.0,
}

# TTS音声（女性）
JAPANESE_FEMALE_VOICES = [
    "ja-JP-Standard-A",
    "ja-JP-Wavenet-A",
]

# 字幕見た目
# ※フォントは環境により変えてOK（Meiryo / MS Gothic など）
SUB_FONT = "Meiryo"
SUB_FONT_SIZE = 16
SUB_MARGIN_V = 100
SUB_ALIGNMENT = 2  # 下寄せ

# ================== 時間表示 ==================
def now() -> float:
    return time.perf_counter()

def fmt(sec: float) -> str:
    m, s = divmod(int(sec), 60)
    return f"{m:02}:{s:02}"

# ================== ユーティリティ ==================
def ensure_tmp() -> None:
    os.makedirs(TMP_DIR, exist_ok=True)

def detect_encoding(path: str) -> str:
    with open(path, "rb") as f:
        return chardet.detect(f.read()).get("encoding") or "utf-8"

def safe_run(cmd: List[str], quiet: bool = False) -> None:
    if quiet:
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print("❌ コマンド失敗:")
            print("   " + " ".join(cmd))
            print("---- stderr ----")
            print(r.stderr)
            raise RuntimeError("command failed")
        return
    subprocess.run(cmd, check=True)

def ffmpeg_escape_filter_path(path: str) -> str:
    # subtitles フィルタ用に Windows パスの ":" を "\:" にする
    p = os.path.abspath(path).replace("\\", "/")
    return p.replace(":", r"\:")

# ================== SRT ==================
def srt_time(t: float) -> str:
    ms = int((t % 1) * 1000)
    s = int(t)
    h = s // 3600
    m = (s // 60) % 60
    sec = s % 60
    return f"{h:02}:{m:02}:{sec:02},{ms:03}"

def wrap_text(text: str, max_length: int = SRT_WRAP_CHARS) -> str:
    # 省略なし：固定幅で改行（元ショート版の挙動）
    t = text.strip()
    return "\n".join([t[i:i + max_length] for i in range(0, len(t), max_length)]) if t else ""

# ================== テキスト処理 ==================
def split_text_by_sentence(text: str) -> List[str]:
    parts = re.split(r"(?<=[。！？])\s*", text)
    return [p.strip() for p in parts if p.strip()]

def split_long_sentence(s: str, max_chars: int = MAX_TTS_CHARS_PER_CHUNK) -> List[str]:
    if len(s) <= max_chars:
        return [s]
    out, buf = [], ""
    for ch in s:
        buf += ch
        if ch in "、。！？" and len(buf) >= int(max_chars * 0.6):
            out.append(buf.strip())
            buf = ""
        elif len(buf) >= max_chars:
            out.append(buf.strip())
            buf = ""
    if buf.strip():
        out.append(buf.strip())
    return out

def normalize_sentences(text: str) -> List[str]:
    base = split_text_by_sentence(text)
    out: List[str] = []
    for s in base:
        out.extend(split_long_sentence(s))
    return out

def infer_pause_seconds(sentence: str) -> float:
    if not sentence:
        return PAUSE_SEC_DEFAULT
    return PAUSE_SEC.get(sentence[-1], PAUSE_SEC_DEFAULT)

# ================== TTS ==================
def tts_each_sentence(sentences: List[str], base: str) -> Tuple[List[float], List[str]]:
    ensure_tmp()
    client = texttospeech.TextToSpeechClient()
    durations: List[float] = []
    mp3s: List[str] = []

    total = len(sentences)
    print(f"🔊 TTS開始（{total}文）")

    for i, s in enumerate(sentences, 1):
        print(f"   TTS [{i:03}/{total:03}]")
        voice_name = random.choice(JAPANESE_FEMALE_VOICES)

        resp = client.synthesize_speech(
            input=texttospeech.SynthesisInput(text=s),
            voice=texttospeech.VoiceSelectionParams(language_code="ja-JP", name=voice_name),
            audio_config=texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3),
        )

        path = os.path.join(TMP_DIR, f"{base}_{i:03}.mp3")
        with open(path, "wb") as f:
            f.write(resp.audio_content)

        audio = MP3(path)
        durations.append(float(audio.info.length))
        mp3s.append(path)

    return durations, mp3s

def concat_mp3(mp3_files: List[str], out_mp3: str) -> None:
    ensure_tmp()
    list_path = os.path.join(TMP_DIR, "mp3_list.txt")
    with open(list_path, "w", encoding="utf-8") as f:
        for p in mp3_files:
            f.write(f"file '{os.path.abspath(p)}'\n")

    # 再エンコード結合（-c copy は環境差で不安定になりがち）
    safe_run([
        "ffmpeg", "-y",
        "-f", "concat", "-safe", "0",
        "-i", list_path,
        "-c:a", "libmp3lame", "-q:a", "2",
        out_mp3
    ], quiet=True)

# ================== SRT生成 ==================
def generate_srt(sentences: List[str], durations: List[float], pauses: List[float], srt_out: str) -> float:
    t = 0.0
    with open(srt_out, "w", encoding="utf-8") as f:
        for i, (s, d, p) in enumerate(zip(sentences, durations, pauses), 1):
            f.write(f"{i}\n")
            f.write(f"{srt_time(t)} --> {srt_time(t + d)}\n")
            f.write(wrap_text(s) + "\n\n")
            t += d + p
    return t

# ================== MP4生成（縦型） ==================
def make_black_image_vertical(image_file: str = "black_vertical.jpg") -> None:
    if os.path.exists(image_file):
        return
    safe_run([
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", f"color=c=black:s={W}x{H}",
        "-frames:v", "1",
        image_file
    ], quiet=True)

def make_mp4_short(merged_mp3: str, srt_out: str, mp4_out: str, total_duration: float) -> None:
    ensure_tmp()
    make_black_image_vertical("black_vertical.jpg")

    # subtitles地雷回避：SRTを安全名でコピー
    safe_srt = os.path.join(TMP_DIR, "sub.srt")
    shutil.copyfile(srt_out, safe_srt)

    srt_ff = ffmpeg_escape_filter_path(safe_srt)

    # フォント名の空白は \ でエスケープする必要がある場合あり
    # 例: "MS Gothic" → "MS\ Gothic"
    font_for_style = SUB_FONT.replace(" ", "\\ ")

    vf = (
        "subtitles="
        f"filename='{srt_ff}'"
        ":charenc=UTF-8"
        f":force_style='FontName={font_for_style},FontSize={SUB_FONT_SIZE},"
        f"Alignment={SUB_ALIGNMENT},MarginV={SUB_MARGIN_V}'"
    )

    safe_run([
        "ffmpeg", "-y",
        "-loop", "1", "-i", "black_vertical.jpg",
        "-i", merged_mp3,
        "-vf", vf,
        "-c:v", "libx264", "-tune", "stillimage",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-shortest",
        "-t", f"{total_duration:.3f}",
        mp4_out
    ], quiet=False)

# ================== メイン ==================
def main():
    t_start = now()
    print("=== ショート動画 生成開始 ===")

    if len(sys.argv) < 2:
        sys.exit("usage: script.py input.txt")

    input_file = sys.argv[1]
    base = os.path.splitext(os.path.basename(input_file))[0]

    mp3_out = base + ".mp3"
    srt_out = base + ".srt"
    mp4_out = base + ".mp4"  # ここは必要なら base + "-short.mp4" にしてOK

    try:
        # ---------- 読み込み ----------
        t0 = now()
        enc = detect_encoding(input_file)
        with open(input_file, encoding=enc, errors="replace") as f:
            text = f.read()
        print(f"📥 入力読込完了 ({fmt(now()-t0)})")

        # ---------- 文分割 ----------
        t0 = now()
        sentences = normalize_sentences(text)
        if not sentences:
            raise RuntimeError("empty text")
        print(f"✂ 文分割完了: {len(sentences)}文 ({fmt(now()-t0)})")

        # ---------- TTS ----------
        t0 = now()
        durations, mp3_files = tts_each_sentence(sentences, base)
        print(f"🔊 TTS完了 ({fmt(now()-t0)})")

        # ---------- MP3結合 ----------
        t0 = now()
        print("🎵 MP3結合開始")
        concat_mp3(mp3_files, mp3_out)
        print(f"🎵 MP3結合完了: {mp3_out} ({fmt(now()-t0)})")

        # ---------- SRT ----------
        t0 = now()
        pauses = [infer_pause_seconds(s) for s in sentences]
        total_duration = generate_srt(sentences, durations, pauses, srt_out)
        print(f"📝 SRT生成完了: {srt_out} ({fmt(now()-t0)})")

        # ---------- MP4（縦型） ----------
        t0 = now()
        print("🎬 ショートMP4生成開始（縦型 720x1280）")
        make_mp4_short(mp3_out, srt_out, mp4_out, total_duration)
        print(f"🎬 ショートMP4生成完了: {mp4_out} ({fmt(now()-t0)})")

        print("=== 正常終了 ===")

    finally:
        if os.path.exists(TMP_DIR):
            shutil.rmtree(TMP_DIR, ignore_errors=True)
        total = now() - t_start
        print(f"⏱ 総処理時間: {fmt(total)} ({total:.2f} 秒)")

if __name__ == "__main__":
    main()
