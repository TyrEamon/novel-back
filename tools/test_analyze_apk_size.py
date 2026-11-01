import tempfile
from pathlib import Path
import unittest
import zipfile

from analyze_apk_size import analyze


class ApkSizeReportTest(unittest.TestCase):
    def test_reports_archive_bytes_categories_and_expanded_content(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixture.apk'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libapp.so', b'A' * 100)
                archive.writestr('assets/flutter_assets/fonts/reader.otf', b'B' * 80,
                                 compress_type=zipfile.ZIP_DEFLATED)
                archive.writestr('classes.dex', b'DEX' * 20)
                archive.writestr('resources.arsc', b'R' * 40)
                archive.writestr('assets/flutter_assets/shaders/glass.frag', b'S' * 30)
            report = analyze(path)
            self.assertEqual(report['apk_bytes'], path.stat().st_size)
            self.assertEqual(report['expanded_entry_bytes'], 310)
            self.assertEqual(report['groups']['native/arm64-v8a']['expanded_bytes'], 100)
            self.assertEqual(report['groups']['fonts']['expanded_bytes'], 80)
            self.assertEqual(report['groups']['android_code']['expanded_bytes'], 60)
            self.assertGreater(report['archive_overhead_bytes'], 0)


if __name__ == '__main__':
    unittest.main()
