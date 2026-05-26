from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

import librosa
import numpy as np
from mutagen import File as MutagenFile
from tqdm import tqdm


AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".oga"}


def slugify(value: str, fallback: str = "track") -> str:
    value = re.sub(r"[^a-zA-Z0-9._-]+", "_", value.strip()).strip("_")
    return value or fallback


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def discover_audio_files(input_dir: Path) -> list[Path]:
    return sorted(path for path in input_dir.rglob("*") if path.suffix.lower() in AUDIO_EXTENSIONS)


def estimate_bpm(path: Path, duration: float = 60.0) -> float | None:
    try:
        y, sr = librosa.load(path, mono=True, duration=duration)
        if y.size == 0:
            return None
        tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
        tempo_value = float(np.asarray(tempo).reshape(-1)[0])
        if math.isnan(tempo_value) or tempo_value <= 0:
            return None
        return round(tempo_value, 1)
    except Exception as exc:
        print(f"[WARN] BPM failed for {path.name}: {exc}")
        return None


def source_bpm(source: dict) -> float | None:
    value = source.get("bpm") or source.get("tempo")
    if value in (None, ""):
        return None
    try:
        return round(float(value), 1)
    except (TypeError, ValueError):
        return None


def read_audio_tags(path: Path) -> dict[str, str]:
    tags = {"title": path.stem, "artist": "Unknown"}
    try:
        audio = MutagenFile(path, easy=True)
        if audio and audio.tags:
            title = audio.tags.get("title", [None])[0]
            artist = audio.tags.get("artist", [None])[0]
            if title:
                tags["title"] = str(title)
            if artist:
                tags["artist"] = str(artist)
    except Exception:
        pass
    return tags


def normalize_scores(scores: np.ndarray) -> np.ndarray:
    shifted = scores - np.max(scores)
    exp_scores = np.exp(shifted)
    return exp_scores / exp_scores.sum()


class ClapScorer:
    def __init__(self, prompts: dict[str, str]) -> None:
        try:
            import laion_clap
        except ImportError as exc:
            raise RuntimeError("laion-clap is not installed. Install requirements or run without --use-clap.") from exc

        self.prompts = prompts
        self.labels = list(prompts.keys())
        self.model = laion_clap.CLAP_Module(enable_fusion=False)
        self.model.load_ckpt()
        self.text_embeddings = self.model.get_text_embedding(list(prompts.values()), use_tensor=False)

    def score(self, path: Path) -> dict[str, float]:
        audio_embedding = self.model.get_audio_embedding_from_filelist(x=[str(path)], use_tensor=False)
        similarities = np.matmul(audio_embedding, self.text_embeddings.T)[0]
        probabilities = normalize_scores(similarities)
        return {label: round(float(score), 4) for label, score in zip(self.labels, probabilities)}


def fallback_scores(prompts: dict[str, str]) -> dict[str, float]:
    return {}


def seeded_scores(prompts: dict[str, str], seed_tags: list[str]) -> dict[str, float]:
    scores = {label: 0.05 for label in prompts}
    weights = [0.7, 0.55, 0.4]
    for tag, weight in zip(seed_tags, weights):
        if tag in scores:
            scores[tag] = weight
    return scores


def top_tags(scores: dict[str, float], count: int) -> list[str]:
    return [label for label, _ in sorted(scores.items(), key=lambda item: item[1], reverse=True)[:count]]


def build_library(
    input_dir: Path,
    output_path: Path,
    prompts_path: Path,
    source_metadata_path: Path,
    use_clap: bool,
    top_k: int,
    bpm_duration: float,
    metadata_only: bool,
) -> None:
    prompts = load_json(prompts_path, {})
    source_records = load_json(source_metadata_path, [])
    source_by_file = {record.get("fileName"): record for record in source_records}
    if metadata_only:
        files = [input_dir / record["fileName"] for record in source_records if record.get("fileName")]
        files = [path for path in files if path.exists()]
    else:
        files = discover_audio_files(input_dir)

    scorer = None
    if use_clap:
        scorer = ClapScorer(prompts)

    library = []
    for index, path in enumerate(tqdm(files, desc="Processing music"), start=1):
        metadata = read_audio_tags(path)
        source = source_by_file.get(path.name, {})
        bpm = source_bpm(source) or estimate_bpm(path, duration=bpm_duration)

        if scorer:
            try:
                scores = scorer.score(path)
                tag_source = "clap"
            except Exception as exc:
                print(f"[WARN] CLAP failed for {path.name}: {exc}")
                scores = fallback_scores(prompts)
                tag_source = "not_computed"
        else:
            seed_tags = source.get("environmentTags", [])
            scores = seeded_scores(prompts, seed_tags) if seed_tags else fallback_scores(prompts)
            tag_source = source.get("environmentTagSource") or ("manual" if seed_tags else "not_computed")

        title = source.get("title") or metadata["title"]
        artist = source.get("artist") or metadata["artist"]
        track_id = f"track_{index:03d}_{slugify(path.stem).lower()}"

        library.append(
            {
                "id": track_id,
                "title": title,
                "artist": artist,
                "fileName": path.name,
                "bpm": bpm,
                "environmentTags": top_tags(scores, top_k) if scores else [],
                "scores": scores,
                "environmentTagSource": tag_source,
                "sourceUrl": source.get("sourceUrl", ""),
                "downloadUrl": source.get("downloadUrl", ""),
                "license": source.get("license", ""),
                "attribution": source.get("attribution", ""),
                "isrc": source.get("isrc", ""),
                "genre": source.get("genre", ""),
                "feel": source.get("feel", ""),
                "length": source.get("length", ""),
            }
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(library, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(library)} tracks to {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a Flutter-ready music_library.json from local audio files.")
    parser.add_argument("--input", default="data/raw_music", help="Input folder containing audio files.")
    parser.add_argument("--output", default="data/processed/music_library.json", help="Output JSON path.")
    parser.add_argument("--prompts", default="config/environment_prompts.json", help="Environment prompt config.")
    parser.add_argument("--source-metadata", default="data/processed/source_metadata.json", help="Optional source metadata JSON.")
    parser.add_argument("--use-clap", action="store_true", help="Enable CLAP audio-text environment scoring.")
    parser.add_argument("--top-k", type=int, default=2, help="Number of environment tags to keep per track.")
    parser.add_argument("--bpm-duration", type=float, default=60.0, help="Seconds from each track used for BPM estimation.")
    parser.add_argument("--metadata-only", action="store_true", help="Only process audio files listed in source metadata.")
    args = parser.parse_args()

    build_library(
        input_dir=Path(args.input),
        output_path=Path(args.output),
        prompts_path=Path(args.prompts),
        source_metadata_path=Path(args.source_metadata),
        use_clap=args.use_clap,
        top_k=args.top_k,
        bpm_duration=args.bpm_duration,
        metadata_only=args.metadata_only,
    )


if __name__ == "__main__":
    main()
