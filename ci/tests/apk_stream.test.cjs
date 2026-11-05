const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

async function main() {
  const template = fs.readFileSync(path.join(__dirname, '../../release/apk_stream.js'), 'utf8');
  const parts = [Buffer.from('signed '), Buffer.from('APK bytes')];
  const metadata = {filename: 'Lazer-test-9.apk', sizeBytes: 16, sha256: 'a'.repeat(64),
    chunks: parts.map((part, index) => ({path: `/lazer/apk-parts/test/part-${index}.bin`, sizeBytes: part.length}))};
  const source = template.replace('__APK_METADATA__', JSON.stringify(metadata));
  const {default: handler} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
  const originalFetch = global.fetch;
  const originalAbortController = global.AbortController;
  let requests = [];
  let mode = 'valid';
  global.fetch = async (url, options) => {
    requests.push(url);
    assert.equal(new URL(url).origin, 'https://updates.lifeaxis.fun');
    assert.equal(options.redirect, 'error');
    const index = Number(/part-(\d)/.exec(url)[1]);
    const data = mode === 'truncated' ? parts[index].subarray(1) : parts[index];
    return new Response(data, {status: mode === 'missing' ? 404 : 200,
      headers: {'Content-Length': mode === 'bad-length' ? '999' : String(parts[index].length)}});
  };
  const context = (method = 'GET') => ({request: new Request(
    'https://updates.lifeaxis.fun/lazer/Lazer-test-9.apk', {method})});
  try {
    const head = await handler(context('HEAD'));
    assert.equal(head.status, 200);
    assert.equal(head.headers.get('Content-Length'), '16');
    assert.equal(requests.length, 0);
    const response = await handler(context());
    assert.equal(response.headers.get('Content-Type'), 'application/vnd.android.package-archive');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), Buffer.concat(parts));
    assert.equal(requests.length, 2);
    assert.equal((await handler(context('POST'))).status, 405);
    for (const failure of ['missing', 'bad-length', 'truncated']) {
      mode = failure;
      const failed = await handler(context());
      await assert.rejects(failed.arrayBuffer());
    }
    mode = 'valid';
    const cancelled = await handler(context());
    await cancelled.body.cancel();
    const withoutAbortContext = context();
    global.AbortController = undefined;
    const withoutAbort = await handler(withoutAbortContext);
    assert.deepEqual(Buffer.from(await withoutAbort.arrayBuffer()), Buffer.concat(parts));
    console.log('APK stream: exact ordered bytes, bounded parts, HEAD, methods, failures and cancellation passed');
  } finally {
    global.fetch = originalFetch;
    global.AbortController = originalAbortController;
  }
}

main().catch((failure) => {console.error(failure); process.exitCode = 1;});
