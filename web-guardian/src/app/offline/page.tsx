export default function OfflinePage() {
  return (
    <div className="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <div className="text-6xl mb-4">📡</div>
      <h1 className="text-2xl font-bold mb-2">Немає з'єднання</h1>
      <p className="text-gray-600">
        Перевірте інтернет і спробуйте знову. Дані оновляться автоматично після підключення.
      </p>
    </div>
  );
}
