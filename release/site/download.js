(() => {
  'use strict';
  const select = (id) => document.getElementById(id);
  const button = select('apk-download');
  const retry = select('retry');
  const status = select('download-status');
  const area = select('download');

  function validate(manifest) {
    if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) throw new Error('清单格式错误');
    const url = new URL(manifest.apkUrl);
    if (!Number.isSafeInteger(manifest.versionCode) || manifest.versionCode < 1 || manifest.versionCode > 2100000000 ||
        typeof manifest.versionName !== 'string' || !/^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$/.test(manifest.versionName) ||
        typeof manifest.notes !== 'string' || manifest.notes.length > 65536 || typeof manifest.mandatory !== 'boolean' ||
        typeof manifest.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(manifest.sha256) ||
        !Number.isSafeInteger(manifest.sizeBytes) || manifest.sizeBytes < 1 || manifest.sizeBytes > 1073741824 ||
        manifest.packageName !== 'fun.lifeaxis.lazer' || !Number.isInteger(manifest.minSdk) || manifest.minSdk < 26 ||
        !Array.isArray(manifest.abis) || !manifest.abis.length ||
        manifest.abis.some((abi) => !['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'].includes(abi)) ||
        url.origin !== 'https://lazer.lifeaxis.fun' || url.username || url.password || url.search || url.hash ||
        !/^\/lazer\/[A-Za-z0-9][A-Za-z0-9._-]*\.apk$/.test(url.pathname)) {
      throw new Error('发布信息不完整或下载地址不可信');
    }
    return url.href;
  }

  async function load() {
    area.setAttribute('aria-busy', 'true');
    retry.hidden = true;
    button.removeAttribute('href');
    button.setAttribute('aria-disabled', 'true');
    select('download-label').textContent = '正在获取 Android 安装包…';
    status.textContent = '正在读取 Lazer 的发布信息';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    try {
      const manifestUrl = new URL('./version.json', window.location.href);
      if (manifestUrl.pathname !== '/lazer/version.json') throw new Error('下载页目录不正确');
      manifestUrl.searchParams.set('t', String(Date.now()));
      const response = await fetch(manifestUrl, {
        cache: 'no-store', credentials: 'omit', redirect: 'error', signal: controller.signal,
      });
      if (!response.ok) throw new Error(`服务器返回 HTTP ${response.status}`);
      const text = await response.text();
      if (text.length > 131072) throw new Error('发布清单过大');
      const manifest = JSON.parse(text);
      const apkUrl = validate(manifest);
      const size = `${(manifest.sizeBytes / 1048576).toLocaleString('zh-CN', { maximumFractionDigits: 1 })} MiB`;
      const system = manifest.minSdk === 26 ? 'Android 8.0 及以上' : `Android API ${manifest.minSdk} 及以上`;
      select('version').textContent = `${manifest.versionName} · build ${manifest.versionCode}`;
      select('requirements').textContent = system;
      select('size').textContent = `${size}（${manifest.sizeBytes.toLocaleString('zh-CN')} 字节）`;
      select('architectures').textContent = manifest.abis.join(' / ');
      select('notes').textContent = manifest.notes || '此版本未附加更新说明。';
      select('checksum').textContent = manifest.sha256;
      select('download-label').textContent = '下载 Android 版';
      status.textContent = `v${manifest.versionName} · ${size} · ${system}`;
      button.href = apkUrl;
      button.setAttribute('download', new URL(apkUrl).pathname.split('/').pop());
      button.removeAttribute('aria-disabled');
    } catch (failure) {
      select('download-label').textContent = '暂时无法获取安装包';
      status.textContent = '无法确认最新版本，请检查网络后重试。为避免下载错误文件，下载已暂停。';
      retry.hidden = false;
    } finally {
      clearTimeout(timeout);
      area.setAttribute('aria-busy', 'false');
    }
  }
  retry.addEventListener('click', load);
  load();
})();
