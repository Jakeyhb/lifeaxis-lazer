#!/usr/bin/env python3
"""Build a signed, identity-checked Android release without deploying it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = 'https://lazer.lifeaxis.fun'
PACKAGE = 'fun.lifeaxis.lazer'
PROJECT = 'makers-ff4cnnfdp6cn'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(arguments, cwd=ROOT):
    return subprocess.check_output([str(value) for value in arguments], cwd=cwd,
                                   text=True, stderr=subprocess.STDOUT)


def fingerprint(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return {'sha256': digest.hexdigest(), 'sizeBytes': Path(path).stat().st_size}


def android_tool(name):
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT', ''))
    candidates = list((sdk / 'build-tools').glob('*/' + name))
    require(candidates, 'Android build-tools not found; set ANDROID_HOME.')
    return max(candidates, key=lambda path: tuple(int(part) for part in
               re.findall(r'\d+', path.parent.name)))


def inspect_apk(path):
    path = Path(path).resolve(strict=True)
    signature = run([android_tool('apksigner'), 'verify', '--print-certs', path])
    certs = sorted(set(re.findall(r'Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})', signature)))
    require(certs, 'APK has no verified signing certificates.')
    require('CN=Android Debug' not in signature, 'Debug signing certificates cannot be published.')
    badging = run([android_tool('aapt'), 'dump', 'badging', path])
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    minimum = re.search(r"^sdkVersion:'(\d+)'", badging, re.M)
    native = re.search(r'^native-code: (.+)$', badging, re.M)
    require(package and minimum, 'APK package/version/minSdk could not be read.')
    require('application-debuggable' not in badging, 'Debuggable APK cannot be published.')
    require(package[1] == PACKAGE, 'APK package differs from ' + PACKAGE)
    return dict(fingerprint(path), packageName=package[1], versionCode=int(package[2]),
                versionName=package[3], minSdk=int(minimum[1]),
                abis=re.findall(r"'([^']+)'", native[1]) if native else [],
                signerSha256=[value.lower() for value in certs])


def compatible(candidate, baseline):
    require(candidate['packageName'] == baseline['packageName'] == PACKAGE,
            'Package identity is incompatible.')
    require(candidate['signerSha256'] == baseline['signerSha256'],
            'Signing certificate differs from the existing formal APK. Publication stopped.')
    require(candidate['versionCode'] > baseline['versionCode'],
            'versionCode must exceed the existing formal APK.')


def signing_identity():
    identity = json.loads((ROOT / 'release/android-identity.json').read_text(encoding='utf-8'))
    require(identity.get('packageName') == PACKAGE and identity.get('upstreamUpgradeCompatible') is False,
            'Independent release identity is missing or incompatible.')
    certs = identity.get('signerSha256')
    require(isinstance(certs, list) and len(certs) == 1 and re.fullmatch(r'[a-f0-9]{64}', certs[0]),
            'A pinned release signing certificate is required.')
    return identity


def check_release_identity(candidate, record):
    identity = signing_identity()
    require(record.get('signingIdentity') == identity, 'Release signing identity record differs.')
    require(candidate['packageName'] == PACKAGE and candidate['signerSha256'] == identity['signerSha256'],
            'APK does not match the pinned independent release signer.')
    if record.get('releaseMode') == 'independent-first-release':
        require(record.get('baseline') is None, 'First release must not claim an upstream baseline.')
    else:
        require(record.get('releaseMode') == 'upgrade', 'Unknown release provenance.')
        compatible(candidate, record['baseline'])


def configured_signer(identity):
    properties = dict(line.split('=', 1) for line in (ROOT / 'android/key.properties').read_text().splitlines()
                      if line.strip() and not line.startswith('#'))
    environment = dict(os.environ, LAZER_SIGNING_PASSWORD=properties['storePassword'])
    keystore = Path(properties['storeFile'])
    if not keystore.is_absolute():
        keystore = ROOT / 'android/app' / keystore
    exported = subprocess.check_output(['keytool', '-exportcert', '-keystore', str(keystore),
                                       '-alias', properties['keyAlias'],
                                       '-storepass:env', 'LAZER_SIGNING_PASSWORD'],
                                      env=environment, stderr=subprocess.PIPE)
    require([hashlib.sha256(exported).hexdigest()] == identity['signerSha256'],
            'Configured keystore does not match the pinned release certificate.')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        raise ValueError('Unexpected HTTP redirect; stop and inspect the deployment.')


def get_url(url):
    request = urllib.request.Request(url, headers={'Cache-Control': 'no-cache, no-store'})
    return urllib.request.build_opener(NoRedirect).open(request, timeout=60)


def published_manifest():
    try:
        with get_url(ORIGIN + '/lazer/version.json') as response:
            raw = response.read(131073)
        require(len(raw) <= 131072, 'Published manifest exceeds size limit.')
        value = json.loads(raw)
        require(type(value.get('versionCode')) is int and value['versionCode'] > 0,
                'Published manifest has no valid versionCode.')
        return value
    except urllib.error.HTTPError as failure:
        if failure.code == 404:
            return None
        raise


def next_code(source_code, baseline_code, published_code, local_codes=()):
    result = max([source_code, baseline_code, published_code] + list(local_codes)) + 1
    require(result <= 2100000000, 'Android versionCode limit reached.')
    return result


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def package(args):
    require((ROOT / 'android/key.properties').is_file(),
            'Missing android/key.properties. Restore the existing independent release key; never replace it.')
    require(sys.version_info >= (3, 10),
            'Existing native audio packaging requires Python 3.10+; activate a matching environment first.')
    identity = signing_identity()
    configured_signer(identity)
    baseline_path = args.baseline_apk.resolve(strict=True) if args.baseline_apk else None
    baseline = inspect_apk(baseline_path) if baseline_path else None
    if baseline:
        require(baseline['signerSha256'] == identity['signerSha256'],
                'Baseline is not signed by the pinned independent release identity.')
    pubspec = ROOT / 'pubspec.yaml'
    source = pubspec.read_text(encoding='utf-8')
    match = re.search(r'^version:[ \t]*(\S+)\+(\d+)[ \t]*$', source, re.M)
    require(match, 'pubspec.yaml must contain version: name+code.')
    version_name = args.version_name or match[1]
    require(re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version_name),
            'Use an Android-safe semantic version name.')
    published = published_manifest()
    local_codes = [int(path.name) for path in args.output.glob('*') if path.is_dir() and path.name.isdigit()]
    if args.first_release:
        require(published is None and not local_codes,
                'Independent first release requires no existing published or local release.')
    code = next_code(int(match[2]), baseline['versionCode'] if baseline else 0,
                     published['versionCode'] if published else 0, local_codes)
    destination = args.output.resolve() / str(code)
    require(not destination.exists(), 'Refusing to overwrite an existing release directory.')
    notes = args.notes.read_text(encoding='utf-8').strip()
    require(0 < len(notes) <= 65536, 'Release notes must be nonempty and at most 64K characters.')
    subprocess.run(['bash', str(ROOT / 'ci/build-android-audio.sh')], cwd=ROOT, check=True)
    for abi in ('arm64-v8a', 'armeabi-v7a'):
        subprocess.run([sys.executable, str(ROOT / 'ci/verify-android-audio.py'),
                        '--directory', str(ROOT / 'android/app/src/main/jniLibs' / abi),
                        '--abi', abi], check=True)
    subprocess.run(['flutter', 'build', 'apk', '--release', '--no-pub',
                    '--target-platform', 'android-arm,android-arm64',
                    '--build-name', version_name, '--build-number', str(code),
                    '--dart-define=LAZER_VERSION=' + version_name,
                    '-PlazerRequireReleaseSigning=true', '-PlazerRequireNativeAudio=true'],
                   cwd=ROOT, check=True)
    apk = ROOT / 'build/app/outputs/flutter-apk/app-release.apk'
    metadata = inspect_apk(apk)
    provenance = {'releaseMode': 'independent-first-release' if args.first_release else 'upgrade',
                  'signingIdentity': identity, 'baseline': baseline}
    check_release_identity(metadata, provenance)
    require(metadata['versionCode'] == code and metadata['versionName'] == version_name,
            'Built APK version differs from the requested version.')
    require(metadata['minSdk'] >= 26 and set(metadata['abis']) == {'armeabi-v7a', 'arm64-v8a'},
            'Unexpected minimum SDK or universal APK architectures.')
    subprocess.run([sys.executable, str(ROOT / 'ci/verify-android-audio.py'), '--apk', str(apk)], check=True)
    args.output.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.building-', dir=args.output))
    try:
        site = temporary / 'lazer'
        shutil.copytree(ROOT / 'release/site', site)
        for source_path, name in (
            ('assets/app_icon.png', 'icon.png'),
            ('docs/images/mascot.png', 'mascot.png'),
            ('assets/fonts/MiSans-Regular.ttf', 'MiSans-Regular.ttf'),
        ):
            shutil.copyfile(ROOT / source_path, site / name)
        filename = 'Lazer-{}-{}-universal.apk'.format(version_name, code)
        shutil.copyfile(apk, site / filename)
        manifest = dict(metadata, apkUrl=ORIGIN + '/lazer/' + filename,
                        notes=notes, mandatory=args.mandatory)
        write_json(site / 'version.json', manifest)
        record = {'projectId': PROJECT, 'status': 'packaged-not-deployed',
                  'baselineApk': str(baseline_path) if baseline_path else None, **provenance,
                  'gitRevision': run(['git', 'rev-parse', 'HEAD']).strip(),
                  'gitDirty': bool(run(['git', 'status', '--porcelain']).strip()),
                  'manifest': manifest,
                  'files': {str(path.relative_to(site)): fingerprint(path)
                            for path in sorted(site.rglob('*')) if path.is_file()}}
        write_json(temporary / 'release-record.json', record)
        temporary.rename(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    require(pubspec.read_text(encoding='utf-8') == source,
            'pubspec.yaml changed during build; package saved but source version not updated.')
    pubspec.write_text(source[:match.start()] + 'version: {}+{}'.format(version_name, code) +
                       source[match.end():], encoding='utf-8')
    print('Verified package prepared, NOT deployed: ' + str(destination))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--baseline-apk', type=Path,
                      help='Previous LifeAxis release APK matching the pinned signing identity')
    mode.add_argument('--first-release', action='store_true',
                      help='Authorized independent first release, not compatible with upstream APKs')
    parser.add_argument('--notes', type=Path, default=ROOT / 'release/notes.txt')
    parser.add_argument('--version-name')
    parser.add_argument('--mandatory', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/releases/android')
    args = parser.parse_args()
    try:
        package(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as failure:
        print('Release stopped: ' + str(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
