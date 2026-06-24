#!/usr/bin/env python3
"""
download_ontologies.py
----------------------
Reads xxx.json and downloads each ontology from its ontology_purl,
saving it as <id>.<ext> in the output directory.
 
- HTTP/HTTPS URLs  → downloaded via requests
- file:// URLs     → copied from the local path, saved as <id>.<ext>
 
Usage:
    python download_ontologies.py [json_file] [output_dir]
 
Defaults:
    json_file  : xxx.json
    output_dir : ontologies/
"""
 
import argparse
import json
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import url2pathname
 
try:
    import requests
except ImportError:
    sys.exit("ERROR: 'requests' is not installed. Run: pip install requests")
 
 
# ── config ────────────────────────────────────────────────────────────────────
 
DEFAULT_JSON_FILE   = Path("ontologies.json")
DEFAULT_OUTPUT_DIR  = Path("ontologies")
DEFAULT_ONTOLOGY_ACTION_COUNTS  = Path("ontology_action_counts.json")
 
DEFAULT_CONNECT_TIMEOUT = 30     # seconds to establish the connection
DEFAULT_READ_TIMEOUT    = 60     # seconds of inactivity between chunks
DEFAULT_TOTAL_TIMEOUT   = 600    # hard cap on the entire download (10 min per file)
DEFAULT_RETRIES         = 3
DEFAULT_RETRY_DELAY     = 5      # seconds between retries
HEADERS     = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": (
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "application/rdf+xml;q=0.8,*/*;q=0.7"
    ),
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate, br",
    "Connection": "keep-alive",
}
KNOWN_EXTS  = {".owl", ".ttl", ".rdf", ".obo", ".xml", ".n3", ".nt", ".jsonld", ".json", ".csv"}
 
 
# ── session (shared across all requests) ─────────────────────────────────────
 
SESSION = requests.Session()
SESSION.headers.update(HEADERS)
 
 
# ── helpers ───────────────────────────────────────────────────────────────────
 
def get_extension(url: str) -> str:
    """Derive a file extension from the URL; fall back to .owl."""
    path = urlparse(url).path.rstrip("/")
    suffix = Path(path).suffix.lower()
    return suffix if suffix in KNOWN_EXTS else ".owl"
 
 
def download_http(
    url: str,
    dest: Path,
    connect_timeout: int,
    read_timeout: int,
    total_timeout: int,
    retries: int,
    retry_delay: int,
) -> bool:
    """Download an HTTP/HTTPS URL to dest. Returns True on success.

    Uses streaming so that TOTAL_TIMEOUT is enforced over the entire download,
    not just per-chunk inactivity. Without this a server that trickles data
    one byte at a time would never trigger the read timeout.
    """
    for attempt in range(1, retries + 1):
        try:
            deadline = time.monotonic() + total_timeout
            response = SESSION.get(
                url,
                timeout=(connect_timeout, read_timeout),
                allow_redirects=True,
                stream=True,
            )
            response.raise_for_status()
            with dest.open("wb") as fh:
                for chunk in response.iter_content(chunk_size=65536):
                    if time.monotonic() > deadline:
                        raise requests.Timeout(
                            f"Total download exceeded {total_timeout}s"
                        )
                    if chunk:
                        fh.write(chunk)
            if dest.stat().st_size == 0:
                dest.unlink()
                print(f"        ✗ Empty response")
                return False
            size_kb = dest.stat().st_size / 1024
            print(f"        ✓ OK ({size_kb:.1f} KB)")
            return True
        except requests.RequestException as e:
            dest.unlink(missing_ok=True)
            print(f"        ✗ Attempt {attempt}/{retries} failed: {e}")
            if attempt < retries:
                time.sleep(retry_delay)
    return False
 
 
def copy_file(purl: str, dest: Path) -> bool:
    """Copy a file:// URL to dest. Returns True on success."""
    local_path = Path(url2pathname(urlparse(purl).path))
    if not local_path.exists():
        print(f"        ✗ Local file not found: {local_path}")
        return False
    shutil.copy2(local_path, dest)
    size_kb = dest.stat().st_size / 1024
    print(f"        ✓ Copied ({size_kb:.1f} KB)")
    return True
 
 
# ── main ──────────────────────────────────────────────────────────────────────
 
