# Music Preprocessing

Offline preprocessing project for building a Flutter-ready music metadata library.

The pipeline takes open-license audio files, estimates BPM, optionally scores each track against environment prompts with CLAP, and writes `data/processed/music_library.json`.

## Project Structure

```text
Music_Preprocessing/
  config/
    environment_prompts.json
    open_music_sources.json
  data/
    raw_music/
    processed/
  notebooks/
    context_music_preprocess.ipynb
  scripts/
    download_open_music.py
    preprocess_music.py
  requirements.txt
```

## Quick Start

1. Put `.mp3`, `.wav`, `.m4a`, `.flac`, or `.ogg` files in `data/raw_music/`.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Build the library:

```bash
python scripts/preprocess_music.py --input data/raw_music --output data/processed/music_library.json
```

4. Copy the generated JSON into the Flutter app:

```bash
copy data\processed\music_library.json ..\App_Research\assets\data\music_library.json
```

## CLAP Environment Matching

By default, the script runs BPM extraction and simple fallback tagging. To enable audio-text matching:

```bash
pip install -r requirements-clap.txt
python scripts/preprocess_music.py --input data/raw_music --output data/processed/music_library.json --use-clap
```

CLAP installation is heavier than BPM extraction because it uses PyTorch. If CLAP fails locally, run the same command in Google Colab using `notebooks/context_music_preprocess.ipynb`.

## Downloading Open-License Music

You can manually download music from:

- [Free Music Archive](https://freemusicarchive.org/)
- [Pixabay Music](https://pixabay.com/music/)
- [Internet Archive audio collections](https://archive.org/details/audio)
- [ccMixter](http://ccmixter.org/)
- [FreePD](https://freepd.com/)
- [OpenGameArt audio](https://opengameart.org/art-search-advanced?keys=&field_art_type_tid%5B%5D=12)

Always record title, artist, source URL, and license. The app/demo can use Creative Commons or public-domain music, but attribution requirements still depend on the individual track.

The helper script can download direct URLs or Internet Archive items declared in `config/open_music_sources.json`:

```bash
python scripts/download_open_music.py --manifest config/open_music_sources.json --output data/raw_music
```

## Output Format

Each track is written like this:

```json
{
  "id": "track_001",
  "title": "Track 001",
  "artist": "Unknown",
  "fileName": "track_001.mp3",
  "bpm": 88.4,
  "environmentTags": ["ocean", "river"],
  "scores": {
    "forest": 0.21,
    "ocean": 0.78,
    "river": 0.61
  },
  "sourceUrl": "",
  "license": "",
  "attribution": ""
}
```

## Dissertation Framing

This folder is the offline data-construction module. The Flutter app is the runtime recommendation module. The app does not need to run ML on device; it only consumes the generated JSON.
