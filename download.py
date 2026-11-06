"""Download raw CMS datasets into data/raw/.

Steps:
  1. Resolve current download URLs from the CMS catalogs and save them to
     config/sources.json (data.cms.gov/data.json, the Open Payments metastore,
     and the Provider Data Catalog metastore).
  2. Stream each file to data/raw/ in chunks, skipping files that already exist.
     Open Payments zips are unzipped and only the general payments CSV is kept.
  3. Append each file's size and download time to run_log.md.

Usage:
  python download.py                 # resolve URLs, then download
  python download.py --no-refresh    # reuse config/sources.json as-is
  python download.py --only phys_svc_2024 op_gnrl_2025
"""

import argparse
import json
import shutil
import sys
import time
import urllib.request
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW_DIR = ROOT / "data" / "raw"
SOURCES = ROOT / "config" / "sources.json"
RUN_LOG = ROOT / "run_log.md"

CHUNK = 8 * 1024 * 1024  # 8 MB
HEADERS = {"User-Agent": "ortho-targeting-download/1.0 (python urllib)"}

DATA_JSON = "https://data.cms.gov/data.json"
OP_METASTORE = "https://openpaymentsdata.cms.gov/api/1/metastore/schemas/dataset/items"
PDC_METASTORE = "https://data.cms.gov/provider-data/api/1/metastore/schemas/dataset/items/{id}"

PHYS_SVC_YEARS = range(2020, 2025)
PHYS_PROV_YEARS = [2024]
OP_YEARS = range(2021, 2026)
PDC_DATASETS = {
    "pdc_clinicians": ("mj5m-pzi6", "Doctors and Clinicians National Downloadable File"),
    "pdc_facility_affil": ("27ea-46a8", "Facility Affiliation Data"),
    "pdc_hospital_info": ("xubh-q36u", "Hospital General Information"),
}


# ---------- URL resolution ----------

