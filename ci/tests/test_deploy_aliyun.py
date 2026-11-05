import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import deploy_aliyun


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode('utf-8'))


class DeployAliyunTests(unittest.TestCase):
    def test_cache_control_is_never_long_for_the_manifest(self):
        self.assertIn('no-store', deploy_aliyun.cache_control('version.json'))
        self.assertIn('immutable', deploy_aliyun.cache_control('Lazer-2.0.0-9.apk'))
        self.assertEqual('no-cache', deploy_aliyun.cache_control('index.html'))
        self.assertIn('max-age=3600', deploy_aliyun.cache_control('style.css'))

    def test_content_type_covers_the_published_files(self):
        self.assertEqual('application/vnd.android.package-archive',
                         deploy_aliyun.content_type('Lazer.apk'))
        self.assertEqual('application/json; charset=utf-8',
                         deploy_aliyun.content_type('version.json'))
        self.assertEqual('text/html; charset=utf-8',
                         deploy_aliyun.content_type('index.html'))
        self.assertEqual('image/png', deploy_aliyun.content_type('icon.png'))

    def site(self, directory, *, apk=b'apk-bytes', manifest=None):
        write(Path(directory, 'index.html'), '<html></html>')
        write(Path(directory, 'Lazer-2.0.0-9.apk'), apk)
        digest = hashlib.sha256(apk).hexdigest()
        payload = {
            'versionCode': 9,
            'versionName': '2.0.0',
            'apkUrl': 'https://updates.lifeaxis.fun/lazer/Lazer-2.0.0-9.apk',
            'notes': 'notes',
            'mandatory': False,
            'sha256': digest,
            'sizeBytes': len(apk),
            'packageName': 'fun.lifeaxis.lazer',
        }
        payload.update(manifest or {})
        write(Path(directory, 'version.json'), json.dumps(payload))

    def test_collect_reads_every_file_and_checks_the_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            self.site(Path(directory))
            files, manifest = deploy_aliyun.collect(Path(directory))
            self.assertEqual({'index.html', 'Lazer-2.0.0-9.apk', 'version.json'},
                             set(files))
            self.assertEqual(manifest['versionCode'], 9)

    def test_collect_rejects_a_manifest_that_disagrees_with_the_apk(self):
        with tempfile.TemporaryDirectory() as directory:
            self.site(Path(directory), manifest={'sha256': '0' * 64})
            with self.assertRaises(ValueError):
                deploy_aliyun.collect(Path(directory))

    def test_collect_rejects_a_missing_apk(self):
        with tempfile.TemporaryDirectory() as directory:
            self.site(Path(directory))
            (Path(directory) / 'Lazer-2.0.0-9.apk').unlink()
            with self.assertRaises(ValueError):
                deploy_aliyun.collect(Path(directory))

    def test_collect_rejects_hidden_files(self):
        with tempfile.TemporaryDirectory() as directory:
            self.site(Path(directory))
            write(Path(directory, '.DS_Store'), 'junk')
            with self.assertRaises(ValueError):
                deploy_aliyun.collect(Path(directory))

    def test_collect_rejects_a_query_or_fragment_on_the_apk_url(self):
        with tempfile.TemporaryDirectory() as directory:
            self.site(Path(directory), manifest={
                'apkUrl': 'https://updates.lifeaxis.fun/lazer/Lazer-2.0.0-9.apk?token=x',
            })
            with self.assertRaises(ValueError):
                deploy_aliyun.collect(Path(directory))


if __name__ == '__main__':
    unittest.main()
