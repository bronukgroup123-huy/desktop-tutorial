importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

// Публічний конфіг Firebase (не секретний, тому безпечно захардкодити в SW)
const firebaseConfig = {
  apiKey: "AIzaSyD...", // ВСТАВТЕ ВАШ API KEY (з Vercel env)
  projectId: "mushroom-radar-4fc75",
  messagingSenderId: "...", // ВСТАВТЕ SENDER ID
  appId: "..." // ВСТАВТЕ APP ID
};

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

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow('/s/' + (event.notification.data?.token || '')));
});