def fetch_json(url):
    req = urllib.request.Request(url, headers={**HEADERS, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def resolve_medicare(entries):
    """Find by-Provider-and-Service and by-Provider CSVs in data.cms.gov/data.json."""
    catalog = fetch_json(DATA_JSON)
    wanted = {
        "Medicare Physician & Other Practitioners - by Provider and Service": ("phys_svc", PHYS_SVC_YEARS),
        "Medicare Physician & Other Practitioners - by Provider": ("phys_prov", PHYS_PROV_YEARS),
    }
    for ds in catalog["dataset"]:
        # Titles carry a release-date suffix, e.g. "... by Provider : 2024-12-01"
        base_title = ds["title"].split(" : ")[0].strip()
        if base_title not in wanted:
            continue
        prefix, years = wanted[base_title]
        for dist in ds.get("distribution", []):
            url = dist.get("downloadURL")
            temporal = dist.get("temporal") or []
            if not url or not url.lower().endswith(".csv") or not temporal:
                continue
            start = temporal[0]["startDate"] if isinstance(temporal, list) else temporal.split("/")[0]
            year = int(start[:4])
            if year in years:
                entries[f"{prefix}_{year}"] = {
                    "dataset": base_title,
                    "release": ds["title"],
                    "data_year": year,
                    "catalog": DATA_JSON,
                    "url": url,
                    "kind": "csv",
                }


def resolve_open_payments(entries):
    """General Payment Data per program year. The catalog lists the CSV; the
    full program-year zip sits next to it (PGYRyyyy_Pmmddyyyy_mmddyyyy.zip)."""
    for ds in fetch_json(OP_METASTORE):
        title = ds.get("title", "")
        if not title.endswith("General Payment Data"):
            continue
        year = int(title.split()[0])
        if year not in OP_YEARS:
            continue
        csv_url = ds["distribution"][0]["downloadURL"]
        folder = csv_url.rsplit("/", 2)[0] + "/" + csv_url.rsplit("/", 2)[1]
        entries[f"op_gnrl_{year}"] = {
            "dataset": title,
            "program_year": year,
            "catalog": OP_METASTORE,
            "modified": ds.get("modified"),
            "url": folder + ".zip",
            "csv_url": csv_url,
            "zip_member": csv_url.rsplit("/", 1)[1],
            "kind": "zip",
        }


def resolve_pdc(entries, old):
    for name, (ds_id, title) in PDC_DATASETS.items():
        meta_url = PDC_METASTORE.format(id=ds_id)
        entry = {"dataset": title, "dataset_id": ds_id, "catalog": meta_url, "kind": "csv"}
        try:
            ds = fetch_json(meta_url)
            entry.update(dataset=ds["title"], modified=ds.get("modified"),
                         url=ds["distribution"][0]["downloadURL"])
        except Exception as e:  # catalog blocks some clients (HTTP 403)
            prev = old.get(name, {})
            entry["url"] = prev.get("url")  # keep a URL added by hand, if any
            entry["resolve_error"] = str(e)
            print(f"  ! could not resolve {name}: {e}")
        entries[name] = entry


def refresh_sources():
    old = json.loads(SOURCES.read_text(encoding="utf-8")).get("files", {}) if SOURCES.exists() else {}
    entries = {}
    print("Resolving URLs from data.cms.gov/data.json ...")
    resolve_medicare(entries)
    print("Resolving URLs from the Open Payments catalog ...")
    resolve_open_payments(entries)
    print("Resolving URLs from the Provider Data Catalog ...")
    resolve_pdc(entries, old)
    sources = {"resolved_at": datetime.now().isoformat(timespec="seconds"),
               "files": dict(sorted(entries.items()))}
    SOURCES.parent.mkdir(parents=True, exist_ok=True)
    SOURCES.write_text(json.dumps(sources, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(entries)} sources to {SOURCES.relative_to(ROOT)}")
    return sources


# ---------- downloading ----------

def stream_to(url, dest):
    """Stream url to dest via a .part file. Returns bytes downloaded."""
    part = dest.with_name(dest.name + ".part")
    req = urllib.request.Request(url, headers=HEADERS)
    done = 0
    last = time.time()
    with urllib.request.urlopen(req, timeout=300) as r, open(part, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        while chunk := r.read(CHUNK):
            f.write(chunk)
            done += len(chunk)
            if time.time() - last > 15:
                pct = f" ({done / total:.0%})" if total else ""
                print(f"    {dest.name}: {done / 1e9:.2f} GB{pct}", flush=True)
                last = time.time()
    if total and done != total:
        raise IOError(f"incomplete download: {done} of {total} bytes")
    part.replace(dest)
    return done


def extract_member(zip_path, member, dest):
    """Copy only the general payments CSV out of the zip, then delete the zip."""
    part = dest.with_name(dest.name + ".part")
    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
        if member not in names:  # fall back to the OP_DTL_GNRL_*.csv file
            matches = [n for n in names if Path(n).name.startswith("OP_DTL_GNRL_") and n.endswith(".csv")]
            if len(matches) != 1:
                raise ValueError(f"general payments CSV not found in zip: {names}")
            member = matches[0]
        with z.open(member) as src, open(part, "wb") as out:
            shutil.copyfileobj(src, out, CHUNK)
    part.replace(dest)
    zip_path.unlink()


def fmt_size(n):
    return f"{n / 1e9:.2f} GB" if n >= 1e9 else f"{n / 1e6:.1f} MB"


def fmt_time(s):
    return f"{int(s // 60)}m {s % 60:04.1f}s" if s >= 60 else f"{s:.1f}s"


def download_all(sources, only=None):
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, src in sources["files"].items():
        if only and name not in only:
            continue
        dest = RAW_DIR / f"{name}.csv"
        if dest.exists():
            print(f"- {dest.name}: exists, skipping")
            rows.append((dest.name, fmt_size(dest.stat().st_size), "-", "skipped (exists)"))
            continue
        if not src.get("url"):
            print(f"- {dest.name}: no URL in sources.json, skipping")
            rows.append((dest.name, "-", "-", "FAILED: no URL (catalog blocked)"))
            continue

        print(f"- {dest.name}: downloading {src['url']}", flush=True)
        t0 = time.time()
        try:
            if src["kind"] == "zip":
                zip_path = RAW_DIR / f"{name}.zip"
                if not zip_path.exists():
                    stream_to(src["url"], zip_path)
                t_dl = time.time() - t0
                print(f"    unzipping {src.get('zip_member')}", flush=True)
                extract_member(zip_path, src.get("zip_member"), dest)
                note = f"ok (zip download {fmt_time(t_dl)}, unzipped general payments CSV)"
            else:
                stream_to(src["url"], dest)
                note = "ok"
            secs = time.time() - t0
            size = dest.stat().st_size
            print(f"    done: {fmt_size(size)} in {fmt_time(secs)}")
            rows.append((dest.name, fmt_size(size), fmt_time(secs), note))
        except Exception as e:
            print(f"    FAILED: {e}")
            rows.append((dest.name, "-", fmt_time(time.time() - t0), f"FAILED: {e}"))
    return rows


def write_log(rows):
    new = not RUN_LOG.exists()
    with open(RUN_LOG, "a", encoding="utf-8") as f:
        if new:
            f.write("# Download run log\n")
        f.write(f"\n## Run {datetime.now():%Y-%m-%d %H:%M}\n\n")
        f.write("| File | Size | Download time | Status |\n|---|---|---|---|\n")
        for r in rows:
            f.write("| " + " | ".join(str(c).replace("|", "/") for c in r) + " |\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-refresh", action="store_true", help="use config/sources.json without re-resolving URLs")
    ap.add_argument("--only", nargs="+", help="only these file names (e.g. phys_svc_2024)")
    args = ap.parse_args()

    if args.no_refresh and SOURCES.exists():
        sources = json.loads(SOURCES.read_text(encoding="utf-8"))
    else:
        sources = refresh_sources()

    rows = download_all(sources, set(args.only) if args.only else None)
    write_log(rows)
    failed = [r for r in rows if r[3].startswith("FAILED")]
    print(f"\nLogged {len(rows)} files to {RUN_LOG.name}; {len(failed)} failed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
