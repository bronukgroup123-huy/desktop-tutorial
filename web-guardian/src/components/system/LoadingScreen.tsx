export function LoadingScreen() {
  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-600 mb-4" />
      <p className="text-gray-600">Завантаження...</p>
    </div>
  );
}
