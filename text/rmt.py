#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rmt_txt_not_contains.py (改良版)
・デフォルト: 「KW を含まない .txt」だけ削除
・--all を付ける: すべての .txt を削除（マルクスも含む）
・--apply を付けたときだけ実削除
"""

import argparse
from pathlib import Path
import unicodedata
import sys

KW = "マルクス"   # キーワード


def clean(s: str) -> str:
    """NFKC 正規化＋不可視文字除去"""
    n = unicodedata.normalize("NFKC", s)
    out = []
    for ch in n:
        cat = unicodedata.category(ch)
        if cat in ("Mn", "Me", "Cf"):
            continue
        if ch in ("\u200b", "\u200c", "\u200d", "\ufeff"):
            continue
        out.append(ch)
    return "".join(out)


def main():
    ap = argparse.ArgumentParser(description="Delete .txt files depending on keyword")
    ap.add_argument("--apply", action="store_true", help="実削除を実行（指定しない場合はドライラン）")
    ap.add_argument("--all", action="store_true", help="すべての .txt を削除（KW 無視）")
    ap.add_argument("--dir", default=".", help="対象ディレクトリ（既定: カレント）")
    args = ap.parse_args()

    base = Path(args.dir)
    if not base.is_dir():
        print(f"ディレクトリが見つかりません: {base}", file=sys.stderr)
        sys.exit(1)

    kw_clean = clean(KW)

    targets = []
    keeps = []

    for p in base.iterdir():
        if p.is_file() and p.suffix.lower() == ".txt":
            name_clean = clean(p.name)

            if args.all:
                # --all 指定時は全部削除
                targets.append(p)
                continue

            # キーワードを含むかどうか
            if kw_clean not in name_clean:
                targets.append(p)
            else:
                keeps.append(p)

    # ---- ログ ----
    print(f"キーワード: {KW}（正規化後: {kw_clean}）")
    if args.all:
        print("\n※--all モード：マルクスを含む・含まないに関係なく、すべての .txt を削除対象にします。")

    print("\n―― 残すファイル ――")
    for k in keeps:
        print("KEEP :", k.name)

    print("\n―― 削除候補 ――")
    for t in targets:
        print("DEL? :", t.name)

    if not args.apply:
        print("\n※ドライランです。実削除は行っていません。削除するには --apply を付けてください。")
        return

    # ---- 実削除 ----
    print("\n―― 実削除ログ ――")
    deleted = 0
    for t in targets:
        try:
            t.unlink()
            print(f"DELETED: {t.name}")
            deleted += 1
        except Exception as e:
            print(f"ERROR  : {t.name} -> {e}", file=sys.stderr)

    print(f"\n完了: {deleted} 件削除 / {len(targets)} 件対象")


if __name__ == "__main__":
    main()
