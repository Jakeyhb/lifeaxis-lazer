"""Represent an immutable APK using bounded static parts and an exact edge route."""

import json
from pathlib import Path

from release_android import ROOT, fingerprint, require

CHUNK_BYTES = 20 * 1024 * 1024
STATIC_LIMIT = 25 * 1024 * 1024


def prepare_transport(staging, apk_name, manifest):
    apk_path = staging / 'lazer' / apk_name
    require(fingerprint(apk_path) == {key: manifest[key] for key in ('sha256', 'sizeBytes')},
            'APK changed before transport preparation.')
    if apk_path.stat().st_size <= STATIC_LIMIT:
        return {}, {}, {}
    relative_directory = 'lazer/apk-parts/' + apk_name.removesuffix('.apk')
    directory = staging / relative_directory
    require(not directory.exists(), 'Refusing to overwrite immutable APK chunks.')
    directory.mkdir(parents=True)
    chunks = []
    static = {}
    with apk_path.open('rb') as source:
        while data := source.read(CHUNK_BYTES):
            relative = relative_directory + '/part-{:03d}.bin'.format(len(chunks))
            part = staging / relative
            part.write_bytes(data)
            metadata = fingerprint(part)
            static[relative] = metadata
            chunks.append(dict(metadata, path='/' + relative))
    function_name = 'edge-functions/lazer/' + apk_name + '.js'
    function = staging / function_name
    require(not function.exists(), 'Refusing to overwrite an immutable APK function.')
    function.parent.mkdir(parents=True, exist_ok=True)
    metadata = {key: manifest[key] for key in ('sizeBytes', 'sha256')}
    metadata.update(filename=apk_name, chunks=chunks)
    template = (ROOT / 'release/apk_stream.js').read_text(encoding='utf-8')
    require(template.count('__APK_METADATA__') == 1, 'Invalid APK stream template.')
    function.write_text(template.replace('__APK_METADATA__', json.dumps(metadata)), encoding='utf-8')
    apk_path.unlink()
    return static, {function_name: fingerprint(function)}, {'lazer/' + apk_name: {
        key: manifest[key] for key in ('sha256', 'sizeBytes')}}


def check_static_sizes(staging):
    for path in Path(staging).rglob('*'):
        if path.is_file():
            require(path.stat().st_size <= STATIC_LIMIT, 'EdgeOne 25 MiB file limit exceeded: ' + str(path))
