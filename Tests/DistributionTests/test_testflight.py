import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('testflight', Path(__file__).resolve().parents[2] / 'scripts/testflight.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class DistributionTests(unittest.TestCase):
    def test_identity_stays_stable_and_state_is_private(self):
        with tempfile.TemporaryDirectory() as directory:
            store = module.DistributionState(Path(directory))
            store.configure('ABCDEFGHIJ', 'dev.example.terminalkun2')
            store.configure('ABCDEFGHIJ', 'dev.example.terminalkun2')
            with self.assertRaises(ValueError):
                store.configure('0123456789', 'dev.example.terminalkun2')
            with self.assertRaises(ValueError):
                store.configure('ABCDEFGHIJ', 'dev.example.other')
            self.assertEqual(store.path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(store.directory.stat().st_mode & 0o777, 0o700)

    def test_build_numbers_are_reserved_before_build_and_never_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            store = module.DistributionState(Path(directory))
            store.configure('ABCDEFGHIJ', 'dev.example.terminalkun2')
            self.assertEqual(store.reserve_build(), 1)
            self.assertEqual(module.DistributionState(Path(directory)).reserve_build(), 2)
            self.assertEqual(store.reserve_build(), 3)

    def test_verified_archive_digest_changes_if_payload_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file = root / 'binary'
            file.write_bytes(b'original')
            original = module.archive_digest(root)
            self.assertEqual(original, module.archive_digest(root))
            file.write_bytes(b'altered')
            self.assertNotEqual(original, module.archive_digest(root))

    def test_invalid_configuration_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            store = module.DistributionState(Path(directory))
            for team, bundle in [('bad', 'dev.example.app'), ('ABCDEFGHIJ', 'a'), ('ABCDEFGHIJ', 'dev.example.a b')]:
                with self.assertRaises(ValueError):
                    store.configure(team, bundle)
            with self.assertRaises(ValueError):
                store.reserve_build()

    def test_export_is_internal_testflight_upload_with_automatic_signing(self):
        options = module.export_options('ABCDEFGHIJ')
        self.assertEqual(options['method'], 'app-store-connect')
        self.assertEqual(options['destination'], 'upload')
        self.assertEqual(options['teamID'], 'ABCDEFGHIJ')
        self.assertTrue(options['testFlightInternalTestingOnly'])
        self.assertTrue(options['manageAppVersionAndBuildNumber'])
        self.assertEqual(options['signingStyle'], 'automatic')
        self.assertNotIn('provisioningProfiles', options)

    def test_apple_tools_use_system_rsync_without_changing_user_environment(self):
        original = {'PATH': '/opt/homebrew/bin:/usr/bin', 'KEEP': 'yes'}
        result = module.apple_tool_environment(original)
        self.assertTrue(result['PATH'].startswith('/usr/bin:/bin:/usr/sbin:/sbin:'))
        self.assertIn('/opt/homebrew/bin', result['PATH'])
        self.assertEqual(original['PATH'], '/opt/homebrew/bin:/usr/bin')
        self.assertEqual(result['KEEP'], 'yes')

    def test_signing_metadata_rejects_development_and_identity_changes(self):
        entitlements = {'application-identifier': 'PREFIX1234.dev.example.terminalkun2',
                        'com.apple.developer.team-identifier': 'ABCDEFGHIJ', 'get-task-allow': False}
        identity = module.validate_signing_metadata(entitlements, 'ABCDEFGHIJ', 'dev.example.terminalkun2')
        self.assertEqual(identity, 'PREFIX1234.dev.example.terminalkun2')
        with self.assertRaises(ValueError):
            module.validate_signing_metadata(dict(entitlements, **{'get-task-allow': True}), 'ABCDEFGHIJ', 'dev.example.terminalkun2')
        with self.assertRaises(ValueError):
            module.validate_signing_metadata(entitlements, '0123456789', 'dev.example.terminalkun2')
        with self.assertRaises(ValueError):
            module.validate_signing_metadata(entitlements, 'ABCDEFGHIJ', 'dev.example.other')
        with self.assertRaises(ValueError):
            module.validate_signing_metadata(entitlements, 'ABCDEFGHIJ', 'dev.example.terminalkun2', 'OTHER12345.dev.example.terminalkun2')

    def test_archive_validation_rejects_wrong_identity_or_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory)
            app = archive / 'Products/Applications/TerminalKun2.app'
            app.mkdir(parents=True)
            info = {'CFBundleIdentifier': 'dev.example.terminalkun2', 'CFBundleVersion': '3'}
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {'Team': 'ABCDEFGHIJ'}}))
            module.validate_archive(archive, 'ABCDEFGHIJ', 'dev.example.terminalkun2', 3)
            with self.assertRaises(ValueError):
                module.validate_archive(archive, 'ABCDEFGHIJ', 'dev.example.other', 3)
            with self.assertRaises(ValueError):
                module.validate_archive(archive, 'ABCDEFGHIJ', 'dev.example.terminalkun2', 4)
            with self.assertRaises(ValueError):
                module.validate_archive(archive, '0123456789', 'dev.example.terminalkun2', 3)


if __name__ == '__main__':
    unittest.main()
