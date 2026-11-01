#!/usr/bin/env python3
"""Reject unaudited revisions and enforce a minimum published age."""
import datetime
import json
import hashlib
from pathlib import Path


def vendor_files(directory):
    files = {}
    for path in sorted(directory.rglob('*')):
        relative = path.relative_to(directory)
        # Xcode creates this nonexecutable UI preference when opening a local package.
        if relative.match('.swiftpm/xcode/xcuserdata/*.xcuserdatad/xcschemes/xcschememanagement.plist'):
            continue
        if path.is_file():
            files[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
    return files


def main():
    root = Path(__file__).resolve().parent.parent
    audit = json.loads((root / 'docs/dependency-audit.json').read_text())
    lock = json.loads((root / 'Package.resolved').read_text())
    now = datetime.datetime.now(datetime.timezone.utc)
    for pin in lock['pins']:
        entry = audit[pin['identity']]
        assert entry['revision'] == pin['state']['revision'], f"Unaudited revision: {pin['identity']}"
        assert entry['version'] == pin['state']['version']
        assert entry['review'] and 'Pending' not in entry['review']
        published = datetime.datetime.fromisoformat(entry['publishedAt'].replace('Z', '+00:00'))
        assert now - published >= datetime.timedelta(hours=24), f"Dependency too new: {pin['identity']}"
    print(f"Verified {len(lock['pins'])} reviewed, pinned dependencies older than 24 hours")

    vendors = json.loads((root / 'docs/vendor-audit.json').read_text())
    for name, entry in vendors.items():
        published = datetime.datetime.fromisoformat(entry['publishedAt'].replace('Z', '+00:00'))
        assert now - published >= datetime.timedelta(hours=24), f"Vendored dependency too new: {name}"
        assert entry['review']
        directory = root / 'Vendor' / name
        actual = vendor_files(directory)
        assert actual == entry['files'], f"Unreviewed vendored changes: {name}; review and update the audit"
    print(f"Verified all file hashes for {len(vendors)} reviewed vendored dependencies")


if __name__ == '__main__':
    main()
