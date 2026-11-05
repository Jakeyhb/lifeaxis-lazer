#!/usr/bin/env python3
"""Stage a complete proven production snapshot; deploy only with --deploy."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

from release_android import (ORIGIN, PROJECT, ROOT, check_release_identity, compatible, fingerprint,
                             get_url, inspect_apk, require, write_json)
from edgeone_apk_transport import check_static_sizes, prepare_transport


def current_production():
    auth = {}
    for path in (Path.home() / '.edgeone').glob('*'):
        if not path.is_file() or not re.fullmatch(r'[a-f0-9]{64}(?:\.json)?', path.name):
            continue
        entry = json.loads(path.read_text(encoding='utf-8'))
        if isinstance(entry, dict) and 'key' in entry and 'value' in entry:
            auth[entry['key']] = entry['value']
    token = auth.get('eo_token', {}).get('Token')
    require(token, 'No existing EdgeOne login. Run edgeone login, then retry.')
    endpoint = ('https://pages-api.cloud.tencent.com/v1' if auth.get('login_region') == 'china'
                else 'https://pages-api.edgeone.ai/v1')
    body = {'Action': 'DescribePagesDeployments', 'ProjectId': PROJECT,
            'Offset': 0, 'Limit': 50, 'OrderBy': 'CreatedOn', 'Order': 'Desc'}
    request = urllib.request.Request(endpoint, data=json.dumps(body).encode(),
                                     headers={'Content-Type': 'application/json',
                                              'Authorization': 'Bearer ' + token})
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.load(response)
    require(result.get('Code') == 0, 'EdgeOne could not confirm the production deployment.')
    deployments = result.get('Data', {}).get('Response', {}).get('Deployments', [])
    active = [entry for entry in deployments if entry.get('UsedInProd') is True]
    require(len(active) == 1, 'Unable to identify exactly one production deployment.')
    require(active[0].get('Status') == 'Success' and active[0].get('ProjectId') == PROJECT,
            'Production deployment is not successful or belongs to another project.')
    return active[0]


def safe_path(value):
    require(isinstance(value, str) and value and '\\' not in value,
            'Invalid inventory path.')
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(part not in ('.', '..') for part in path.parts)
            and str(path) == value and not any(part.startswith('.') for part in path.parts),
            'Inventory contains unsafe/hidden paths: ' + value)
    return value


def load_baseline(receipt_path, production):
    receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
    require(receipt.get('projectId') == PROJECT and receipt.get('completeSnapshot') is True,
            'A complete production snapshot receipt is required; local directory listings are not proof.')
    require(receipt.get('source') in ('provider-export', 'successful-full-snapshot'),
            'Receipt must come from a provider export or a recorded successful full deployment.')
    require(receipt.get('source') != 'successful-full-snapshot' or
            receipt.get('status') == 'verified-production',
            'A deployed but unverified snapshot cannot be used as a release baseline.')
    require(receipt.get('deploymentId') == production['DeploymentId'],
            'Snapshot receipt is stale: production deployment ID differs.')
    files = receipt.get('files')
    require(isinstance(files, dict) and 'index.html' in files and 'version.json' in files,
            'Missing root application or empty snapshot inventory.')
    require(any(name.startswith('zaice/') for name in files), 'Missing the existing zaice application.')
    for name, expected in dict(files, **receipt.get('functions', {}), **receipt.get('virtualFiles', {})).items():
        safe_path(name)
        require(name != 'edgeone.json', 'Deployment configuration belongs in receipt.config, not static files.')
        require(isinstance(expected, dict) and type(expected.get('sizeBytes')) is int
                and expected['sizeBytes'] >= 0 and isinstance(expected.get('sha256'), str)
                and re.fullmatch(r'[a-f0-9]{64}', expected['sha256']),
                'Invalid receipt fingerprint: ' + name)
    config = receipt.get('config', {})
    require(isinstance(config, dict) and not set(config) - {'headers', 'redirects', 'caches', '$schema'},
            'Only verified static-site configuration is supported; stop for manual provider export review.')
    metadata = json.loads(production['MetaData']) if isinstance(production['MetaData'], str) else production['MetaData']
    require(metadata.get('routes') == receipt.get('providerRoutes', [{'handle': 'filesystem'}]),
            'Production routing differs from the proven snapshot.')
    require(not receipt.get('functions') or receipt.get('source') == 'successful-full-snapshot',
            'Function source must come from a verified archived deployment.')
    actual = metadata.get('conf', {})
    require(not set(actual) - {'headers', 'redirects', 'caches'}, 'Unknown production routing configuration.')
    for key in ('headers', 'redirects', 'caches'):
        require(config.get(key, []) == actual.get(key, []), 'Archived configuration differs: ' + key)
    return receipt


def verify_remote(origin, files):
    for index, (name, expected) in enumerate(sorted(files.items()), start=1):
        print('Verifying remote file {}/{}: {}'.format(index, len(files), name), flush=True)
        digest = hashlib.sha256()
        size = 0
        with get_url(origin.rstrip('/') + '/' + urllib.parse.quote(name, safe='/')) as response:
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                size += len(chunk)
                require(size <= expected['sizeBytes'], 'Remote file grew unexpectedly: ' + name)
                digest.update(chunk)
        require({'sha256': digest.hexdigest(), 'sizeBytes': size} == expected,
                'Remote content does not match the proven snapshot: ' + name)


def merge_config(config):
    merged = json.loads(json.dumps(config))
    merged['redirects'] = [rule for rule in merged.get('redirects', [])
                           if rule.get('source') != '/lazer'] + [
        {'source': '/lazer', 'destination': '/lazer/', 'statusCode': 308}]
    sources = ('/lazer/version.json', '/lazer/', '/lazer/index.html')
    for key in ('headers', 'caches'):
        existing = merged.get(key, [])
        require(isinstance(existing, list), 'Invalid EdgeOne ' + key)
        unrelated = [rule for rule in existing if rule.get('source') not in sources]
        require(not any('*' in rule.get('source', '') or '(' in rule.get('source', '')
                        for rule in unrelated),
                'Broad existing cache/header rules require provider review before merging.')
        if key == 'headers':
            added = [{'source': source, 'headers': [{'key': 'Cache-Control',
                      'value': 'no-store, no-cache, must-revalidate, max-age=0'}]} for source in sources]
        else:
            added = [{'source': source, 'cacheTtl': 0} for source in sources]
        merged[key] = unrelated + added
    return merged


def copy_baseline(directory, receipt, target):
    for name, expected in dict(receipt['files'], **receipt.get('functions', {})).items():
        source = checked_source(directory, name)
        require(source.is_file() and fingerprint(source) == expected,
                'Missing/modified baseline file: ' + name)
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)


def checked_source(directory, name):
    directory = directory.resolve(strict=True)
    source = directory
    for part in PurePosixPath(safe_path(name)).parts:
        source = source / part
        require(not source.is_symlink(), 'Snapshot symlinks are not allowed: ' + name)
    return source


def stage(args, production, receipt):
    release = json.loads((args.release / 'release-record.json').read_text(encoding='utf-8'))
    require(release.get('projectId') == PROJECT and release.get('status') == 'packaged-not-deployed',
            'Use output from ci/release_android.py.')
    files = release['files']
    require({'index.html', 'version.json', 'download.js', 'style.css'} <= set(files),
            'Release website files are incomplete.')
    manifest = json.loads((args.release / 'lazer/version.json').read_text(encoding='utf-8'))
    require(manifest == release['manifest'], 'Release manifest was modified after packaging.')
    apk_name = urllib.parse.urlparse(manifest['apkUrl']).path.removeprefix('/lazer/')
    require(manifest['apkUrl'] == ORIGIN + '/lazer/' + safe_path(apk_name) and '/' not in apk_name,
            'APK must live directly under the Lazer directory.')
    metadata = inspect_apk(args.release / 'lazer' / apk_name)
    require(all(manifest.get(key) == value for key, value in metadata.items()), 'APK differs from its manifest.')
    check_release_identity(metadata, release)
    if release['releaseMode'] == 'independent-first-release':
        require(not any(name.startswith('lazer/') for name in receipt['files']),
                'Cannot deploy a first release over an existing Lazer publication.')
    require('lazer/' + apk_name not in dict(receipt['files'], **receipt.get('virtualFiles', {})),
            'Refusing to overwrite a historical APK URL.')
    if 'lazer/version.json' in receipt['files']:
        previous = json.loads((args.baseline / 'lazer/version.json').read_text(encoding='utf-8'))
        compatible(metadata, previous)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    require(not args.output.exists(), 'Staging directory must not already exist.')
    temporary = Path(tempfile.mkdtemp(prefix='.edgeone-staging-', dir=args.output.parent))
    try:
        copy_baseline(args.baseline, receipt, temporary)
        for name, expected in files.items():
            safe_path(name)
            require(not name.endswith('.apk') or name == apk_name, 'Unexpected extra APK in release.')
            source = checked_source(args.release / 'lazer', name)
            require(fingerprint(source) == expected, 'Release file changed: ' + name)
            destination = temporary / 'lazer' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        write_json(temporary / 'edgeone.json', merge_config(receipt.get('config', {})))
        transport_files, functions, virtual_files = prepare_transport(temporary, apk_name, manifest)
        check_static_sizes(temporary)
        temporary.rename(args.output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    all_files = dict(receipt['files'])
    all_files.update({'lazer/' + name: value for name, value in files.items()})
    if virtual_files:
        del all_files['lazer/' + apk_name]
        all_files.update(transport_files)
    result = {'projectId': PROJECT, 'baselineDeploymentId': production['DeploymentId'],
              'status': 'staged-not-deployed', 'completeSnapshot': True,
              'source': 'successful-full-snapshot', 'files': all_files,
              'config': json.loads((args.output / 'edgeone.json').read_text()),
              'functions': dict(receipt.get('functions', {}), **functions),
              'virtualFiles': dict(receipt.get('virtualFiles', {}), **virtual_files),
              'manifest': manifest}
    return result, release


def deploy(args):
    production = current_production()
    receipt = load_baseline(args.baseline_receipt, production)
    print('Verifying every known production file against the complete archived inventory...')
    verify_remote(ORIGIN, dict(receipt['files'], **receipt.get('virtualFiles', {})))
    result, release = stage(args, production, receipt)
    report = args.output.with_name(args.output.name + '-receipt.json')
    write_json(report, result)
    print('Isolated complete snapshot staged: ' + str(args.output))
    if not args.deploy:
        print('NOT deployed. Re-run with a fresh --output and --deploy after reviewing the staged snapshot.')
        return
    require(current_production()['DeploymentId'] == production['DeploymentId'],
            'Production changed during preparation; do not deploy a stale snapshot.')
    log = args.output.with_name(args.output.name + '-deployment.log')
    with log.open('w') as output:
        os.chmod(log, 0o600)
        subprocess.run(['edgeone', 'makers', 'deploy', str(args.output), '-n', 'feelmating-updates',
                        '-e', 'production', '--json', '--skip-ai-gateway-sync'], stdout=output,
                       stderr=subprocess.STDOUT, check=True)
    deployed = current_production()
    require(deployed['DeploymentId'] != production['DeploymentId'], 'No new production deployment confirmed.')
    metadata = json.loads(deployed['MetaData']) if isinstance(deployed['MetaData'], str) else deployed['MetaData']
    result.update(status='deployed-verification-pending', deploymentId=deployed['DeploymentId'],
                  providerRoutes=metadata.get('routes'))
    write_json(report, result)
    verify_remote(ORIGIN, dict(result['files'], **result.get('virtualFiles', {})))
    with get_url(ORIGIN + '/lazer/version.json') as response:
        require('no-store' in response.headers.get('Cache-Control', '').lower(),
                'Manifest Cache-Control does not prevent long caching.')
    with tempfile.TemporaryDirectory(prefix='lazer-production-verification-') as directory:
        downloaded = Path(directory) / 'production.apk'
        with get_url(result['manifest']['apkUrl']) as response, downloaded.open('wb') as output:
            shutil.copyfileobj(response, output)
        metadata = inspect_apk(downloaded)
        require(all(result['manifest'].get(key) == value for key, value in metadata.items()),
                'Production download metadata does not match the release.')
        check_release_identity(metadata, release)
    result.update(status='verified-production', verification={
        'allHistoricalFiles': 'size-and-sha256-matched',
        'productionApk': 'size-sha256-package-version-signature-matched',
        'manifestCache': 'no-store'})
    write_json(report, result)
    print('Verified production deployment: ' + result['deploymentId'])
    print('Download page: ' + ORIGIN + '/lazer/')
    print('APK: ' + result['manifest']['apkUrl'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--baseline-receipt', type=Path, required=True)
    parser.add_argument('--release', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--deploy', action='store_true')
    args = parser.parse_args()
    try:
        deploy(args)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as failure:
        print('Production publication stopped: ' + str(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
