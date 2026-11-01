import importlib.util
from pathlib import Path
import tempfile
import unittest
from zipfile import ZipFile

spec = importlib.util.spec_from_file_location('runtime', Path(__file__).with_name('verify_apk_runtime.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class ApkRuntimeTest(unittest.TestCase):
    def apk(self, root, extra=None):
        apk = root / 'fixture.apk'
        with ZipFile(apk, 'w') as z:
            for name, data in {
                'lib/arm64-v8a/libflutter.so': b'flutter',
                'lib/arm64-v8a/libapp.so': b'app',
                **(extra or {}),
            }.items():
                z.writestr(name, data)
        return apk

    def test_zero_provider_release_succeeds_but_retired_runtime_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime.verify(self.apk(root), 'arm64-v8a')
            with self.assertRaises(ValueError):
                runtime.verify(self.apk(root, {'lib/arm64-v8a/libcpp.so': b'old-provider'}), 'arm64-v8a')

    def test_wrong_or_extra_architecture_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            with self.assertRaises(ValueError):
                runtime.verify(self.apk(root, {'lib/x86_64/libapp.so': b'wrong-abi'}), 'arm64-v8a')
            with self.assertRaises(ValueError):
                runtime.verify(self.apk(root), 'x86_64')

    def test_source_lists_and_probe_dex_are_rejected_but_normal_assets_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime.verify(self.apk(root, {'assets/config.json': '{"theme":"paper"}'}), 'arm64-v8a')
            runtime.verify(self.apk(root, {'legado/cryptojs.min.js': 'var CryptoJS = {};'}), 'arm64-v8a')
            for extra in [
                {'assets/sources.json': '[{"bookSourceName":"fixture","bookSourceUrl":"https://fixture.invalid"}]'},
                {'classes.dex': b'fixture Lorg/mewx/wenku8_flutter/SourceFixtureProbe;'},
                {'assets/source.js': 'var config={bookSourceName:"fixture",bookSourceUrl:"https://fixture.invalid"};'},
            ]:
                with self.assertRaises(ValueError):
                    runtime.verify(self.apk(root, extra), 'arm64-v8a')


if __name__ == '__main__': unittest.main()
