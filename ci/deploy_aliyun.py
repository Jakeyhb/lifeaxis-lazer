#!/usr/bin/env python3
"""Upload a packaged Lazer site to Aliyun OSS static website hosting.

The packaged `lazer/` directory comes from `ci/release_android.py`. This
script uploads the whole directory to an OSS bucket under a prefix and sets
cache headers so the update manifest is never cached while a published APK
stays immutable. The public domain (for example `lazer.lifeaxis.fun`) is
configured once in the Aliyun console; see docs/releases/aliyun-oss.md.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fingerprint(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return {'sha256': digest.hexdigest(), 'sizeBytes': Path(path).stat().st_size}


def cache_control(name):
    """Cache policy per published file.

    `version.json` drives both the download page and the in-app updater, so it
    must never be served from a long-lived cache. A published APK is immutable
    and content-addressed by its SHA-256, so it can be cached forever.
    """
    if name == 'version.json':
        return 'no-store, no-cache, must-revalidate, max-age=0'
    if name == 'index.html':
        return 'no-cache'
    if name.endswith('.apk'):
        return 'public, max-age=31536000, immutable'
    return 'public, max-age=3600'


def content_type(name):
    if name.endswith('.html'):
        return 'text/html; charset=utf-8'
    if name.endswith('.css'):
        return 'text/css; charset=utf-8'
    if name.endswith('.js'):
        return 'application/javascript; charset=utf-8'
    if name.endswith('.json'):
        return 'application/json; charset=utf-8'
    if name.endswith('.png'):
        return 'image/png'
    if name.endswith('.ttf'):
        return 'font/ttf'
    if name.endswith('.apk'):
        return 'application/vnd.android.package-archive'
    return 'application/octet-stream'


def collect(site):
    """Read every publishable file and check it against the manifest."""
    require(site.is_dir(), 'Site directory not found: ' + str(site))
    files = {}
    for path in sorted(site.rglob('*')):
        if not path.is_file():
            continue
        name = path.relative_to(site).as_posix()
        require(not name.startswith('.'), 'Hidden files cannot be published: ' + name)
        files[name] = fingerprint(path)
    require(
        {'index.html', 'version.json'} <= set(files),
        'Site must contain index.html and version.json.',
    )
    manifest = json.loads((site / 'version.json').read_text(encoding='utf-8'))
    apk_url = manifest.get('apkUrl')
    require(isinstance(apk_url, str) and apk_url, 'Manifest has no apkUrl.')
    parsed = urllib.parse.urlparse(apk_url)
    require(parsed.scheme == 'https' and parsed.path, 'Manifest apkUrl is not an HTTPS URL.')
    require(not parsed.query and not parsed.fragment,
            'Manifest apkUrl must not carry a query or fragment.')
    apk_name = parsed.path.rsplit('/', 1)[-1]
    require(apk_name in files, 'Manifest APK is missing from the site: ' + apk_name)
    require(manifest.get('sha256') == files[apk_name]['sha256'],
            'Manifest SHA-256 does not match the APK.')
    require(manifest.get('sizeBytes') == files[apk_name]['sizeBytes'],
            'Manifest size does not match the APK.')
    return files, manifest


def _headers(name):
    return {
        'Cache-Control': cache_control(name),
        'Content-Type': content_type(name),
    }


def upload(args, files):
    prefix = args.prefix.strip('/')
    if args.dry_run:
        for name, meta in files.items():
            key = prefix + '/' + name
            print('Would upload {} ({} bytes) {}'.format(
                key, meta['sizeBytes'], _headers(name)))
        return
    import oss2

    auth = oss2.Auth(args.access_key_id, args.access_key_secret)
    bucket = oss2.Bucket(auth, args.endpoint, args.bucket)
    for name, meta in files.items():
        key = prefix + '/' + name
        bucket.put_object_from_file(
            key, str(args.site / name), headers=_headers(name))
        print('Uploaded {} ({} bytes)'.format(key, meta['sizeBytes']))


def verify(args, files):
    """Re-download every published file from the public domain and check it."""
    base = 'https://{}/{}/'.format(args.domain.rstrip('/'), args.prefix.strip('/'))
    for name, meta in files.items():
        url = base + urllib.parse.quote(name)
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read()
        require(len(data) == meta['sizeBytes'], 'Size mismatch: ' + name)
        require(hashlib.sha256(data).hexdigest() == meta['sha256'],
                'SHA-256 mismatch: ' + name)
        print('Verified ' + url)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site', type=Path, required=True,
                        help='Packaged lazer/ directory from ci/release_android.py')
    parser.add_argument('--bucket', required=True)
    parser.add_argument('--endpoint', required=True,
                        help='OSS endpoint, for example oss-cn-hangzhou.aliyuncs.com')
    parser.add_argument('--prefix', default='lazer')
    parser.add_argument('--domain', default='lazer.lifeaxis.fun')
    parser.add_argument('--access-key-id', default=os.environ.get('OSS_ACCESS_KEY_ID'))
    parser.add_argument('--access-key-secret',
                        default=os.environ.get('OSS_ACCESS_KEY_SECRET'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--verify', action='store_true',
                        help='Re-download every file from the public domain and check it')
    args = parser.parse_args()
    try:
        files, manifest = collect(args.site)
        require(args.bucket and args.endpoint, 'Bucket and endpoint are required.')
        if not args.dry_run:
            require(args.access_key_id and args.access_key_secret,
                    'OSS credentials are required (OSS_ACCESS_KEY_ID / OSS_ACCESS_KEY_SECRET).')
        upload(args, files)
        if args.verify and not args.dry_run:
            verify(args, files)
        print('Download page: https://{}/{}/'.format(args.domain.rstrip('/'),
                                                     args.prefix.strip('/')))
        print('APK: ' + manifest['apkUrl'])
    except (ValueError, OSError, urllib.error.URLError) as failure:
        print('Aliyun OSS deployment stopped: ' + str(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
