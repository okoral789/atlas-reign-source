"""Read completed owner performance runs from the private Roblox experience."""
import argparse
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-file", type=Path, required=True)
    key = parser.parse_args().key_file.read_text(encoding="utf-8-sig").strip()
    base = "https://apis.roblox.com/cloud/v2/universes/10774039150/data-stores/AtlasPlaytestV1/scopes/global/entries/"
    reports = []
    for device in ("phone", "desktop"):
        for mode in ("online", "solo"):
            name = f"{device}-{mode}"
            try:
                with urlopen(Request(base + name, headers={"x-api-key": key}), timeout=10) as response:
                    reports.append(json.load(response)["value"])
            except HTTPError as exc:
                if exc.code != 404:
                    raise SystemExit(f"{name}: Roblox HTTP {exc.code}") from None
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
