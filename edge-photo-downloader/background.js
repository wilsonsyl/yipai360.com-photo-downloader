let activeJob = null;
function broadcast(message) {
  chrome.runtime.sendMessage(message).catch(() => {});
}
async function sendProgressUpdate() {
  if (!activeJob) return;
  const percent = activeJob.total > 0 ? Math.round((activeJob.completed / activeJob.total) * 100) : 0;
  broadcast({
    type: 'DOWNLOAD_PROGRESS',
    progress: {
      total: activeJob.total,
      completed: activeJob.completed,
      failed: activeJob.failed,
      percent,
      statusText: `${activeJob.completed} / ${activeJob.total} completed${activeJob.failed ? `, ${activeJob.failed} failed` : ''}`
    }
  });
}
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== 'START_DOWNLOADS') return;
  (async () => {
    try {
      const payload = message.payload || {};
      const orderId = payload.orderId || 'album';
      const quality = payload.quality || 'original';
      const photos = Array.isArray(payload.photos) ? payload.photos : [];
      activeJob = { orderId, quality, total: photos.length, completed: 0, failed: 0 };
      await sendProgressUpdate();
      sendResponse({ ok: true });
      for (let i = 0; i < photos.length; i += 1) {
        const photo = photos[i];
        const url = photo.url;
        if (!url) {
          activeJob.failed += 1;
          await sendProgressUpdate();
          continue;
        }
        const filename = (photo.filename || `photo_${String(i + 1).padStart(3, '0')}.jpg`).replace(/[\\/:*?"<>|]/g, '_');
        try {
          await chrome.downloads.download({
            url,
            filename: `yipai360/${orderId}/${quality}/${filename}`,
            saveAs: false,
            conflictAction: 'uniquify'
          });
          activeJob.completed += 1;
        } catch (e) {
          activeJob.failed += 1;
        }
        await sendProgressUpdate();
      }
      const percent = activeJob.total > 0 ? Math.round((activeJob.completed / activeJob.total) * 100) : 100;
      broadcast({
        type: 'DOWNLOAD_DONE',
        progress: {
          total: activeJob.total,
          completed: activeJob.completed,
          failed: activeJob.failed,
          percent,
          statusText: `Finished: ${activeJob.completed} completed, ${activeJob.failed} failed`
        }
      });
      activeJob = null;
    } catch (err) {
      broadcast({ type: 'DOWNLOAD_ERROR', error: err?.message || String(err) });
      activeJob = null;
      try { sendResponse({ ok: false, error: err?.message || String(err) }); } catch {}
    }
  })();
  return true;
});
