#!/usr/bin/env python3
"""Reject unaudited revisions and enforce a minimum published age."""
import datetime
import json
from pathlib import Path

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
