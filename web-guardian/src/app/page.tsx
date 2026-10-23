export default function Home() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-900 text-white">
      <div className="text-center">
        <h1 className="text-4xl font-bold mb-4">Mushroom Radar Guardian API</h1>
        <p className="text-gray-400 mb-8">
          Це сервіс для Наглядачів. Якщо ви грибник, завантажте мобільний додаток.
        </p>
        <a
          href="/landing.html"
          className="text-emerald-400 underline hover:text-emerald-300"
        >
          Переглянути прототип додатку грибника
        </a>
      </div>
    </div>
  );
}