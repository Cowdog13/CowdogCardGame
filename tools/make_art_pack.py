#!/usr/bin/env python3
"""Builds an art pack (a folder plus a zip) for the game from your own images.

A table background only:
  python3 tools/make_art_pack.py --board my_background.png --id midnight-grove --name "Midnight Grove" --ai

A full art style, from one folder of images named after the cards:
  python3 tools/make_art_pack.py --art-dir my_art/ --id storybook --name "Storybook" --creator "Your Name" --ai
  python3 tools/make_art_pack.py --art-dir my_art/ --check        (only report what is found and what is missing)

--art-dir may contain sub-folders; only the file NAMES matter, and capitals, spaces, dashes and underscores are ignored:
  cards   "Firespore.png", "fire_lord.png", "Water Essence.png", "Removal.png", ... (every creature, leader and spell,
          and the five berries "Fire Berry.png", "Super Berry.png", ...; the small berry icons are made from these)
  symbols "Fire.png" or "Fire_Symbol.png", also Water, Nature, Light, Super, Colorless (black glyph on white, or transparent)
  back    "Card Back.png" (the logo on the back of the decks)
  board   "Board.png" / "Background.png" / "Table.png" (the table; 16:9, 2560 px wide at most)
Pictures on a plain white background get it cut out automatically, the art is cropped and made square, and everything is
resized to the game's sizes. Anything you leave out keeps the built-in art (a warning lists what is missing).

Creates  <out>/<id>/  (pack.json, cards/, berries/, symbols/, ui/, board/)  and  <out>/<id>.zip  (the zip holds the folder
<id>/, so a player just unzips it into the game's art_packs folder).
Needs: pillow (board only) or pillow + numpy + scipy (everything else):  pip install pillow numpy scipy
"""
import argparse
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
MAX_WIDTH = 2560
CARD_SIZE = 1024
ICON_SIZE = 256
SYMBOL_SIZE = 256
BACK_MAX = 852
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp"}
SYMBOLS = ["fire", "water", "nature", "light", "super", "colorless"]
BOARD_NAMES = {"board", "boardbg", "background", "table", "boardbackground"}
BACK_NAMES = {"cardback", "cardbacklogo", "back", "logo"}


