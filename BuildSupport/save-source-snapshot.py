#!/usr/bin/env python3
"""Archive working source, including submodules, without ignored build/game data."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

root = Path(__file__).resolve().parents[1]
destination = Path(sys.argv[1]).resolve()
destination.parent.mkdir(parents=True, exist_ok=True)
if destination.exists():
    raise SystemExit('Snapshot already exists; choose a new path.')


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


repositories = {}
files = []


def collect(repo):
    relative = str(repo.relative_to(root))
    repositories[relative] = {
        'head': git(repo, 'rev-parse', 'HEAD').decode().strip(),
        'status': git(repo, 'status', '--short').decode(),
    }
    for name in sorted(set(git(repo, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0'))):
        if not name:
            continue
        path = repo / name.decode()
        if path.is_symlink() or path.is_file():
            files.append(path)
        elif path.is_dir():
            # Directory entries from ls-files are submodule gitlinks.
            collect(path)


collect(root)
manifest = {'repositories': repositories, 'files': {}}
with tarfile.open(destination, 'w:gz', compresslevel=3) as archive:
    for path in files:
        name = str(path.relative_to(root))
        archive.add(path, arcname='boxer-work/' + name, recursive=False)
        manifest['files'][name] = (
            {'symlink': str(path.readlink())} if path.is_symlink()
            else {'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        )
manifest['archive_sha256'] = hashlib.sha256(destination.read_bytes()).hexdigest()
destination.with_suffix(destination.suffix + '.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Saved {len(files)} files and {len(repositories)} repository states: {destination}')
print('SHA-256:', manifest['archive_sha256'])
