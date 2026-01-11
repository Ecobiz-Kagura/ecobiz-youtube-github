# -*- coding: utf-8 -*-
import os
import sys
import shutil
import chardet
import re
import subprocess
import random
from google.cloud import texttospeech
from mutagen.mp3 import MP3

os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = r"D:\\central-web-428404-n2-6a98d3a64225.json"
DESTINATION_FOLDER = r"D:\\ecobiz-youtube-uploader\\google-trans"
TMP_AUDIO_DIR = "_tts_tmp"

def detect_encoding(file_path):
    with open(file_path, "rb") as f:
        return chardet.detect(f.read()).get('encoding', 'utf-8')

def format_time(seconds):
    millisec = int((seconds % 1) * 1000)
    seconds = int(seconds)
    return f"{seconds//3600:02}:{(seconds//60)%60:02}:{seconds%60:02},{millisec:03}"

def split_text_by_sentence(text):
    sentences = re.split(r'(?<=[。！？])\s*', text)
    return [s.strip() for s in sentences if s.strip()]

def wrap_text(text, max_length=25):
    lines = []
    while len(text) > max_length:
        idx = max(text.rfind("、", 0, max_length), text.rfind("。", 0, max_length))
        if idx == -1:
            idx = max_length
        lines.append(text[:idx+1].strip())
        text = text[idx+1:].strip()
    lines.append(text)
    return "\n".join(lines)

JAPANESE_FEMALE_VOICES = [
    "ja-JP-Standard-A",
    "ja-JP-Wavenet-A"
]

def tts_each_sentence(sentences, base_name):
    os.makedirs(TMP_AUDIO_DIR, exist_ok=True)
    durations = []
    audio_files = []

    client = texttospeech.TextToSpeechClient()
    for i, sentence in enumerate(sentences):
        voice_name = random.choice(JAPANESE_FEMALE_VOICES)
        synthesis_input = texttospeech.SynthesisInput(text=sentence)
        voice = texttospeech.VoiceSelectionParams(language_code="ja-JP", name=voice_name)
        audio_config = texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3)

        response = client.synthesize_speech(input=synthesis_input, voice=voice, audio_config=audio_config)

        part_path = os.path.join(TMP_AUDIO_DIR, f"{base_name}_part_{i+1:03}.mp3")
        with open(part_path, "wb") as out:
            out.write(response.audio_content)

        audio = MP3(part_path)
        durations.append(audio.info.length)
        audio_files.append(part_path)

    return durations, audio_files

def generate_srt(sentences, durations, srt_file):
    with open(srt_file, "w", encoding="utf-8") as f:
        current_time = 0.0
        for i, (sentence, duration) in enumerate(zip(sentences, durations)):
            start = current_time
            end = start + duration
            f.write(f"{i+1}\n")
            f.write(f"{format_time(start)} --> {format_time(end)}\n")
            f.write(f"{wrap_text(sentence)}\n\n")
            current_time = end
    print(f"📝 SRTファイル作成完了: {srt_file}")

def concat_mp3(audio_files, output_mp3):
    list_path = os.path.join(TMP_AUDIO_DIR, "file_list.txt")
    with open(list_path, "w", encoding="utf-8") as f:
        for path in audio_files:
            f.write(f"file '{os.path.abspath(path)}'\n")

    cmd = ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list_path, "-c", "copy", output_mp3]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"🎵 MP3作成完了: {output_mp3}")

def make_mp4_with_subtitle(mp3_file, srt_file, output_mp4, durations):
    image_file = "black_horizontal.jpg"
    if not os.path.exists(image_file):
        subprocess.run([
            "ffmpeg", "-y", "-f", "lavfi", "-i", "color=c=black:s=1920x1080", "-frames:v", "1", image_file
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    total_duration = sum(durations)

    cmd = [
        "ffmpeg", "-y",
        "-loop", "1", "-i", image_file,
        "-i", mp3_file,
        "-vf", f"subtitles={srt_file}:force_style='FontName=MS Gothic,FontSize=18,Alignment=2,MarginV=80'",
        "-c:v", "libx264", "-tune", "stillimage",
        "-c:a", "aac", "-b:a", "192k",
	# "-filter:a", "volume=1.5",
        "-shortest",
        "-t", str(total_duration),
        output_mp4
    ]
    subprocess.run(cmd)
    print(f"🎬 動画作成完了（1920x1080 横長）: {output_mp4}")

def copy_file(file_path, destination_folder):
    if os.path.exists(file_path):
        os.makedirs(destination_folder, exist_ok=True)
        shutil.copy(file_path, os.path.join(destination_folder, os.path.basename(file_path)))
        print(f"📄 ファイルコピー完了: {file_path}")

def clean_tmp():
    if os.path.exists(TMP_AUDIO_DIR):
        shutil.rmtree(TMP_AUDIO_DIR)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("使用法: python script.py <input.txt>")
        sys.exit(1)

    input_file = sys.argv[1]
    if not os.path.isfile(input_file):
        print(f"❌ ファイルが見つかりません: {input_file}")
        sys.exit(1)

    print(f"📥 入力読込: {input_file}")
    encoding = detect_encoding(input_file)
    with open(input_file, "r", encoding=encoding) as f:
        text = f.read()

    # 🔴 横棒などの記号は変換しない（そのまま残す）

    base = os.path.splitext(os.path.basename(input_file))[0]
    mp3_output = base + ".mp3"
    srt_output = base + ".srt"
    mp4_output = base + ".mp4"

    sentences = split_text_by_sentence(text)
    #max_sentences = 8
    #sentences = sentences[:max_sentences]

    durations, audio_files = tts_each_sentence(sentences, base)
    generate_srt(sentences, durations, srt_output)
    concat_mp3(audio_files, mp3_output)
    make_mp4_with_subtitle(mp3_output, srt_output, mp4_output, durations)

    copy_file(mp4_output, "D:\\")
    clean_tmp()
    print("🎉 全処理完了（フォントサイズ18で字幕表示）")
