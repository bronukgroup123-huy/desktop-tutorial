importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

const urlParams = new URL(self.location.href).searchParams;
const apiKey = urlParams.get('apiKey');

if (apiKey) {
  const firebaseConfig = {
    apiKey: apiKey,
    projectId: urlParams.get('projectId'),
    messagingSenderId: urlParams.get('messagingSenderId'),
    appId: urlParams.get('appId'),
  };

  try {
    firebase.initializeApp(firebaseConfig);
    const messaging = firebase.messaging();

    messaging.onBackgroundMessage((payload) => {
      console.log('[SW] Background message:', payload);
      const notificationTitle = payload.notification?.title || 'Грибний Радар';
      const notificationOptions = {
        body: payload.notification?.body || 'Нове сповіщення',
        icon: '/icons/icon-192.png',
        data: payload.data
      };
      self.registration.showNotification(notificationTitle, notificationOptions);
    });
  } catch (error) {
    console.error('[SW] Firebase init error:', error);
  }
} else {
  console.warn('[SW] No apiKey provided. Skipping Firebase init.');
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.openWindow('/s/' + (event.notification.data?.token || ''))
  );
});
