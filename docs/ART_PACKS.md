# Art packs

An art pack is a folder in the game's `art_packs` folder (Windows: `%APPDATA%\CowdogCardGame\art_packs`; the **Art packs**
screen has an "Open art packs folder" button). The player picks one under **Art packs** in the main menu; the choice is
remembered. Anything a pack doesn't contain keeps the built-in art.

**Several packs can be switched on at once** (click a pack, then "Use this pack" / "Stop using this pack"). Each picture comes from a pack that has it, so e.g. a table-background pack and a card-art pack combine.
If two switched-on packs have the same picture, one of them is picked at random for each picture when a game starts (and stays the same for that game).

```
art_packs/
  midnight-grove/
    pack.json                  {"name": "...", "creator": "...", "description": "...", "publisher": "Cowdog Game Store", "ai_generated": true}
    board/board_bg.webp        table background (webp, png or jpg; 16:9 works best, 2560 px wide at most)
    cards/<card id>.png        (later) card art, e.g. cards/firespore.png, square, transparent background
    berries/<id>.png, symbols/<element>.png, ui/card_back_logo.png   (later)
```

## Making a full art-style pack (all 47 images)

Put the images in one folder (sub-folders are fine). Only the file names matter, ignoring capitals, spaces, dashes and underscores:

- **39 card images**: every creature, leader and spell by its name (`Firespore.png`, `Fire Lord.png`, `Water Essence.png`, `Spore Muncher.png`,
  `Removal.png`, `Gather.png`, ...) and the five berries (`Fire Berry.png`, `Water Berry.png`, `Nature Berry.png`, `Light Berry.png`, `Super Berry.png`).
  The small berry icons are made from the berry cards.
- **6 symbols**: `Fire.png` (or `Fire_Symbol.png`), `Water`, `Nature`, `Light`, `Super`, `Colorless`; a black shape on white (or a transparent shape).
- **Card back**: `Card Back.png`. **Table**: `Board.png` / `Background.png` / `Table.png`.

```
pip install pillow numpy scipy
python3 tools/make_art_pack.py --art-dir my_art/ --check                       # what's found, what's missing
python3 tools/make_art_pack.py --art-dir my_art/ --id storybook --name "Storybook" --creator "Your Name" --ai --out build/art_packs
```

Pictures on a plain white background get it cut out, the art is cropped and made square, and everything is resized to the game's sizes.
Missing images keep the built-in art and are listed in the output. `tests/make_art_pack_test.py` checks the script.

## Making a pack with only a table background

    python3 tools/make_art_pack.py --board my_background.png --id midnight-grove --name "Midnight Grove" \
        --creator "Your Name" --ai --out build/art_packs

The pack screen shows the pack's name, creator, description and `publisher` ("Cowdog Game Store" by default). `--ai` only
records the fact in `pack.json`; the disclosure that matters is the one on the itch.io page (below).

This writes the folder and a zip (`build/art_packs/midnight-grove.zip`) that contains the folder, so a buyer just unzips
it into the art packs folder.

## Selling it on itch.io (separate project per pack)

1. Dashboard -> Create new project. Kind of project: "Game mod" or "Assets". Title e.g. "Elemental Showdown - Midnight Grove table".
2. Pricing: Paid, minimum price 0.99. (Payout details must be set up in your itch.io account.)
3. Uploads: the pack zip. Add a cover image and screenshots of the new table.
4. Description: needs the base game; install by unzipping into the art packs folder (or the in-game button); and
   **say clearly that the art was made with AI (Midjourney)**. itch.io also has a generative-AI disclosure setting on the
   project page: fill it in.
5. Visibility: Restricted/Draft while testing, Public when ready. Link the page from the game's page and vice versa.

Midjourney: check the current terms for your plan (ownership/commercial use of images made with a paid plan, and any
limits that depend on company revenue) before selling. Note that AI-generated images may get little or no copyright
protection in some countries, so others could copy a pack; that is a trade-off of selling cosmetics.