def main():
    parser = argparse.ArgumentParser(
        description="Read xxx.json and download each ontology from its ontology_purl."
    )
    parser.add_argument(
        "--json-file",
        type=Path,
        default=DEFAULT_JSON_FILE,
        help="Input JSON file (default: %(default)s).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Output directory (default: %(default)s).",
    )
    parser.add_argument(
        "--ontology-action-counts",
        type=Path,
        default=DEFAULT_ONTOLOGY_ACTION_COUNTS,
        help="Ontology action counts JSON file (default: %(default)s). Without using this parameter or by pointing to a file with an empty json object, all ontologies will be downloaded.",
    )
    parser.add_argument(
        "--connect-timeout",
        type=int,
        default=DEFAULT_CONNECT_TIMEOUT,
        help="Seconds to establish the connection (default: %(default)s).",
    )
    parser.add_argument(
        "--read-timeout",
        type=int,
        default=DEFAULT_READ_TIMEOUT,
        help="Seconds of inactivity between chunks (default: %(default)s).",
    )
    parser.add_argument(
        "--total-timeout",
        type=int,
        default=DEFAULT_TOTAL_TIMEOUT,
        help="Hard cap on the entire download per file in seconds (default: %(default)s).",
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=DEFAULT_RETRIES,
        help="Number of retries for failed downloads (default: %(default)s).",
    )
    parser.add_argument(
        "--retry-delay",
        type=int,
        default=DEFAULT_RETRY_DELAY,
        help="Seconds between retries (default: %(default)s).",
    )
    args = parser.parse_args()

    json_file = args.json_file
    output_dir = args.output_dir
    ontology_action_counts = args.ontology_action_counts
    connect_timeout = args.connect_timeout
    read_timeout = args.read_timeout
    total_timeout = args.total_timeout
    retries = args.retries
    retry_delay = args.retry_delay

    if not json_file.exists():
        sys.exit(f"ERROR: JSON file not found: {json_file}")
 
    output_dir.mkdir(parents=True, exist_ok=True)
 
    with json_file.open(encoding="utf-8") as f:
        data = json.load(f)

    counted_ontologies = set()
    if ontology_action_counts.exists():
        with ontology_action_counts.open(encoding="utf-8") as oac:
            counted_ontologies = set(json.load(oac).keys())
    else:
        counted_ontologies = set()
 
    ontologies = data.get("ontologies", [])
    filtered_ontologies = ontologies
    if len(counted_ontologies) != 0:
        filtered_ontologies = [item for item in ontologies if item.get("id") in counted_ontologies]
    else: 
        filtered_ontologies = ontologies
 
    print(f"Reading : {json_file}")
    print(f"Output  : {output_dir}/")
    print(f"Entries : {len(ontologies)}")
    print("─" * 60)
    skipped = set()
    failed = set()
    downloaded = set()
    total = set()
 
    for entry in filtered_ontologies:
        oid  = entry.get("id", "").strip()
        total.add(oid)
        purl = (entry.get("ontology_purl") or "").strip()
 
        if not oid or not purl:
            print(f"[SKIP ] ({total}) id={oid!r} – missing id or ontology_purl")
            skipped.add(oid)
            continue
 
        ext      = get_extension(purl)
        now = datetime.now()
        date_time = now.strftime("%d-%m-%Y--%H-%M-%S")
        out_file = output_dir / f"{oid}_{date_time}{ext}"
 
        # Resume-safe: skip already downloaded files
        if out_file.exists() and out_file.stat().st_size > 0:
            print(f"[EXIST] ({total}) {oid} → {out_file.name} (already present)")
            skipped.add(oid)
            continue
 
        scheme = urlparse(purl).scheme.lower()
 
        print(f"[DOWN ] ({len(total)}) {oid}")
        print(f"        URL : {purl}")
        print(f"        File: {out_file}")
 
        if scheme in ("http", "https"):
            ok = download_http(
                purl,
                out_file,
                connect_timeout,
                read_timeout,
                total_timeout,
                retries,
                retry_delay,
            )
        elif scheme == "file":
            ok = copy_file(purl, out_file)
        else:
            print(f"        ✗ Unsupported scheme: {scheme!r}")
            ok = False
 
        if ok:
            downloaded.add(oid)
        else:
            out_file.unlink(missing_ok=True)
            failed.add(oid)
 
    print()
    print("═" * 60)
    print(f" Done.")
    print(f"  Total entries : {len(total)}")
    print(f"  Downloaded    : {len(downloaded)}")
    print(f"  Skipped       : {skipped}  (already present or no URL)")
    print(f"  Failed        : {failed}")
    print("═" * 60)
 
 
if __name__ == "__main__":
    main()
