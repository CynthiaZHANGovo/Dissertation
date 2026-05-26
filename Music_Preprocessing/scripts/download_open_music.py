from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlparse

import requests
from tqdm import tqdm


AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".oga"}
WIKIMEDIA_API_URL = "https://commons.wikimedia.org/w/api.php"


def slugify(value: str, fallback: str = "track") -> str:
    value = re.sub(r"[^a-zA-Z0-9._-]+", "_", value.strip()).strip("_")
    return value or fallback


def download_file(url: str, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists() and output_path.stat().st_size > 0:
        print(f"Using existing file: {output_path.name}")
        return
    response = requests.get(url, stream=True, timeout=60, headers={"User-Agent": "MusicPreprocessingDemo/1.0"})
    response.raise_for_status()
    total = int(response.headers.get("content-length", 0))

    with output_path.open("wb") as handle:
        with tqdm(total=total, unit="B", unit_scale=True, desc=output_path.name) as bar:
            for chunk in response.iter_content(chunk_size=1024 * 128):
                if chunk:
                    handle.write(chunk)
                    bar.update(len(chunk))


def extension_from_url(url: str) -> str:
    suffix = Path(urlparse(url).path).suffix.lower()
    return suffix if suffix in AUDIO_EXTENSIONS else ".mp3"


def download_direct_files(items: list[dict], output_dir: Path, records: list[dict]) -> None:
    for index, item in enumerate(items, start=1):
        url = item.get("url", "").strip()
        if not url:
            continue

        title = item.get("title") or f"direct_track_{index:03d}"
        file_name = f"{slugify(title)}{extension_from_url(url)}"
        output_path = output_dir / file_name
        try:
            download_file(url, output_path)
        except Exception as exc:
            print(f"[WARN] Skipped direct file {title}: {exc}")
            continue

        records.append(
            {
                "fileName": file_name,
                "title": title,
                "artist": item.get("artist", ""),
                "sourceUrl": url,
                "license": item.get("license", ""),
                "attribution": item.get("attribution", ""),
                "environmentTags": item.get("environmentTags", []),
            }
        )


def internet_archive_file_url(identifier: str, file_name: str) -> str:
    return f"https://archive.org/download/{identifier}/{file_name}"


def download_internet_archive_items(items: list[dict], output_dir: Path, records: list[dict]) -> None:
    for item in items:
        identifier = item.get("identifier", "").strip()
        if not identifier:
            continue

        metadata_url = f"https://archive.org/metadata/{identifier}"
        metadata_response = requests.get(metadata_url, timeout=60)
        metadata_response.raise_for_status()
        metadata = metadata_response.json()

        max_files = int(item.get("maxFiles", 5))
        audio_files = [
            file_info
            for file_info in metadata.get("files", [])
            if Path(file_info.get("name", "")).suffix.lower() in AUDIO_EXTENSIONS
        ][:max_files]

        for file_info in audio_files:
            file_name = file_info["name"]
            url = internet_archive_file_url(identifier, file_name)
            safe_name = f"{slugify(identifier)}_{slugify(Path(file_name).stem)}{Path(file_name).suffix.lower()}"
            output_path = output_dir / safe_name
            try:
                download_file(url, output_path)
            except Exception as exc:
                print(f"[WARN] Skipped Internet Archive file {file_name}: {exc}")
                continue

            records.append(
                {
                    "fileName": safe_name,
                    "title": Path(file_name).stem,
                    "artist": metadata.get("metadata", {}).get("creator", ""),
                    "sourceUrl": f"https://archive.org/details/{identifier}",
                    "license": item.get("license") or metadata.get("metadata", {}).get("licenseurl", ""),
                    "attribution": item.get("attribution", ""),
                    "environmentTags": item.get("environmentTags", []),
                }
            )


def wikimedia_file_info(page_title: str) -> dict:
    response = requests.get(
        WIKIMEDIA_API_URL,
        params={
            "action": "query",
            "format": "json",
            "prop": "imageinfo",
            "iiprop": "url|extmetadata",
            "titles": page_title,
        },
        timeout=60,
        headers={"User-Agent": "MusicPreprocessingDemo/1.0"},
    )
    response.raise_for_status()
    pages = response.json().get("query", {}).get("pages", {})
    page = next(iter(pages.values()))
    image_info = page.get("imageinfo", [{}])[0]
    if "url" not in image_info:
        raise RuntimeError(f"No download URL found for Wikimedia file: {page_title}")
    return image_info


def download_wikimedia_files(items: list[dict], output_dir: Path, records: list[dict]) -> None:
    for item in items:
        page_title = item.get("pageTitle", "").strip()
        if not page_title:
            continue

        info = wikimedia_file_info(page_title)
        url = info["url"]
        title = item.get("title") or page_title.replace("File:", "")
        suffix = extension_from_url(url)
        file_name = f"{slugify(title)}{suffix}"
        output_path = output_dir / file_name
        try:
            download_file(url, output_path)
        except Exception as exc:
            print(f"[WARN] Skipped Wikimedia file {page_title}: {exc}")
            continue

        source_url = f"https://commons.wikimedia.org/wiki/{page_title.replace(' ', '_')}"
        records.append(
            {
                "fileName": file_name,
                "title": title,
                "artist": item.get("artist", ""),
                "sourceUrl": source_url,
                "license": item.get("license", ""),
                "attribution": item.get("attribution", ""),
                "environmentTags": item.get("environmentTags", []),
            }
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Download open-license music declared in a JSON manifest.")
    parser.add_argument("--manifest", default="config/open_music_sources.json", help="Path to source manifest JSON.")
    parser.add_argument("--output", default="data/raw_music", help="Directory where audio files will be stored.")
    parser.add_argument("--metadata-output", default="data/processed/source_metadata.json", help="Downloaded source metadata JSON.")
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    output_dir = Path(args.output)
    metadata_output = Path(args.metadata_output)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    records: list[dict] = []

    download_direct_files(manifest.get("directFiles", []), output_dir, records)
    download_wikimedia_files(manifest.get("wikimediaFiles", []), output_dir, records)
    download_internet_archive_items(manifest.get("internetArchiveItems", []), output_dir, records)

    metadata_output.parent.mkdir(parents=True, exist_ok=True)
    metadata_output.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Downloaded {len(records)} files. Metadata written to {metadata_output}")


if __name__ == "__main__":
    main()
