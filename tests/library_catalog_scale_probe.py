#!/usr/bin/env python3
"""Seed a large local VLC Neo catalog and measure the real QML search path.

Run from the repository root:
  NEO_BUILD_DIR=build-fidelity2 python3 tests/library_catalog_scale_probe.py

This focused probe uses a temporary XDG data/config tree and the installed VLC
plugin. It does not touch a user's library or download media.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ROWS = int(os.environ.get("NEO_LIBRARY_PROBE_ROWS", "50000"))
BUILD = Path(os.environ.get("NEO_BUILD_DIR", ROOT / "build")).resolve()


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="neo-library-scale-") as temporary:
        sandbox = Path(temporary)
        data = sandbox / "data" / "vlc-neo" / "neo"
        data.mkdir(parents=True)
        database = sqlite3.connect(data / "library.sqlite")
        database.executescript(
            "PRAGMA journal_mode=WAL;"
            "CREATE TABLE roots(path TEXT PRIMARY KEY);"
            "CREATE TABLE media(path TEXT PRIMARY KEY,root TEXT NOT NULL,title TEXT NOT NULL,"
            "artist TEXT NOT NULL,album TEXT NOT NULL,genre TEXT NOT NULL,kind TEXT NOT NULL,"
            "duration INTEGER NOT NULL,size INTEGER NOT NULL,modified INTEGER NOT NULL,artwork TEXT NOT NULL);"
            "CREATE INDEX media_artist_album ON media(artist,album);"
            "CREATE INDEX media_genre ON media(genre);"
            "CREATE INDEX media_root ON media(root);"
        )
        values = []
        for index in range(ROWS):
            title = "Needle unique song" if index == ROWS - 1 else f"Track {index:06d}"
            values.append((
                f"/probe/music/{index:06d}.flac", "/probe/music", title,
                f"Artist {index % 700:04d}", f"Album {index % 4000:04d}",
                f"Genre {index % 20:02d}", "audio", 180, 1024, index, "",
            ))
        database.executemany(
            "INSERT INTO media VALUES(?,?,?,?,?,?,?,?,?,?,?)", values
        )
        seeded_rows = database.execute("SELECT COUNT(*) FROM media").fetchone()[0]
        database.commit()
        database.close()
        if seeded_rows != ROWS:
            raise RuntimeError(f"seeded {seeded_rows} rows, expected {ROWS}")

        steps = (
            "1000:'catalogBefore=' + mediaLibrary.databasePath + '; view=' + mediaLibrary.model.view"
            " + '; count=' + mediaLibrary.model.itemCount() + '; loading=' + mediaLibrary.model.loading"
            "|+100:var setterStarted=Date.now(); win.objectName=''; "
            "mediaLibrary.model.loadingChanged.connect(function(){ if (!mediaLibrary.model.loading) "
            "win.objectName='settled=' + (Date.now()-setterStarted) + '; count=' + "
            "mediaLibrary.model.itemCount() + '; title=' + mediaLibrary.model.itemAt(0).title }); "
            "mediaLibrary.model.search='NEO_PROBE_NO_MATCH'; 'catalogSetterMs=' + "
            "(Date.now()-setterStarted) + '; loading=' + mediaLibrary.model.loading"
            "|+10:var replacementStarted=Date.now(); var wasLoading=mediaLibrary.model.loading; "
            "mediaLibrary.model.search='NEEDLE'; 'catalogReplacement=' + wasLoading + '/' + "
            "mediaLibrary.model.loading + '; setterMs=' + (Date.now()-replacementStarted)"
            "|+2500:'catalogSearchResult=' + win.objectName + '; loading=' + "
            "mediaLibrary.model.loading + '; stale=' + mediaLibrary.model.stale"
            "|+100:quit"
        )
        environment = os.environ.copy()
        environment.update({
            "NEO_BUILD_DIR": str(BUILD),
            "NEO_SANDBOX": str(sandbox),
            "NEO_TIMEOUT": "30",
        })
        result = subprocess.run(
            [str(ROOT / "scripts" / "run-offscreen.sh"), steps],
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=35,
            check=False,
        )
        before_match = re.search(r"catalogBefore=.*?count=(\d+); loading=(true|false)", result.stdout)
        setter_match = re.search(r"catalogSetterMs=(\d+); loading=(true|false)", result.stdout)
        replacement_match = re.search(r"catalogReplacement=(true|false)/(true|false); setterMs=(\d+)", result.stdout)
        match = re.search(
            r"catalogSearchResult=settled=(\d+); count=(\d+); title=([^;\r\n]+); "
            r"loading=(true|false); stale=(true|false)", result.stdout
        )
        if result.returncode != 0 or not match:
            print(result.stdout[-6000:])
            return result.returncode or 1
        elapsed_ms, count, title, loading, stale = match.groups()
        initial_count = int(before_match.group(1)) if before_match else -1
        initial_loading = before_match.group(2) if before_match else "missing"
        setter_ms = int(setter_match.group(1)) if setter_match else -1
        replacement_during_load = bool(replacement_match and replacement_match.group(1) == "true")
        replacement_loading = replacement_match.group(2) if replacement_match else "missing"
        if (initial_count != ROWS or initial_loading != "false" or setter_ms > 16
                or not replacement_during_load or replacement_loading != "true"
                or loading != "false" or stale != "false" or int(count) != 1
                or title != "Needle unique song"):
            print("Unexpected async search result: "
                  f"initial={initial_count}/{initial_loading}, setter={setter_ms}ms, "
                  f"replacementDuringLoad={replacement_during_load}/{replacement_loading}, "
                  f"elapsed={elapsed_ms}ms, loading={loading}, stale={stale}, "
                  f"count={count}, title={title!r}")
            print(result.stdout[-3000:])
            return 1
        print(f"catalogRows={ROWS}; matchingRows={count}; setterMs={setter_ms}; "
              f"latestSearchSettledMs={elapsed_ms}; replacedWhileLoading=true")
        print("probe=pass (replacement search supersedes an in-flight query and exposes the exact final row)")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
