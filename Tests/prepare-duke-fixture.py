#!/usr/bin/env python3
"""Copy a Duke gamebox (including CD media) and optionally its current config."""
import argparse
import pathlib
import plistlib
import shutil
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("gamebox", type=pathlib.Path)
parser.add_argument("--config", type=pathlib.Path, help="DUKE3D.CFG from the current game-state overlay")
args = parser.parse_args()
target = pathlib.Path(__file__).resolve().parent.parent / "build/Duke Benchmark.boxer"
if target.exists():
    raise SystemExit(f"Fixture already exists; preserved: {target}")
if not (args.gamebox / "C.harddisk/DUKE3D/DUKE3D.EXE").is_file():
    raise SystemExit("Expected C.harddisk/DUKE3D/DUKE3D.EXE in the supplied gamebox")
shutil.copytree(args.gamebox, target)
info_path = target / "Game Info.plist"
info = plistlib.loads(info_path.read_bytes())
info.update(BXGameIdentifier=str(uuid.uuid4()).upper(), BXGameIdentifierType=1,
            BXDefaultProgramPath="C.harddisk/DUKE3D/DUKE3D.EXE")
info_path.write_bytes(plistlib.dumps(info))
(target / "DOSBox Preferences.conf").write_text("[cpu]\ncore=dynamic\ncycles=max\n")
if args.config:
    shutil.copy2(args.config, target / "C.harddisk/DUKE3D/DUKE3D.CFG")
print(f"Created disposable fixture: {target}")
