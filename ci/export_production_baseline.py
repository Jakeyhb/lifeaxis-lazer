#!/usr/bin/env python3
"""Recover production bytes using an independently verified provider inventory."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import sys
import tempfile
import urllib.parse
import zipfile

from deploy_android import current_production, load_baseline, safe_path
from release_android import ORIGIN, PROJECT, fingerprint, get_url, require, write_json


def validate_inventory(inventory):
    require(inventory.get('projectId') == PROJECT,
            'Inventory belongs to a different project.')
    require(inventory.get('inventorySource') == 'authenticated-provider-console',
            'Inventory must come from the complete authenticated provider artifact listing.')
    files = inventory.get('files')
    require(isinstance(files, list) and files and len(set(files)) == len(files),
            'Inventory must contain distinct file paths.')
    counts = Counter()
    for name in files:
        safe_path(name)
        require(name != 'edgeone.json', 'Configuration cannot be recovered as a static asset.')
        counts[name.rsplit('/', 1)[0] if '/' in name else ''] += 1
    expected = dict(inventory.get('directoryFileCounts', {}))
    expected[''] = inventory.get('rootFileCount')
    require(dict(counts) == expected, 'File counts differ from the observed provider directory counts.')
    return files


def download_file(directory, name, deployment_id):
    destination = directory / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    query = urllib.parse.urlencode({'baseline': deployment_id})
    url = ORIGIN + '/' + urllib.parse.quote(name, safe='/') + '?' + query
    with get_url(url) as response, destination.open('xb') as output:
        require(response.status == 200, 'Unexpected HTTP status: ' + name)
        declared = response.headers.get('Content-Length')
        size = 0
        for chunk in iter(lambda: response.read(1024 * 1024), b''):
            size += len(chunk)
            require(size <= 1024 * 1024 * 1024, 'Baseline file exceeds 1 GiB: ' + name)
            output.write(chunk)
        require(not declared or size == int(declared), 'Truncated production response: ' + name)
    if name.endswith('.apk'):
        with zipfile.ZipFile(destination) as archive:
            require('AndroidManifest.xml' in archive.namelist(), 'Downloaded asset is not an APK: ' + name)
    result = fingerprint(destination)
    print('Recovered {} ({} bytes)'.format(name, result['sizeBytes']), flush=True)
    return name, result


def export(args):
    inventory = json.loads(args.inventory.read_text(encoding='utf-8'))
    files = validate_inventory(inventory)
    production = current_production()
    deployment_id = production['DeploymentId']
    require(inventory.get('deploymentId') == deployment_id,
            'Provider inventory does not describe the current production deployment.')
    metadata = json.loads(production['MetaData'])
    require(metadata.get('routes') == [{'handle': 'filesystem'}],
            'Cannot recover non-static routes from a static artifact inventory.')
    require(not args.output.exists(), 'Refusing to replace an existing baseline.')
    receipt_path = args.output.with_name(args.output.name + '-receipt.json')
    require(not receipt_path.exists(), 'Refusing to replace an existing baseline receipt.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.recovering-', dir=args.output.parent))
    try:
        with ThreadPoolExecutor(max_workers=4) as executor:
            fingerprints = dict(executor.map(
                lambda name: download_file(temporary, name, deployment_id), files))
        require(current_production()['DeploymentId'] == deployment_id,
                'Production changed while recovering; snapshot rejected.')
        receipt = {
            'projectId': PROJECT, 'deploymentId': deployment_id,
            'completeSnapshot': True, 'source': 'provider-export',
            'recoveredAt': datetime.now(timezone.utc).isoformat(),
            'inventoryEvidence': inventory,
            'config': metadata['conf'], 'files': fingerprints,
        }
        temporary_receipt = temporary / '.recovery-receipt.json'
        write_json(temporary_receipt, receipt)
        load_baseline(temporary_receipt, production)
        temporary_receipt.unlink()
        temporary.rename(args.output)
        write_json(receipt_path, receipt)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    print('Verified inventory recovered; NOT deployed: ' + str(args.output))
    print('Receipt: ' + str(receipt_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        export(args)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as failure:
        print('Baseline recovery stopped: ' + str(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
