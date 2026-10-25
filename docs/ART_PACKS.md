# Art packs

An art pack is a folder in the game's `art_packs` folder (Windows: `%APPDATA%\CowdogCardGame\art_packs`; the **Art packs**
screen has an "Open art packs folder" button). The player picks one under **Art packs** in the main menu; the choice is
remembered. Anything a pack doesn't contain keeps the built-in art.

```
art_packs/
  midnight-grove/
    pack.json                  {"name": "...", "creator": "...", "description": "...", "publisher": "Cowdog Game Store", "ai_generated": true}
    board/board_bg.webp        table background (webp, png or jpg; 16:9 works best, 2560 px wide at most)
    cards/<card id>.png        (later) card art, e.g. cards/firespore.png, square, transparent background
    berries/<id>.png, symbols/<element>.png, ui/card_back_logo.png   (later)
```

## Making a pack

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
