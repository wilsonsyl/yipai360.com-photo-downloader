function getOrderId() {
  const u = new URL(window.location.href);
  return u.searchParams.get('orderId');
}

function buildUrl(img, preference = 'original') {
  if (!img || !img.path) return null;
  const base = img.primary || img.failover;
  if (!base) return null;
  if (preference === '1920' && img.s1920) return `${base}${img.path}${img.s1920}`;
  if (preference === '1080' && img.s1080) return `${base}${img.path}${img.s1080}`;
  if (preference === 'original' && img.sign) return `${base}${img.path}${img.sign}`;
  if (img.sign) return `${base}${img.path}${img.sign}`;
  if (img.s1920) return `${base}${img.path}${img.s1920}`;
  if (img.s1080) return `${base}${img.path}${img.s1080}`;
  if (img.s375) return `${base}${img.path}${img.s375}`;
  return `${base}${img.path}`;
}

async function fetchAllPhotos(orderId, quality) {
  const pageSize = 100;
  let page = 1;
  const results = [];
  while (true) {
    const apiUrl = `https://www.yipai360.com/api/v1/yipai/order/${encodeURIComponent(orderId)}/audience/photos?tagId=&sortType=desc&page=${page}&pageSize=${pageSize}`;
    const resp = await fetch(apiUrl, {
      method: 'GET',
      credentials: 'include',
      headers: { 'Accept': 'application/json, text/plain, */*' }
    });
    if (!resp.ok) throw new Error(`API failed on page ${page}: ${resp.status}`);
    const json = await resp.json();
    const data = json?.data;
    let items = [];
    if (Array.isArray(data)) {
      items = data;
    } else if (data && typeof data === 'object') {
      for (const value of Object.values(data)) {
        if (Array.isArray(value)) {
          items = value;
          break;
        }
      }
    }
    if (!items.length) break;
    for (const item of items) {
      const ext = item?.ext || 'jpg';
      const rawName = item?.fname || `${item?.photoId || 'photo'}.${ext}`;
      const dot = rawName.lastIndexOf('.');
      const baseName = dot > 0 ? rawName.slice(0, dot) : rawName;
      const filename = `${baseName}_${quality}.${ext}`;
      const url = buildUrl(item?.img, quality);
      results.push({ filename, url, photoId: item?.photoId || null, quality });
    }
    if (items.length < pageSize) break;
    page += 1;
  }
  return results.filter(x => !!x.url);
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== 'DOWNLOAD_ALBUM') return;
  (async () => {
    try {
      const orderId = getOrderId();
      const quality = message?.quality || 'original';
      if (!orderId) throw new Error('orderId not found in URL');
      const photos = await fetchAllPhotos(orderId, quality);
      sendResponse({ ok: true, count: photos.length, payload: { orderId, quality, photos } });
    } catch (err) {
      sendResponse({ ok: false, error: err?.message || String(err) });
    }
  })();
  return true;
});
