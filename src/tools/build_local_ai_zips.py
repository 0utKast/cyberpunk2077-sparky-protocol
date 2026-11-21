# -*- coding: utf-8 -*-
"""
build_local_ai_zips.py
======================
Builds standalone, cleanly filtered Local AI Bridge release ZIPs for Nexus Mods:
  - releases/optional/SPARKY_v2.0.0_LocalAI_Service_EN.zip
  - releases/optional/CHISPA_v2.0.0_LocalAI_Service_ES.zip
And verifies CRC integrity (`testzip()`) across all 7 v2.0.0 release ZIPs.

Usage:
  python mods/chispa_nc/tools/build_local_ai_zips.py
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parents[2]
OPT_DIR = REPO_ROOT / "releases" / "optional"
LICENSE_PATH = REPO_ROOT / "sparky_protocol" / "LICENSE"

FORBIDDEN_SUBSTRINGS = ("educa", "Mods_cyberpunk2077")
EXCLUDED_DIRS = {".venv", "__pycache__", "audio_out", "kokoro", "models_cache", "huggingface"}
EXCLUDED_FILES = {"voice_override.json", "user_audio_prefs.json", ".env"}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".sqlite", ".db", ".log", ".tmp", ".bak"}

TARGETS = [
    {
        "label": "EN",
        "src_dir": REPO_ROOT / "sparky_local_service_en",
        "pkg_name": "sparky_rt",
        "ref_wav": "sparky_ref_en.wav",
        "guide_name": "SPARKY_LOCAL_AI_GUIDE_EN.md",
        "zip_name": "SPARKY_v2.0.0_LocalAI_Service_EN.zip",
    },
    {
        "label": "ES",
        "src_dir": REPO_ROOT / "sparky_local_service",
        "pkg_name": "chispa_rt",
        "ref_wav": "chispa_ref_es.wav",
        "guide_name": "GUIA_CHISPA_IA_LOCAL_ES.md",
        "zip_name": "CHISPA_v2.0.0_LocalAI_Service_ES.zip",
    },
]


def _should_exclude(path: Path) -> bool:
    if any(part in EXCLUDED_DIRS for part in path.parts):
        return True
    if path.name in EXCLUDED_FILES:
        return True
    if path.suffix.lower() in EXCLUDED_SUFFIXES:
        return True
    return False


def _collect_service_files(spec: dict) -> list[tuple[Path, str]]:
    src_dir: Path = spec["src_dir"]
    pkg_name: str = spec["pkg_name"]
    ref_wav: str = spec["ref_wav"]
    guide_name: str = spec["guide_name"]
    prefix = src_dir.name

    assert src_dir.is_dir(), f"Missing service directory: {src_dir}"
    assert LICENSE_PATH.is_file(), f"Missing LICENSE file: {LICENSE_PATH}"

    items: list[tuple[Path, str]] = []
    # Root convenience files (LICENSE + Guide + folder itself)
    items.append((LICENSE_PATH, "LICENSE"))
    items.append((src_dir / guide_name, guide_name))

    # Top-level service files (.toml, .bat, .md, .ico)
    for f in sorted(src_dir.iterdir()):
        if not f.is_file() or _should_exclude(f):
            continue
        if f.suffix.lower() in {".toml", ".bat", ".md", ".ico"}:
            items.append((f, f"{prefix}/{f.name}"))

    # Package Python modules & 8 lore_kb/*.json files
    pkg_dir = src_dir / pkg_name
    for f in sorted(pkg_dir.rglob("*")):
        if not f.is_file() or _should_exclude(f):
            continue
        rel = f.relative_to(src_dir).as_posix()
        items.append((f, f"{prefix}/{rel}"))

    # Reference 24 kHz WAV only (exclude Kokoro downloads, user_override, etc.)
    ref_path = src_dir / "models" / ref_wav
    assert ref_path.is_file() and ref_path.stat().st_size > 10_000, f"Missing reference WAV: {ref_path}"
    items.append((ref_path, f"{prefix}/models/{ref_wav}"))

    # Verify exact lore card count == 162
    lore_files = sorted((pkg_dir / "lore_kb").glob("*.json"))
    assert len(lore_files) == 8, f"Expected 8 lore_kb files in {pkg_dir}, found {len(lore_files)}"
    total_cards = sum(len(json.loads(lf.read_text(encoding="utf-8"))) for lf in lore_files)
    assert total_cards == 162, f"Expected 162 lore cards in {pkg_dir}, found {total_cards}"

    # Verify zero forbidden developer/machine strings in text files
    for src_file, arcname in items:
        if src_file.suffix.lower() in {".py", ".bat", ".toml", ".md", ".json", ".txt"} or src_file.name == "LICENSE":
            text = src_file.read_text(encoding="utf-8", errors="replace")
            for bad in FORBIDDEN_SUBSTRINGS:
                assert bad not in text, f"Forbidden string '{bad}' found in {src_file} ({arcname})"

    return items


def build_local_ai_zips() -> list[Path]:
    OPT_DIR.mkdir(parents=True, exist_ok=True)
    built: list[Path] = []

    for spec in TARGETS:
        items = _collect_service_files(spec)
        out_zip = OPT_DIR / spec["zip_name"]
        with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for src_file, arcname in items:
                zf.write(src_file, arcname)
        with zipfile.ZipFile(out_zip, "r") as zf:
            bad = zf.testzip()
            assert bad is None, f"Corrupt entry '{bad}' inside {out_zip}"
            count = len(zf.namelist())
        mb = out_zip.stat().st_size / (1024 * 1024)
        print(f"[LOCAL AI ZIP OK] {out_zip.name} | {mb:.2f} MB | {count} files | 162 lore cards | clean")
        built.append(out_zip)

    return built


def verify_all_7_release_zips() -> None:
    expected = [
        REPO_ROOT / "releases" / "chispa_nc_en" / "SparkyProtocol_EN_v2.0.0.zip",
        REPO_ROOT / "releases" / "chispa_nc" / "ChispaNC_v2.0.0.zip",
        OPT_DIR / "SPARKY_v2.0.0_LocalAI_Service_EN.zip",
        OPT_DIR / "CHISPA_v2.0.0_LocalAI_Service_ES.zip",
        OPT_DIR / "SparkyProtocol_EN_FemaleVoicePack_v2.0.0.zip",
        OPT_DIR / "Chispa_LocalAI_FemaleVoicePack_ES_v2.0.0.zip",
        OPT_DIR / "ChispaNC_ClassicCampaignVoices_v2.0.0.zip",
    ]
    print("\n=== Verifying All 7 v2.0.0 Release Archives ===")
    for zp in expected:
        assert zp.is_file() and zp.stat().st_size > 1000, f"Missing release archive: {zp}"
        with zipfile.ZipFile(zp, "r") as zf:
            bad = zf.testzip()
            assert bad is None, f"Corrupt entry '{bad}' in {zp}"
            n = len(zf.namelist())
        mb = zp.stat().st_size / (1024 * 1024)
        print(f"  [OK] {zp.relative_to(REPO_ROOT)} | {mb:6.2f} MB | {n:3d} files | CRC OK")


def main() -> None:
    build_local_ai_zips()
    verify_all_7_release_zips()


if __name__ == "__main__":
    main()
