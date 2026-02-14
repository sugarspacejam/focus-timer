chrome.action.onClicked.addListener(() => {
  chrome.tabs.create({
    url: chrome.runtime.getURL('index.html')
  });
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'timerComplete') {
    chrome.notifications.create({
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: "JOB'S NOT FINISHED",
      message: 'Block complete. Start another one. No excuses.',
      priority: 2
    });
  }
});
