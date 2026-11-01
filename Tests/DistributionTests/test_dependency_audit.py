import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('dependency_audit', Path(__file__).resolve().parents[2] / 'scripts/check-dependencies.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class DependencyAuditTests(unittest.TestCase):
    def test_only_generated_nonexecutable_scheme_management_is_excluded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'Sources/Module.swift'
            source.parent.mkdir()
            source.write_text('public let value = 1')
            expected = module.vendor_files(root)
            metadata = root / '.swiftpm/xcode/xcuserdata/test.xcuserdatad/xcschemes/xcschememanagement.plist'
            metadata.parent.mkdir(parents=True)
            metadata.write_text('<plist><dict/></plist>')
            self.assertEqual(module.vendor_files(root), expected)
            script = metadata.parent / 'Unreviewed.xcscheme'
            script.write_text('unreviewed pre-build action')
            self.assertNotEqual(module.vendor_files(root), expected)

    def test_source_changes_still_change_reviewed_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'Package.swift'
            source.write_text('reviewed')
            expected = module.vendor_files(root)
            source.write_text('unreviewed')
            self.assertNotEqual(module.vendor_files(root), expected)


if __name__ == '__main__':
    unittest.main()
