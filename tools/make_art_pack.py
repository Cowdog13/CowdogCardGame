#!/usr/bin/env python3
"""Builds an art pack (a folder plus a zip) for the game from your own images.

  python3 tools/make_art_pack.py --board my_background.png --id midnight-grove --name "Midnight Grove" \
      --creator "Cowdog Games" --ai --out build/art_packs

Creates  <out>/<id>/pack.json  and  <out>/<id>/board/board_bg.webp  and  <out>/<id>.zip  (the zip holds the folder
<id>/, so a player just unzips it into the game's art_packs folder). Needs: pillow.

The pack format mirrors the game's own assets: board/board_bg.(webp|png|jpg) is the table background; cards/<card id>.png,
berries/<id>.png, symbols/<element>.png and ui/card_back_logo.png can be added the same way later. Anything a pack does
not contain keeps the built-in art.
"""
import argparse
import json
import shutil
import zipfile
from pathlib import Path

from PIL import Image

MAX_WIDTH = 2560


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--board", required=True, help="background image (16:9 works best)")
    ap.add_argument("--id", required=True, help="folder name, e.g. midnight-grove (letters, digits, dashes)")
    ap.add_argument("--name", required=True)
    ap.add_argument("--creator", default="")
    ap.add_argument("--description", default="A new look for the game table.")
    ap.add_argument("--publisher", default="Cowdog Game Store", help="credit line shown under the pack in the game")
    ap.add_argument("--ai", action="store_true", help="record in pack.json that the art is AI-generated (the itch.io page must say so too)")
    ap.add_argument("--out", default="build/art_packs")
    args = ap.parse_args()

    out = Path(args.out)
    folder = out / args.id
    if folder.exists():
        shutil.rmtree(folder)
    (folder / "board").mkdir(parents=True)
    img = Image.open(args.board).convert("RGB")
    if img.width > MAX_WIDTH:
        img = img.resize((MAX_WIDTH, round(img.height * MAX_WIDTH / img.width)), Image.LANCZOS)
    img.save(folder / "board" / "board_bg.webp", quality=90)
    meta = {"name": args.name, "creator": args.creator, "description": args.description, "publisher": args.publisher, "ai_generated": args.ai}
    (folder / "pack.json").write_text(json.dumps(meta, indent=1))
    zip_path = out / f"{args.id}.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(folder.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(out))
    print(f"{folder}  ->  {zip_path}  ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
