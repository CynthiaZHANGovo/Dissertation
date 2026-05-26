from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import quote

import requests
from tqdm import tqdm


PIECES_URL = "https://incompetech.com/music/royalty-free/pieces.json"
MP3_BASE_URL = "https://incompetech.com/music/royalty-free/mp3-royaltyfree"
TRACK_PAGE_BASE_URL = "https://incompetech.com/music/royalty-free/index.html?isrc="
USER_AGENT = "MusicPreprocessingDemo/1.0"

GENRES = {
    "2": "African",
    "3": "Blues",
    "4": "Classical",
    "5": "Contemporary",
    "6": "Disco",
    "7": "Electronica",
    "8": "Funk",
    "9": "Holiday",
    "10": "Horror",
    "11": "Jazz",
    "12": "Latin",
    "13": "Modern",
    "14": "Musical",
    "15": "Polka",
    "16": "Pop",
    "18": "Reggae",
    "19": "Rock",
    "20": "Silent Film Score",
    "21": "Ska",
    "22": "Soundtrack",
    "23": "Stings",
    "24": "Unclassifiable",
    "25": "World",
    "26": "Urban",
}


def slugify(value: str, fallback: str = "track") -> str:
    value = re.sub(r"[^a-zA-Z0-9._-]+", "_", value.strip()).strip("_")
    return value or fallback


def read_track_requests(path: Path) -> list[dict[str, str]]:
    tracks = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if "|" in line:
            name, isrc = [part.strip() for part in line.rsplit("|", 1)]
        else:
            name, isrc = "", line.strip()

        isrc = isrc.upper().replace(" ", "")
        if not re.fullmatch(r"[A-Z]{5}\d{7}", isrc):
            print(f"[WARN] Skipped invalid ISRC line: {raw_line}")
            continue
        tracks.append({"name": name, "isrc": isrc})
    return tracks


def fetch_pieces() -> list[dict]:
    response = requests.get(PIECES_URL, headers={"User-Agent": USER_AGENT}, timeout=60)
    response.raise_for_status()
    return response.json()


def download_file(url: str, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists() and output_path.stat().st_size > 0:
        print(f"Using existing file: {output_path.name}")
        return

    response = requests.get(url, stream=True, headers={"User-Agent": USER_AGENT}, timeout=60)
    response.raise_for_status()
    total = int(response.headers.get("content-length", 0))

    with output_path.open("wb") as handle:
        with tqdm(total=total, unit="B", unit_scale=True, desc=output_path.name) as bar:
            for chunk in response.iter_content(chunk_size=1024 * 128):
                if chunk:
                    handle.write(chunk)
                    bar.update(len(chunk))


def build_record(piece: dict) -> dict:
    title = str(piece.get("title", "")).strip()
    filename = str(piece.get("filename", "")).strip()
    isrc = str(piece.get("isrc", "")).strip()
    download_url = f"{MP3_BASE_URL}/{quote(filename)}"
    safe_file_name = f"{slugify(title)}.mp3"

    return {
        "fileName": safe_file_name,
        "title": title,
        "artist": "Kevin MacLeod",
        "isrc": isrc,
        "bpm": int(piece["bpm"]) if str(piece.get("bpm", "")).isdigit() else None,
        "genre": GENRES.get(str(piece.get("genre", "")), str(piece.get("genre", ""))),
        "length": str(piece.get("length", "")),
        "feel": str(piece.get("feel", "")),
        "instruments": str(piece.get("instruments", "")),
        "description": str(piece.get("description", "")),
        "sourceUrl": f"{TRACK_PAGE_BASE_URL}{isrc}",
        "downloadUrl": download_url,
        "license": "CC BY 4.0",
        "attribution": f"{title} Kevin MacLeod (incompetech.com), licensed under Creative Commons: By Attribution 4.0 License",
        "environmentTags": [],
        "environmentTagSource": "not_computed",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Download selected Incompetech tracks from an ISRC text file.")
    parser.add_argument("--tracks", default="config/incompetech_tracks.txt", help="Text file containing Song Name | ISRC lines.")
    parser.add_argument("--output", default="data/raw_music", help="Directory where MP3 files will be stored.")
    parser.add_argument("--metadata-output", default="data/processed/source_metadata.json", help="Output metadata JSON path.")
    args = parser.parse_args()

    track_requests = read_track_requests(Path(args.tracks))
    pieces_by_isrc = {piece.get("isrc"): piece for piece in fetch_pieces()}
    output_dir = Path(args.output)
    records = []

    for request in track_requests:
        piece = pieces_by_isrc.get(request["isrc"])
        if not piece:
            print(f"[WARN] ISRC not found on Incompetech: {request['isrc']}")
            continue

        record = build_record(piece)
        download_file(record["downloadUrl"], output_dir / record["fileName"])
        records.append(record)

    metadata_output = Path(args.metadata_output)
    metadata_output.parent.mkdir(parents=True, exist_ok=True)
    metadata_output.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Downloaded or reused {len(records)} tracks. Metadata written to {metadata_output}")


if __name__ == "__main__":
    main()
