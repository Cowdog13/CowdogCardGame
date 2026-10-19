#!/usr/bin/env python3
"""Turns the raw art deliveries (square PNGs on white backgrounds, black-on-white symbols)
into game-ready assets with transparent backgrounds.

  python3 tools/process_art.py <raw_dir> <out_assets_dir>

<raw_dir> holds the unzipped Berries/, Symbols/, FireCards/ and WaterCards/ folders.
Needs: pillow, numpy, scipy.   Re-run whenever art is replaced.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

CARD_FILES = {
    "FireCards/Fire_Famine.png": "fire_famine", "FireCards/Fire_King.png": "fireking",
    "FireCards/Fire_Spitter.png": "firespitter", "FireCards/Fire_Wolf.png": "firewolf",
    "FireCards/Firepup.png": "firepup", "FireCards/Firespore.png": "firespore",
    "FireCards/Reinforce.png": "reinforce", "FireCards/Removal.png": "removal",
    "WaterCards/Disable.png": "disable", "WaterCards/Water_Binder.png": "water_binder",
    "WaterCards/Water_Constrictor.png": "water_constrictor", "WaterCards/Water_Crash.png": "water_crash",
    "WaterCards/Water_Ruler.png": "water_ruler", "WaterCards/Water_Spirit.png": "water_spirit",
    "WaterCards/Water_Sprite.png": "water_sprite",
    "Berries/Fire_Berry.png": "fire_berry", "Berries/Water_Berry.png": "water_berry",
    "Berries/Super_Berry.png": "super_berry",
}
SYMBOL_FILES = {
    "Symbols/Fire_Symbol.png": "fire", "Symbols/Water_Symbol.png": "water", "Symbols/Nature_Symbol.png": "nature",
    "Symbols/Light_Symbol.png": "light", "Symbols/Shadow_Symbol.png": "shadow", "Symbols/Super_Symbol.png": "super",
    "Symbols/Colorless_Symbol.png": "colorless",
}
ART_SIZE = 1024
SYMBOL_SIZE = 256
BERRY_ICON_SIZE = 256
SHADOW_REACH = 22  # px: how far grey shadows are traced away from the outside


def remove_white_background(img: Image.Image) -> Image.Image:
    """Makes the white (and soft grey shadow) background connected to the image border transparent.
    White areas inside the creature (fur, eyes) are kept because they are not connected to the border."""
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    mn = rgb.min(axis=2)
    mx = rgb.max(axis=2)
    sat = mx - mn
    # Pure-white paper only: exterior = near-white pixels connected to the image border. (A looser
    # threshold would also eat white fur that touches the outside.)
    candidate = mn >= 240
    labels, _ = ndi.label(candidate)
    border = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    border = border[border != 0]
    exterior = np.isin(labels, border)
    # Anti-aliased edge: pixels next to the exterior get a partial alpha from how white they are.
    near = ndi.binary_dilation(exterior, iterations=3) & ~exterior
    alpha = np.ones(mn.shape, np.float32)
    alpha[exterior] = 0.0
    edge_alpha = np.clip((250.0 - mn) / (250.0 - 170.0), 0.0, 1.0)
    alpha[near] = np.maximum(edge_alpha[near], 0.0)
    # Un-blend the white from edge colours so there is no light halo.
    a = np.maximum(alpha, 1e-3)[..., None]
    out = np.where(near[..., None], np.clip((rgb - 255.0 * (1 - a)) / a, 0, 255), rgb)
    # Soft grey ground shadows next to the outside become translucent black instead of grey blobs.
    greyish = (sat < 9) & (mn >= 190) & (mn < 240) & ~exterior
    reach = ndi.binary_dilation(exterior, iterations=SHADOW_REACH) & greyish
    grow_lab, _ = ndi.label(greyish)
    touching = np.unique(grow_lab[reach])
    shadow = np.isin(grow_lab, touching[touching != 0]) & ndi.binary_dilation(exterior, iterations=SHADOW_REACH)
    out[shadow] = 0.0
    alpha[shadow] = np.clip((255.0 - mn[shadow]) / 255.0 * 0.9, 0.0, 1.0)
    # Drop stray specks (tiny disconnected bits of background).
    keep, n = ndi.label(alpha > 0.05)
    if n > 1:
        sizes = ndi.sum(np.ones_like(alpha), keep, index=np.arange(1, n + 1))
        small = np.isin(keep, np.where(sizes < 600)[0] + 1)
        alpha[small] = 0.0
    rgba = np.dstack([out, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def crop_to_content(img: Image.Image, pad_frac: float = 0.04) -> Image.Image:
    """Crops transparent margins, then pads to a square so every card art has the same aspect."""
    box = img.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
    if box:
        img = img.crop(box)
    side = int(max(img.size) * (1 + 2 * pad_frac))
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.alpha_composite(img, ((side - img.width) // 2, (side - img.height) // 2))
    return out


def symbol_to_white(img: Image.Image) -> Image.Image:
    """Black glyph on white -> white glyph with alpha (tint it with modulate in the game)."""
    gray = np.asarray(img.convert("L")).astype(np.float32)
    alpha = np.clip((205.0 - gray) / (205.0 - 70.0), 0.0, 1.0)
    # Keep only the main glyph: drop faint shadow remains.
    alpha[alpha < 0.08] = 0.0
    white = np.full(gray.shape + (3,), 255, np.uint8)
    out = Image.fromarray(np.dstack([white, (alpha * 255).astype(np.uint8)]), "RGBA")
    return crop_to_content(out, 0.06)


def main() -> None:
    raw = Path(sys.argv[1])
    out = Path(sys.argv[2])
    for sub in ("cards", "symbols", "berries", "ui"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    for rel, card_id in CARD_FILES.items():
        img = remove_white_background(Image.open(raw / rel))
        img = crop_to_content(img).resize((ART_SIZE, ART_SIZE), Image.LANCZOS)
        img.save(out / "cards" / f"{card_id}.png", optimize=True)
        if card_id.endswith("_berry"):
            img.resize((BERRY_ICON_SIZE, BERRY_ICON_SIZE), Image.LANCZOS).save(out / "berries" / f"{card_id}.png", optimize=True)
        print("card", card_id)
    for rel, name in SYMBOL_FILES.items():
        symbol_to_white(Image.open(raw / rel)).resize((SYMBOL_SIZE, SYMBOL_SIZE), Image.LANCZOS).save(out / "symbols" / f"{name}.png", optimize=True)
        print("symbol", name)
    back = Image.open(raw / "FireCards/Card_Back.png").convert("RGBA")
    back = crop_to_content(back, 0.02)
    back.resize((back.width * 2, back.height * 2), Image.LANCZOS).save(out / "ui" / "card_back_logo.png", optimize=True)
    print("card back logo")


if __name__ == "__main__":
    main()