def norm(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def load_cards() -> dict:
    return json.loads((HERE.parent / "data" / "cards.json").read_text())


def lazy_art():
    try:
        sys.path.insert(0, str(HERE))
        import process_art  # noqa: needs numpy and scipy
        return process_art
    except ImportError as e:
        sys.exit(f"Processing card art needs numpy and scipy ({e}). Install with:  pip install pillow numpy scipy")


def has_real_alpha(img: Image.Image) -> bool:
    if img.mode != "RGBA":
        return False
    alpha = img.getchannel("A")
    lo, _ = alpha.getextrema()
    return lo < 200 and sum(1 for v in alpha.getdata() if v < 128) > img.width * img.height * 0.02


def clean_art(path: Path, pa) -> Image.Image:
    img = Image.open(path)
    img = img.convert("RGBA") if has_real_alpha(img.convert("RGBA")) else pa.remove_white_background(img.convert("RGB"))
    return pa.crop_to_content(img).resize((CARD_SIZE, CARD_SIZE), Image.LANCZOS)


def symbol_art(path: Path, pa) -> Image.Image:
    img = Image.open(path)
    rgba = img.convert("RGBA")
    if has_real_alpha(rgba):  # a transparent shape: keep its outline, make it a white glyph
        white = Image.new("RGBA", rgba.size, (255, 255, 255, 0))
        white.putalpha(rgba.getchannel("A"))
        out = pa.crop_to_content(white, 0.06)
    else:
        out = pa.symbol_to_white(img.convert("RGB"))
    return out.resize((SYMBOL_SIZE, SYMBOL_SIZE), Image.LANCZOS)


def find_files(art_dir: Path, cards: dict) -> dict:
    """Maps what the file names mean to their paths: {("card", id) | ("symbol", name) | ("back",) | ("board",): Path}."""
    by_name = {}
    for cid, c in cards.items():
        by_name[norm(cid)] = ("card", cid)
        by_name[norm(c["name"])] = ("card", cid)
    for s in SYMBOLS:
        by_name.setdefault(norm(s), ("symbol", s))
        by_name[norm(s + " symbol")] = ("symbol", s)
    for n in BOARD_NAMES:
        by_name[n] = ("board",)
    for n in BACK_NAMES:
        by_name[n] = ("back",)
    found, unknown = {}, []
    for f in sorted(art_dir.rglob("*")):
        if f.suffix.lower() not in IMAGE_EXTS or not f.is_file():
            continue
        key = by_name.get(norm(f.stem))
        if key is None:
            unknown.append(f)
        else:
            if key in found:
                print(f"  note: {f.name} replaces {found[key].name}")
            found[key] = f
    return {"found": found, "unknown": unknown}


def report(found: dict, unknown: list, cards: dict) -> list:
    groups = {"creature": [], "leader": [], "spell": [], "berry": []}
    for cid, c in cards.items():
        g = "leader" if c.get("leader") else ("creature" if c["kind"] == "creature" else c["kind"])
        groups[g].append(cid)
    missing = []
    for g, ids in groups.items():
        have = [i for i in ids if ("card", i) in found]
        gone = [cards[i]["name"] for i in ids if ("card", i) not in found]
        label = {"creature": "creatures", "leader": "leaders", "spell": "spells", "berry": "berries"}[g]
        print(f"  {label:10} {len(have):2}/{len(ids):2}" + (f"   missing: {', '.join(gone)}" if gone else ""))
        missing += gone
    have = [s for s in SYMBOLS if ("symbol", s) in found]
    gone = [s for s in SYMBOLS if ("symbol", s) not in found]
    print(f"  {'symbols':10} {len(have):2}/{len(SYMBOLS):2}" + (f"   missing: {', '.join(gone)}" if gone else ""))
    print(f"  {'card back':10} {'yes' if ('back',) in found else 'missing (keeps the default)'}")
    print(f"  {'board':10} {'yes' if ('board',) in found else 'missing (keeps the default)'}")
    if unknown:
        print("  ignored (names not recognised): " + ", ".join(f.name for f in unknown))
    return missing


def build(args, found: dict, cards: dict, folder: Path) -> None:
    (folder).mkdir(parents=True)
    if any(k[0] != "board" for k in found):
        pa = lazy_art()
    for key, path in found.items():
        if key[0] == "card":
            cid = key[1]
            art = clean_art(path, pa)
            (folder / "cards").mkdir(exist_ok=True)
            art.save(folder / "cards" / f"{cid}.png", optimize=True)
            if cards[cid]["kind"] == "berry":
                (folder / "berries").mkdir(exist_ok=True)
                art.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS).save(folder / "berries" / f"{cid}.png", optimize=True)
        elif key[0] == "symbol":
            (folder / "symbols").mkdir(exist_ok=True)
            symbol_art(path, pa).save(folder / "symbols" / f"{key[1]}.png", optimize=True)
        elif key[0] == "back":
            img = Image.open(path)
            img = img.convert("RGBA") if has_real_alpha(img.convert("RGBA")) else pa.remove_white_background(img.convert("RGB"))
            img = pa.crop_to_content(img, 0.02)
            scale = min(1.0, BACK_MAX / max(img.size))
            if scale < 1.0:
                img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
            (folder / "ui").mkdir(exist_ok=True)
            img.save(folder / "ui" / "card_back_logo.png", optimize=True)
        elif key[0] == "board":
            img = Image.open(path).convert("RGB")
            if img.width > MAX_WIDTH:
                img = img.resize((MAX_WIDTH, round(img.height * MAX_WIDTH / img.width)), Image.LANCZOS)
            (folder / "board").mkdir(exist_ok=True)
            img.save(folder / "board" / "board_bg.webp", quality=90)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--board", help="just a table background image (16:9 works best)")
    ap.add_argument("--art-dir", help="a folder of images named after the cards (see above)")
    ap.add_argument("--check", action="store_true", help="only report what --art-dir contains and what is missing")
    ap.add_argument("--id", help="folder name, e.g. midnight-grove (letters, digits, dashes)")
    ap.add_argument("--name")
    ap.add_argument("--creator", default="")
    ap.add_argument("--description", default="A new look for the game.")
    ap.add_argument("--publisher", default="Cowdog Game Store", help="credit line shown under the pack in the game")
    ap.add_argument("--ai", action="store_true", help="record in pack.json that the art is AI-generated (the itch.io page must say so too)")
    ap.add_argument("--out", default="build/art_packs")
    args = ap.parse_args()
    if not args.board and not args.art_dir:
        ap.error("give --board and/or --art-dir")

    cards = load_cards()
    found, unknown = {}, []
    if args.art_dir:
        scan = find_files(Path(args.art_dir), cards)
        found, unknown = scan["found"], scan["unknown"]
    if args.board:
        found[("board",)] = Path(args.board)
    print("Found:")
    missing = report(found, unknown, cards)
    if args.check:
        return
    if not args.id or not args.name:
        ap.error("--id and --name are required to build a pack")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", args.id):
        ap.error("--id may only contain lowercase letters, digits and dashes")
    if not found:
        sys.exit("No usable images found.")

    out = Path(args.out)
    folder = out / args.id
    if folder.exists():
        shutil.rmtree(folder)
    build(args, found, cards, folder)
    meta = {"name": args.name, "creator": args.creator, "description": args.description, "publisher": args.publisher, "ai_generated": args.ai}
    (folder / "pack.json").write_text(json.dumps(meta, indent=1))
    zip_path = out / f"{args.id}.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(folder.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(out))
    n = sum(1 for f in folder.rglob("*") if f.is_file() and f.name != "pack.json")
    print(f"\n{folder}  ->  {zip_path}  ({n} images)")
    if missing:
        print(f"Note: {len(missing)} cards are missing, so those keep the default art and will not match the style.")


if __name__ == "__main__":
    main()
