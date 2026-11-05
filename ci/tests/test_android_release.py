import argparse
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import deploy_android
import edgeone_apk_transport
import export_production_baseline
import release_android


class AndroidReleaseTests(unittest.TestCase):
    def test_archived_functions_require_verified_receipt_and_exact_provider_routes(self):
        route = {'src': '/lazer/Lazer-9.apk', 'dest': 'lazer-apk-function'}
        routes = [{'handle': 'filesystem'}, route]
        production = {'DeploymentId': 'current', 'MetaData': {'routes': routes, 'conf': {}}}
        entry = {'sizeBytes': 1, 'sha256': 'a' * 64}
        receipt = {'projectId': release_android.PROJECT, 'completeSnapshot': True,
                   'source': 'successful-full-snapshot', 'status': 'verified-production',
                   'deploymentId': 'current', 'providerRoutes': routes,
                   'files': {'index.html': entry, 'version.json': entry, 'zaice/old.apk': entry},
                   'functions': {'edge-functions/lazer/Lazer-9.apk.js': entry},
                   'virtualFiles': {'lazer/Lazer-9.apk': entry}, 'config': {}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            release_android.write_json(path, receipt)
            self.assertEqual(deploy_android.load_baseline(path, production), receipt)
            for changes in ({'status': 'deployed-verification-pending'},
                            {'providerRoutes': [{'handle': 'filesystem'}]}):
                release_android.write_json(path, dict(receipt, **changes))
                with self.assertRaises(ValueError):
                    deploy_android.load_baseline(path, production)

    def test_snapshot_copy_preserves_archived_apk_functions_without_local_drafts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'baseline'
            function = source / 'edge-functions/lazer/Lazer-9.apk.js'
            function.parent.mkdir(parents=True)
            function.write_bytes(b'original function')
            (source / 'index.html').write_bytes(b'root app')
            (source / 'draft.txt').write_bytes(b'unpublished')
            receipt = {'files': {'index.html': release_android.fingerprint(source / 'index.html')},
                       'functions': {str(function.relative_to(source)): release_android.fingerprint(function)}}
            target = root / 'staging'
            deploy_android.copy_baseline(source, receipt, target)
            self.assertEqual((target / function.relative_to(source)).read_bytes(), b'original function')
            self.assertFalse((target / 'draft.txt').exists())

    def test_large_apk_transport_preserves_bytes_and_uses_exact_immutable_route(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / 'lazer/Lazer-test-9.apk'
            apk.parent.mkdir()
            original = b'complete signed APK bytes' * 9
            apk.write_bytes(original)
            manifest = release_android.fingerprint(apk)
            with patch.object(edgeone_apk_transport, 'STATIC_LIMIT', 32), \
                    patch.object(edgeone_apk_transport, 'CHUNK_BYTES', 24):
                files, functions, virtual = edgeone_apk_transport.prepare_transport(root, apk.name, manifest)
            self.assertFalse(apk.exists())
            self.assertEqual(b''.join((root / name).read_bytes() for name in sorted(files)), original)
            self.assertEqual(virtual, {'lazer/Lazer-test-9.apk': manifest})
            self.assertEqual(list(functions), ['edge-functions/lazer/Lazer-test-9.apk.js'])
            for name, expected in dict(files, **functions).items():
                self.assertEqual(release_android.fingerprint(root / name), expected)
            apk.write_bytes(original)
            with patch.object(edgeone_apk_transport, 'STATIC_LIMIT', 32):
                with self.assertRaisesRegex(ValueError, 'immutable APK chunks'):
                    edgeone_apk_transport.prepare_transport(root, apk.name, manifest)
            self.assertTrue(apk.exists())

    def test_small_apk_remains_a_static_file_and_large_files_fail_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / 'lazer/Lazer-test-9.apk'
            apk.parent.mkdir()
            apk.write_bytes(b'valid bytes')
            self.assertEqual(edgeone_apk_transport.prepare_transport(
                root, apk.name, release_android.fingerprint(apk)), ({}, {}, {}))
            with patch.object(edgeone_apk_transport, 'STATIC_LIMIT', 1):
                with self.assertRaisesRegex(ValueError, '25 MiB'):
                    edgeone_apk_transport.check_static_sizes(root)

    def test_console_inventory_requires_complete_distinct_provider_counts(self):
        inventory = {'projectId': release_android.PROJECT,
                     'inventorySource': 'authenticated-provider-console',
                     'rootFileCount': 1, 'directoryFileCounts': {'zaice': 1},
                     'files': ['index.html', 'zaice/old.apk']}
        self.assertEqual(export_production_baseline.validate_inventory(inventory), inventory['files'])
        for changes in ({'inventorySource': 'guessed-local-list'},
                        {'rootFileCount': 2}, {'directoryFileCounts': {'zaice': 2}},
                        {'files': ['index.html', 'index.html']},
                        {'projectId': 'other-project'}):
            with self.assertRaises(ValueError):
                export_production_baseline.validate_inventory(dict(inventory, **changes))

    def test_recorded_provider_inventory_has_31_files_and_excludes_local_drafts(self):
        path = Path(__file__).resolve().parents[2] / 'docs/releases/edgeone-inventory-2026-11-05.json'
        inventory = json.loads(path.read_text(encoding='utf-8'))
        files = export_production_baseline.validate_inventory(inventory)
        self.assertEqual(len(files), 31)
        self.assertEqual(sum(name.endswith('.apk') for name in files), 26)
        self.assertFalse(any(name.startswith(('loom/', 'lazer/')) for name in files))

    def test_next_code_exceeds_source_production_baseline_and_local_artifacts(self):
        self.assertEqual(release_android.next_code(8, 8, 10, [9, 12]), 13)
        self.assertEqual(release_android.next_code(8, 3008, 0), 3009)
        with self.assertRaises(ValueError):
            release_android.next_code(2100000000, 8, 9)

    def test_signature_and_package_identity_are_mandatory(self):
        baseline = {'packageName': release_android.PACKAGE, 'signerSha256': ['original'], 'versionCode': 8}
        candidate = dict(baseline, versionCode=9)
        release_android.compatible(candidate, baseline)
        for changed in ({'signerSha256': ['new']}, {'packageName': 'another.app'}, {'versionCode': 8}):
            with self.assertRaises(ValueError):
                release_android.compatible(dict(candidate, **changed), baseline)

    def test_debug_and_unverified_apks_cannot_be_packaged(self):
        with tempfile.NamedTemporaryFile(suffix='.apk') as archive:
            with patch.object(release_android, 'android_tool', return_value='apksigner'):
                with patch.object(release_android, 'run', return_value='Signer #1 certificate DN: CN=Android Debug'):
                    with self.assertRaises(ValueError):
                        release_android.inspect_apk(archive.name)
                with patch.object(release_android, 'run', side_effect=RuntimeError('invalid signature')):
                    with self.assertRaises(RuntimeError):
                        release_android.inspect_apk(archive.name)

    def test_independent_first_release_requires_pinned_identity_and_no_fake_baseline(self):
        identity = {'packageName': release_android.PACKAGE, 'signerSha256': ['pinned']}
        metadata = dict(identity, versionCode=9)
        record = {'releaseMode': 'independent-first-release', 'baseline': None, 'signingIdentity': identity}
        with patch.object(release_android, 'signing_identity', return_value=identity):
            release_android.check_release_identity(metadata, record)
            for changes in ({'signerSha256': ['different']}, {'packageName': 'dev.naominet.lazer'}):
                with self.assertRaises(ValueError):
                    release_android.check_release_identity(dict(metadata, **changes), record)
            for changes in ({'baseline': metadata}, {'releaseMode': 'unknown'}, {'signingIdentity': {}}):
                with self.assertRaises(ValueError):
                    release_android.check_release_identity(metadata, dict(record, **changes))

    def test_independent_upgrade_requires_previous_own_signer_and_increasing_code(self):
        identity = {'packageName': release_android.PACKAGE, 'signerSha256': ['pinned']}
        metadata = dict(identity, versionCode=10)
        record = {'releaseMode': 'upgrade', 'baseline': dict(metadata, versionCode=9),
                  'signingIdentity': identity}
        with patch.object(release_android, 'signing_identity', return_value=identity):
            release_android.check_release_identity(metadata, record)
            with self.assertRaises(ValueError):
                release_android.check_release_identity(dict(metadata, versionCode=9), record)

    def test_path_traversal_and_hidden_local_state_are_rejected(self):
        for path in ('../file', '/file', 'a/../b', './x', '.edgeone/token', 'a\\b', 'a//b'):
            with self.assertRaises(ValueError, msg=path):
                deploy_android.safe_path(path)
        self.assertEqual(deploy_android.safe_path('zaice/old.apk'), 'zaice/old.apk')

    def test_cache_rules_are_scoped_and_preserve_other_app_rules(self):
        config = {'headers': [{'source': '/zaice/version.json', 'headers': [{'key': 'X-App', 'value': 'zaice'}]}],
                  'caches': [{'source': '/version.json', 'cacheTtl': 0}], 'redirects': []}
        merged = deploy_android.merge_config(config)
        self.assertEqual(merged['headers'][0], config['headers'][0])
        self.assertEqual(merged['caches'][0], config['caches'][0])
        self.assertEqual([rule['source'] for rule in merged['caches'][1:]],
                         ['/lazer/version.json', '/lazer/', '/lazer/index.html'])
        self.assertEqual(config['caches'], [{'source': '/version.json', 'cacheTtl': 0}])
        self.assertEqual(merged['redirects'], [
            {'source': '/lazer', 'destination': '/lazer/', 'statusCode': 308}])
        with self.assertRaises(ValueError):
            deploy_android.merge_config({'caches': [{'source': '/*', 'cacheTtl': 3600}]})

    def test_incomplete_stale_or_nonstatic_production_baselines_are_rejected(self):
        production = {'DeploymentId': 'current', 'MetaData': json.dumps({
            'routes': [{'handle': 'filesystem'}], 'conf': {'headers': [], 'redirects': [], 'caches': []}})}
        entry = {'sha256': 'a' * 64, 'sizeBytes': 1}
        receipt = {'projectId': release_android.PROJECT, 'completeSnapshot': True,
                   'source': 'provider-export', 'deploymentId': 'current',
                   'config': {}, 'files': {'index.html': entry, 'version.json': entry,
                                           'zaice/old.apk': entry}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            for changes in ({'completeSnapshot': False}, {'deploymentId': 'old'},
                            {'source': 'guessed-local-directory'}, {'files': {'index.html': entry}}):
                release_android.write_json(path, dict(receipt, **changes))
                with self.assertRaises(ValueError):
                    deploy_android.load_baseline(path, production)
            release_android.write_json(path, receipt)
            self.assertEqual(deploy_android.load_baseline(path, production), receipt)
            production['MetaData'] = json.dumps({'routes': [{'handle': 'rewrite'}], 'conf': {}})
            with self.assertRaises(ValueError):
                deploy_android.load_baseline(path, production)

    def test_baseline_copy_is_exact_and_never_includes_unpublished_drafts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline = root / 'baseline'
            target = root / 'staged'
            baseline.mkdir()
            target.mkdir()
            (baseline / 'published.apk').write_bytes(b'published bytes')
            (baseline / 'draft.apk').write_bytes(b'not deployed')
            receipt = {'files': {'published.apk': release_android.fingerprint(baseline / 'published.apk')}}
            deploy_android.copy_baseline(baseline, receipt, target)
            self.assertEqual(list(target.iterdir()), [target / 'published.apk'])
            self.assertEqual((target / 'published.apk').read_bytes(), b'published bytes')
            (baseline / 'published.apk').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                deploy_android.copy_baseline(baseline, receipt, target)

    def test_historical_lazer_apk_url_is_immutable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            site = root / 'release/lazer'
            site.mkdir(parents=True)
            metadata = {'packageName': release_android.PACKAGE, 'versionName': '2.0.0',
                        'versionCode': 9, 'signerSha256': ['original'], 'minSdk': 26,
                        'abis': ['arm64-v8a'], 'sha256': 'a' * 64, 'sizeBytes': 10}
            manifest = dict(metadata, apkUrl=release_android.ORIGIN + '/lazer/Lazer-2.0.0-9.apk',
                            notes='actual changes', mandatory=False)
            record = {'projectId': release_android.PROJECT, 'status': 'packaged-not-deployed',
                      'manifest': manifest, 'baseline': dict(metadata, versionCode=8),
                      'releaseMode': 'upgrade',
                      'signingIdentity': {'packageName': release_android.PACKAGE, 'signerSha256': ['original']},
                      'files': {name: {} for name in ('index.html', 'version.json', 'download.js', 'style.css')}}
            release_android.write_json(site / 'version.json', manifest)
            release_android.write_json(site.parent / 'release-record.json', record)
            args = argparse.Namespace(release=site.parent, baseline=root / 'baseline', output=root / 'out')
            with patch.object(deploy_android, 'inspect_apk', return_value=metadata), \
                    patch.object(release_android, 'signing_identity', return_value=record['signingIdentity']):
                with self.assertRaisesRegex(ValueError, 'historical APK'):
                    deploy_android.stage(args, {'DeploymentId': 'current'},
                                         {'files': {'lazer/Lazer-2.0.0-9.apk': {}}})
            self.assertFalse(args.output.exists())


if __name__ == '__main__':
    unittest.main()
