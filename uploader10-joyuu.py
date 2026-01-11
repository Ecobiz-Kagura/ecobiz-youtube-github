import os
import shutil
import chardet
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

# 認証スコープ
SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]

def authenticate():
    """Google API 認証処理"""
    creds = None
    token_file = "token.json"
    credentials_file = r"D:\client_secret_487095582016-s9mbp3bkvft6cidq2nn6nted181p7pef.apps.googleusercontent.com.json"

    if os.path.exists(token_file):
        creds = Credentials.from_authorized_user_file(token_file, SCOPES)

    if not creds or not creds.valid:
        try:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(credentials_file, SCOPES)
                creds = flow.run_local_server(port=8080, access_type="offline", prompt="consent")

            with open(token_file, "w") as token:
                token.write(creds.to_json())

        except Exception as e:
            print(f"認証エラー: {e}")
            return None

    return creds

def get_metadata_from_textfile(txt_file, fallback_title):
    """タイトルと説明をテキストファイルから取得（文字化け検出時はファイル名をタイトルにする）"""
    if not os.path.exists(txt_file):
        print(f"警告: {txt_file} が見つかりません。デフォルトのタイトルを使用します。")
        return fallback_title, ""

    try:
        with open(txt_file, "rb") as f:
            raw_data = f.read()
            detected = chardet.detect(raw_data)
            encoding = detected["encoding"]

        with open(txt_file, "r", encoding=encoding, errors="strict") as f:
            lines = f.readlines()

        title = lines[0].strip() if lines else fallback_title
        description = "".join(lines[1:]).strip() if len(lines) > 1 else ""
        return title, description

    except (UnicodeDecodeError, TypeError):
        print(f"警告: {txt_file} は文字化けしている可能性があります。ファイル名をタイトルに設定し、説明を空白にします。")
        return fallback_title, ""

def upload_video(file_path, title, description, category_id="22", privacy_status="public"):
    """動画をYouTubeにアップロード"""
    creds = authenticate()
    if not creds:
        print("エラー: 認証に失敗しました。")
        return None

    youtube = build("youtube", "v3", credentials=creds)

    request_body = {
        "snippet": {
            "title": title,
            "description": description,
            "tags": ["自動アップロード", "YouTube API"],
            "categoryId": category_id
        },
        "status": {
            "privacyStatus": privacy_status
        }
    }

    try:
        media = MediaFileUpload(file_path, chunksize=-1, resumable=True, mimetype="video/*")
        request = youtube.videos().insert(part="snippet,status", body=request_body, media_body=media)
        response = request.execute()
        print(f"アップロード完了: {file_path} -> 動画ID: {response['id']}")
        return response['id']

    except Exception as e:
        print(f"エラー: {file_path} のアップロード中に問題が発生しました: {e}")
        return None

def move_to_done_directory(file_path):
    """ファイルと関連する .srt / .mp3 を ./done ディレクトリに移動"""
    done_dir = os.path.join(os.path.dirname(file_path), "done")
    os.makedirs(done_dir, exist_ok=True)

    # メインファイルの移動
    shutil.move(file_path, os.path.join(done_dir, os.path.basename(file_path)))

    # 関連ファイル（.srt, .mp3）の移動
    base_name, _ = os.path.splitext(file_path)
    for ext in [".srt", ".mp3", ".txt"]:
        related_file = base_name + ext
        if os.path.exists(related_file):
            shutil.move(related_file, os.path.join(done_dir, os.path.basename(related_file)))

def upload_single_video(file_path, category_id="22", privacy_status="public"):
    """単一の動画ファイルをアップロードし、成功したら ./done に移動"""
    if not os.path.exists(file_path):
        print(f"エラー: 指定されたファイルが見つかりません: {file_path}")
        return

    fallback_title = os.path.splitext(os.path.basename(file_path))[0]
    txt_path = os.path.splitext(file_path)[0] + ".txt"
    title, description = get_metadata_from_textfile(txt_path, fallback_title)

    # 🔽【ラジオ】をタイトルの先頭に追加
    title = f"【女優】{title}"

    print(f"アップロード開始: {file_path} | タイトル: {title} | 説明: {description}")

    video_id = upload_video(file_path, title, description, category_id, privacy_status)
    if video_id:
        print(f"アップロード成功: {file_path}")
        move_to_done_directory(file_path)
        print(f"ファイル移動完了: {file_path} -> ./done/")
    else:
        print(f"エラー: {file_path} のアップロードに失敗しました。ファイルは移動しません。")

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="動画をYouTubeに自動アップロード")
    parser.add_argument("path", help="動画ファイルのパス")
    parser.add_argument("--category_id", default="22", help="YouTubeのカテゴリID")
    parser.add_argument("--privacy_status", choices=["public", "unlisted", "private"], default="public", help="公開範囲")

    args = parser.parse_args()

    if os.path.isfile(args.path):
        upload_single_video(args.path, args.category_id, args.privacy_status)
    else:
        print("エラー: 指定されたパスが無効です。")
