#!/usr/bin/env python3
"""Exercise release assembly boundaries using generated data, never private artwork."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ASSEMBLER = Path(__file__).with_name('assemble-asset-release.py')
MODS = ['base', 'elevated-rails', 'quality', 'recycler', 'space-age']

class AssetAssemblyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fb-native-asset-assembly-test-')
        self.root = Path(self.temporary.name)
        self.sprites = self.root / 'sprites'
        self.sprites.mkdir()
        self.prototype = self.root / 'prototype-map.json'
        self.destination = self.root / 'release'
        (self.sprites / 'manifest.json').write_text(json.dumps(dict(schema=2, gameVersion='2.1.23', mods=MODS)))
        self.prototype.write_text(json.dumps(dict(schema=1, gameVersion='2.1.23', mods={mod: '2.1.23' for mod in MODS})))

    def tearDown(self):
        self.temporary.cleanup()

    def assemble(self):
        return subprocess.run([sys.executable, str(ASSEMBLER), '--sprites', str(self.sprites), '--prototype-map', str(self.prototype),
            '--destination', str(self.destination), '--id', 'test-release'], capture_output=True)

    def test_complete_inventory_and_existing_destination_preservation(self):
        self.assertEqual(self.assemble().returncode, 0)
        descriptor = json.loads((self.destination / 'release.json').read_bytes())
        fields = {key: descriptor[key] for key in ['schema', 'profile', 'provenance', 'files']}
        identity_bytes = (json.dumps(fields, sort_keys=True, separators=(',', ':'), ensure_ascii=False) + '\n').encode()
        self.assertEqual(descriptor['identity'], hashlib.sha256(identity_bytes).hexdigest())
        for entry in descriptor['files']:
            data = (self.destination / entry['path']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), entry['sha256'])
        before = (self.destination / 'release.json').read_bytes()
        self.assertNotEqual(self.assemble().returncode, 0)
        self.assertEqual((self.destination / 'release.json').read_bytes(), before)

    def test_symlink_escape_is_refused_before_destination_creation(self):
        (self.sprites / 'escape').symlink_to(self.prototype)
        self.assertNotEqual(self.assemble().returncode, 0)
        self.assertFalse(self.destination.exists())

    def test_shared_file_is_refused_before_destination_creation(self):
        os.link(self.prototype, self.sprites / 'shared.json')
        self.assertNotEqual(self.assemble().returncode, 0)
        self.assertFalse(self.destination.exists())

    def test_oversized_prototype_is_refused_before_reading_or_copying(self):
        with self.prototype.open('wb') as stream:
            stream.truncate(17 * 1024**2)
        self.assertNotEqual(self.assemble().returncode, 0)
        self.assertFalse(self.destination.exists())

if __name__ == '__main__':
    unittest.main()
