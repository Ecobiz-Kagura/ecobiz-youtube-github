# -*- coding: utf-8 -*-
"""
txt → 文分割 → Google TTS(文ごと) → (文間ポーズ無音を挿入して) MP3結合 → SRT生成(正規) → 黒背景+字幕MP4

表示:
- 各工程の開始/完了/経過時間
- TTS・音声処理の進捗表示
- 最後に総処理時間を必ず表示

重要:
- MP4の音声は「結合した1本のmp3」を使用（1文目だけ問題を解消）
- SRT時刻は 00:00:00,000 形式で正しく生成（60秒超でも壊れない）
- subtitlesのパス地雷回避：SRTを _tts_tmp/sub.srt にコピーして渡す
- ★字幕ズレ防止：SRTに入れたポーズ秒と同じ無音をMP3側にも挿入して同期
- ★ffmpegの -loop 問題回避：lavfi color を使い -loop を使わない
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

SRT_WRAP_CHARS = 25
MAX_TTS_CHARS_PER_CHUNK = 160

PAUSE_SEC_DEFAULT = 0.10
PAUSE_SEC = {
    "。": 0.25,
    "！": 0.20,
    "？": 0.20,
    "…": 0.18,
    "、": 0.12,
}

JAPANESE_FEMALE_VOICES = [
    "ja-JP-Standard-A",
    "ja-JP-Wavenet-A",
]

# ================== 時間表示 ==================
def now() -> float:
    return time.perf_counter()

def fmt(sec: float) -> str:
    m, s = divmod(int(sec), 60)
    return f"{m:02}:{s:02}"

# ================== ユーティリティ ==================
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
    # subtitlesフィルタ用: Windowsの D:\ の ":" を "\:" にする
    p = os.path.abspath(path).replace("\\", "/")
    return p.replace(":", r"\:")

def ensure_tmp():
    os.makedirs(TMP_DIR, exist_ok=True)

# ================== SRT関連 ==================
def srt_time(t: float) -> str:
    # 浮動小数誤差に強い：総msに丸めてから分解
    total_ms = int(round(t * 1000.0))
    ms = total_ms % 1000
    total_s = total_ms // 1000
    h = total_s // 3600
    m = (total_s // 60) % 60
    sec = total_s % 60
    return f"{h:02}:{m:02}:{sec:02},{ms:03}"

def wrap_text(text: str, max_length: int = SRT_WRAP_CHARS) -> str:
    lines = []
    t = text.strip()
    while len(t) > max_length:
        idx = max(t.rfind("、", 0, max_length), t.rfind("。", 0, max_length))
        if idx == -1:
            idx = max_length
        lines.append(t[:idx+1].strip())
        t = t[idx+1:].strip()
    lines.append(t)
    return "\n".join([x for x in lines if x])

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

# ================== 無音生成（ポーズ同期用） ==================
def make_silence_mp3(duration_sec: float, out_path: str) -> None:
    ensure_tmp()
    d = max(0.01, float(duration_sec))
    safe_run([
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
        "-t", f"{d:.3f}",
        "-c:a", "libmp3lame", "-q:a", "4",
        out_path
    ], quiet=True)

# ================== MP3結合 ==================
def concat_mp3(mp3_files: List[str], out_mp3: str) -> None:
    """
    mp3を結合して1本にする（MP4に使う）
    """
    ensure_tmp()
    list_path = os.path.join(TMP_DIR, "mp3_list.txt")
    with open(list_path, "w", encoding="utf-8") as f:
        for p in mp3_files:
            f.write(f"file '{os.path.abspath(p)}'\n")

    # 再エンコード結合（環境差で -c copy が不安定なことがあるため）
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

# ================== MP4生成 ==================
def make_mp4(merged_mp3: str, srt_out: str, mp4_out: str) -> None:
    ensure_tmp()

    # subtitles地雷回避：SRTを安全名でコピー
    safe_srt = os.path.join(TMP_DIR, "sub.srt")
    shutil.copyfile(srt_out, safe_srt)

    srt_ff = ffmpeg_escape_filter_path(safe_srt)
    vf = (
        f"subtitles=filename='{srt_ff}':charenc=UTF-8:"
        "force_style='FontName=MS\\ Gothic,FontSize=18,Alignment=2,MarginV=80'"
    )

    # ★-loop は使わない（あなたのffmpegで Option loop not found 対策）
    safe_run([
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "color=c=black:s=1920x1080:r=30",
        "-i", merged_mp3,
        "-vf", vf,
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-shortest",
        mp4_out
    ], quiet=False)

# ================== メイン ==================
def main():
    t_start = now()
    print("=== 処理開始 ===")

    if len(sys.argv) < 2:
        sys.exit("usage: script.py input.txt")

    input_file = sys.argv[1]
    base = os.path.splitext(os.path.basename(input_file))[0]

    mp3_out = base + ".mp3"
    srt_out = base + ".srt"
    mp4_out = base + ".mp4"

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

        # ---------- ポーズ（SRTと音声で一致させる） ----------
        pauses = [infer_pause_seconds(s) for s in sentences]

        # ---------- 無音挿入（字幕ズレ防止） ----------
        t0 = now()
        print("🤫 無音(ポーズ)生成開始")
        mp3_with_silence: List[str] = []
        total = len(mp3_files)

        for i, (mp3p, p) in enumerate(zip(mp3_files, pauses), 1):
            print(f"   無音準備 [{i:03}/{total:03}]")
            mp3_with_silence.append(mp3p)
            if p > 0:
                sil = os.path.join(TMP_DIR, f"{base}_sil_{i:03}.mp3")
                make_silence_mp3(p, sil)
                mp3_with_silence.append(sil)

        print(f"🤫 無音(ポーズ)生成完了 ({fmt(now()-t0)})")

        # ---------- MP3結合 ----------
        t0 = now()
        print("🎵 MP3結合開始（ポーズ込み）")
        concat_mp3(mp3_with_silence, mp3_out)
        print(f"🎵 MP3結合完了: {mp3_out} ({fmt(now()-t0)})")

        # ---------- SRT ----------
        t0 = now()
        total_duration = generate_srt(sentences, durations, pauses, srt_out)
        print(f"📝 SRT生成完了: {srt_out} ({fmt(now()-t0)})")
        print(f"🕒 想定総尺（SRT/音声）: {total_duration:.3f} 秒")

        # ---------- MP4 ----------
        t0 = now()
        print("🎬 MP4生成開始")
        make_mp4(mp3_out, srt_out, mp4_out)
        print(f"🎬 MP4生成完了: {mp4_out} ({fmt(now()-t0)})")

        print("=== 正常終了 ===")

    finally:
        # tmp掃除（欲しければコメントアウト）
        if os.path.exists(TMP_DIR):
            shutil.rmtree(TMP_DIR, ignore_errors=True)
        total = now() - t_start
        print(f"⏱ 総処理時間: {fmt(total)} ({total:.2f} 秒)")

if __name__ == "__main__":
    main()
