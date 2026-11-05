export default async function onRequest(context) {
  const metadata = __APK_METADATA__;
  const request = context.request;
  if (!['GET', 'HEAD'].includes(request.method)) {
    return new Response('Method not allowed', {status: 405, headers: {Allow: 'GET, HEAD'}});
  }
  const headers = {
    'Content-Type': 'application/vnd.android.package-archive',
    'Content-Length': String(metadata.sizeBytes),
    'Content-Disposition': `attachment; filename="${metadata.filename}"`,
    'Cache-Control': 'public, max-age=31536000, immutable',
    'Accept-Ranges': 'none',
    'X-Content-Type-Options': 'nosniff',
    ETag: `"${metadata.sha256}"`,
  };
  if (request.method === 'HEAD') return new Response(null, {headers});
  let chunkIndex = 0;
  let reader = null;
  let received = 0;
  let cancelled = false;
  const abort = typeof AbortController === 'function' ? new AbortController() : null;
  const stream = new ReadableStream({
    async pull(controller) {
      try {
        while (!cancelled) {
          if (reader === null) {
            if (chunkIndex === metadata.chunks.length) {
              controller.close();
              return;
            }
            const chunk = metadata.chunks[chunkIndex];
            const response = await fetch(new URL(chunk.path, request.url).toString(), {
              redirect: 'error', ...(abort ? {signal: abort.signal} : {}),
            });
            if (cancelled) {
              await response.body?.cancel();
              return;
            }
            const declaredSize = response.headers.get('Content-Length');
            if (response.status !== 200 || !response.body ||
                (declaredSize !== null && Number(declaredSize) !== chunk.sizeBytes)) {
              await response.body?.cancel();
              throw new Error('APK chunk unavailable');
            }
            reader = response.body.getReader();
            received = 0;
          }
          const result = await reader.read();
          if (cancelled) return;
          if (result.done) {
            reader.releaseLock();
            reader = null;
            if (received !== metadata.chunks[chunkIndex].sizeBytes) throw new Error('Truncated APK chunk');
            chunkIndex += 1;
          } else {
            received += result.value.byteLength;
            if (received > metadata.chunks[chunkIndex].sizeBytes) throw new Error('Oversized APK chunk');
            controller.enqueue(result.value);
            return;
          }
        }
      } catch (failure) {
        abort?.abort();
        await reader?.cancel().catch(() => {});
        if (!cancelled) controller.error(failure);
      }
    },
    async cancel() {
      cancelled = true;
      abort?.abort();
      await reader?.cancel();
    },
  });
  return new Response(stream, {headers});
}
