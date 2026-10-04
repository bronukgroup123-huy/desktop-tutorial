export default function Home() {
  return (
    <div className="max-w-2xl mx-auto p-6">
      <h1 className="text-3xl font-bold mb-4">MushroomRadar Guardian</h1>
      <p className="text-gray-600 mb-6">
        Веб-інтерфейс для Наглядачів грибників. Якщо ви отримали посилання
        від грибника — просто відкрийте його.
      </p>

      <div className="bg-white rounded-lg shadow p-6 mb-4">
        <h2 className="font-semibold text-lg mb-3">Як це працює</h2>
        <ol className="list-decimal list-inside space-y-2 text-gray-700">
          <li>Грибник надсилає вам посилання перед походом у ліс</li>
          <li>Ви відкриваєте його — бачите карту в реальному часі</li>
          <li>У разі SOS — миттєве сповіщення з координатами</li>
          <li>Можете завантажити GPX-трек для рятувальників</li>
        </ol>
      </div>

      <div className="bg-blue-50 rounded-lg p-4 text-sm text-blue-900">
        <strong>Порада:</strong> встановіть цю сторінку на домашній екран,
        щоб отримувати push-повідомлення навіть коли браузер закритий.
      </div>
    </div>
  );
}
