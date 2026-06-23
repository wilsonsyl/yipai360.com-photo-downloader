const statusEl = document.getElementById('status');
const btn = document.getElementById('downloadBtn');
const qualityEl = document.getElementById('quality');
const progressBar = document.getElementById('progressBar');
const progressText = document.getElementById('progressText');
const progressPercent = document.getElementById('progressPercent');

function setStatus(text) {
  statusEl.textContent = text;
}

function renderProgress(progress) {
  const total = progress?.total ?? 0;
  const completed = progress?.completed ?? 0;
  const percent = total > 0 ? Math.round((completed / total) * 100) : 0;
  progressBar.value = percent;
  progressText.textContent = `${completed} / ${total}`;
  progressPercent.textContent = `${percent}%`;
}

async function getActiveTab() {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  return tabs[0];
}

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === 'DOWNLOAD_PROGRESS') {
    renderProgress(message.progress);
    if (message.progress?.statusText) setStatus(message.progress.statusText);
  }
  if (message?.type === 'DOWNLOAD_DONE') {
    renderProgress(message.progress);
    setStatus(message.progress?.statusText || 'Downloads finished.');
    btn.disabled = false;
  }
  if (message?.type === 'DOWNLOAD_ERROR') {
    setStatus(message.error || 'Download failed.');
    btn.disabled = false;
  }
});

btn.addEventListener('click', async () => {
  btn.disabled = true;
  renderProgress({ total: 0, completed: 0 });
  try {
    const tab = await getActiveTab();
    if (!tab || !tab.id) {
      setStatus('No active tab found.');
      btn.disabled = false;
      return;
    }
    if (!/^https:\/\/www\.yipai360\.com\/(photolivepc|photoliveh5)\//.test(tab.url || '')) {
      setStatus('Open a Yipai360 album page first.');
      btn.disabled = false;
      return;
    }
    setStatus('Collecting photos...');
    const response = await chrome.tabs.sendMessage(tab.id, {
      type: 'DOWNLOAD_ALBUM',
      quality: qualityEl.value
    });
    if (!response) {
      setStatus('No response from page. Reload the album page and try again.');
      btn.disabled = false;
      return;
    }
    if (!response.ok) {
      setStatus('Error: ' + (response.error || 'Unknown error'));
      btn.disabled = false;
      return;
    }
    renderProgress({ total: response.count, completed: 0 });
    setStatus(`Found ${response.count} photos. Starting downloads...`);
    const startResp = await chrome.runtime.sendMessage({
      type: 'START_DOWNLOADS',
      payload: response.payload
    });
    if (!startResp?.ok) {
      setStatus(startResp?.error || 'Failed to start downloads.');
      btn.disabled = false;
    }
  } catch (err) {
    setStatus('Failed: ' + (err?.message || String(err)));
    btn.disabled = false;
  }
});
