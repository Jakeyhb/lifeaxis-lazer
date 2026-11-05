#!/usr/bin/env python3
"""Initialize the explicitly authorized independent Android identity exactly once."""

import argparse
import hashlib
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys

from release_android import PACKAGE, ROOT, require, write_json


def initialize(args):
    os.umask(0o077)
    require(args.initialize_independent_app, 'Explicit independent-first-release authorization is required.')
    properties = ROOT / 'android/key.properties'
    identity = ROOT / 'release/android-identity.json'
    private = Path.home() / '.local/share/lazer-signing' / PACKAGE
    backup = Path.home() / 'Documents/Lazer-signing-backup' / PACKAGE
    for path in (properties, identity, private, backup):
        require(not path.exists(), 'Refusing to replace existing signing material: ' + str(path))
    subprocess.run(['git', 'check-ignore', '--quiet', 'android/key.properties'], cwd=ROOT, check=True)
    private.mkdir(parents=True, mode=0o700)
    backup.mkdir(parents=True, mode=0o700)
    os.chmod(backup.parent, 0o700)
    password = secrets.token_hex(32)
    environment = dict(os.environ, LAZER_SIGNING_PASSWORD=password)
    keystore = private / 'release.p12'
    arguments = ['keytool', '-genkeypair', '-keystore', str(keystore), '-storetype', 'PKCS12',
                 '-storepass:env', 'LAZER_SIGNING_PASSWORD', '-keypass:env', 'LAZER_SIGNING_PASSWORD',
                 '-alias', 'lazer-release', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
                 '-dname', 'CN=Lazer LifeAxis Release, O=LifeAxis', '-noprompt']
    subprocess.run(arguments, env=environment, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    os.chmod(keystore, 0o600)
    exported = subprocess.check_output(['keytool', '-exportcert', '-keystore', str(keystore),
                                       '-alias', 'lazer-release', '-storepass:env', 'LAZER_SIGNING_PASSWORD'],
                                      env=environment, stderr=subprocess.PIPE)
    contents = ('storeFile=' + str(keystore) + '\nstorePassword=' + password +
                '\nkeyAlias=lazer-release\nkeyPassword=' + password + '\n')
    for path, data in ((properties, contents), (private / 'password.txt', password + '\n')):
        with path.open('x', encoding='utf-8') as output:
            os.chmod(path, 0o600)
            output.write(data)
    for name in ('release.p12', 'password.txt'):
        shutil.copyfile(private / name, backup / name)
        os.chmod(backup / name, 0o600)
        require((private / name).read_bytes() == (backup / name).read_bytes(), 'Signing backup mismatch.')
    write_json(identity, {'packageName': PACKAGE, 'signerSha256': [hashlib.sha256(exported).hexdigest()],
                          'distribution': 'LifeAxis independent edition',
                          'upstreamPackageName': 'dev.naominet.lazer',
                          'upstreamUpgradeCompatible': False,
                          'authorization': 'User approved independent first release on 2026-11-05.'})
    print('Independent release identity initialized; public certificate: ' + str(identity))
    print('Private signing material and local backup secured outside the repository.')
    print('Backup directory (copy securely to another device): ' + str(backup))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--initialize-independent-app', action='store_true')
    try:
        initialize(parser.parse_args())
    except (ValueError, OSError, subprocess.CalledProcessError) as failure:
        print('Signing initialization stopped: ' + str(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
