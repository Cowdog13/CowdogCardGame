#!/usr/bin/env python3
"""Builds a full art pack from synthetic input (the game's own art on white, with varied file names) and checks the output.
  python3 tests/make_art_pack_test.py
"""
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
cards = json.loads((ROOT / "data" / "cards.json").read_text())


def on_white(img: Image.Image, size: int) -> Image.Image:
    bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
    bg.alpha_composite(img.convert("RGBA"))
    return bg.convert("RGB").resize((size, size))


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    src = tmp / "my art" / "sub folder"
    src.mkdir(parents=True)
    n = 0
    for cid, c in cards.items():
        art = ROOT / "assets" / "cards" / f"{cid}.png"
        if cid == "removal":  # leave one out: it must be reported as missing
            continue
        # file names written the way a person would: spaces, capitals, underscores
        on_white(Image.open(art), 600).save(src / f"{c['name'].replace(' ', '_').upper() if n % 2 else c['name']}.png")
        n += 1
    for s in ["fire", "water", "nature", "light", "super", "colorless"]:
        glyph = Image.open(ROOT / "assets" / "symbols" / f"{s}.png").convert("RGBA")
        black = Image.new("RGBA", glyph.size, (0, 0, 0, 255))
        black.putalpha(glyph.getchannel("A"))
        on_white(black, 300).save(src / f"{s.capitalize()}_Symbol.png")
    on_white(Image.open(ROOT / "assets" / "ui" / "card_back_logo.png"), 500).save(src / "Card Back.png")
    Image.open(ROOT / "assets" / "board" / "board_bg.webp").save(src / "Table.jpg")
    (src / "readme.txt").write_text("not an image")
    (src / "Mystery.png").write_bytes((src / "Table.jpg").read_bytes())

    out = tmp / "out"
    res = subprocess.run([sys.executable, str(ROOT / "tools" / "make_art_pack.py"), "--art-dir", str(tmp / "my art"), "--id", "test-style",
                          "--name", "Test Style", "--ai", "--out", str(out)], capture_output=True, text=True)
    print(res.stdout)
    assert res.returncode == 0, res.stderr
    pack = out / "test-style"
    fails = 0

    def check(ok, msg):
        global fails
        if not ok:
            fails += 1
            print("FAIL:", msg)

    card_files = sorted(p.stem for p in (pack / "cards").glob("*.png"))
    check(len(card_files) == len(cards) - 1 and "removal" not in card_files, f"cards: {len(card_files)}")
    check(len(list((pack / "berries").glob("*.png"))) == 5, "5 berry icons made from the berry cards")
    check(len(list((pack / "symbols").glob("*.png"))) == 6, "6 symbols")
    check((pack / "ui" / "card_back_logo.png").exists() and (pack / "board" / "board_bg.webp").exists(), "card back and board")
    im = Image.open(pack / "cards" / "firespore.png")
    check(im.size == (1024, 1024) and im.mode == "RGBA" and im.getpixel((2, 2))[3] == 0, "card art is square with a cut-out background")
    check(Image.open(pack / "berries" / "fire_berry.png").size == (256, 256), "berry icon size")
    sym = Image.open(pack / "symbols" / "fire.png")
    check(sym.size == (256, 256) and sym.getpixel((128, 128))[:3] == (255, 255, 255), "symbols are white glyphs")
    check("Mystery.png" in res.stdout and "Removal" in res.stdout, "unrecognised files and missing cards are reported")
    check((out / "test-style.zip").exists() and "test-style/pack.json" in zipfile.ZipFile(out / "test-style.zip").namelist(), "zip with the folder inside")
    meta = json.loads((pack / "pack.json").read_text())
    check(meta["publisher"] == "Cowdog Game Store" and meta["ai_generated"] is True, "pack.json")
    check((pack / "preview.webp").exists() and Image.open(pack / "preview.webp").size == (1600, 900), "a preview picture is made")
    check("decks" not in meta, "a pack with cards of every deck is for every deck")
    # A pack with only Nature cards is made for the Nature deck (and says so, for shared cards like Removal).
    part = tmp / "nature only"
    part.mkdir()
    for n in ["Leafer", "Removal"]:
        on_white(Image.open(ROOT / "assets" / "cards" / f"{n.lower()}.png"), 600).save(part / f"{n}.png")
    res2 = subprocess.run([sys.executable, str(ROOT / "tools" / "make_art_pack.py"), "--art-dir", str(part), "--id", "nature-only",
                           "--name", "Nature Only", "--out", str(out)], capture_output=True, text=True)
    assert res2.returncode == 0, res2.stderr
    meta2 = json.loads((out / "nature-only" / "pack.json").read_text())
    check(meta2.get("decks") == ["nature_exile"], f"decks of a Nature-only pack: {meta2.get('decks')}")
    # White background trapped between parts of the drawing goes; a white eye deep inside the figure stays.
    sys.path.insert(0, str(ROOT / "tools"))
    import make_art_pack as m
    from PIL import ImageDraw
    img = Image.new("RGB", (2048, 2048), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.rectangle((300, 300, 1700, 1700), fill=(40, 90, 40))  # the figure
    d.rectangle((360, 1100, 700, 1500), fill=(255, 255, 255))  # a pocket of background near the figure's edge
    d.ellipse((900, 800, 1100, 1000), fill=(255, 255, 255))  # an eye, far from the outside
    cleaned = m.remove_background_pockets(m.lazy_art().remove_white_background(img))
    check(cleaned.getpixel((550, 1300))[3] == 0, "a pocket near the outside is removed")
    check(cleaned.getpixel((1000, 900))[3] == 255, "a white eye deep inside is kept")
    print("make_art_pack_test failures=%d" % fails)
    sys.exit(1 if fails else 0)
