"use client";

import { useState } from "react";
import { Camera, Image } from "lucide-react";

export default function RecognizePage() {
  const [preview, setPreview] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);

  const onPickFile = (file: File | undefined) => {
    if (!file) return;
    if (preview) URL.revokeObjectURL(preview);
    setPreview(URL.createObjectURL(file));
    setFileName(file.name);
  };

  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50 overflow-y-auto p-4 pb-[calc(var(--nav-h)+1rem)]">
      <header className="mb-6">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">Розпізнати</h1>
        <p className="text-ink-muted text-sm mt-1">Сфотографуйте гриб — визначимо вид</p>
      </header>

      <section className="rounded-2xl bg-white p-5 shadow-soft border border-cream-300 mb-6">
        <label
          htmlFor="mushroom-photo"
          className="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed border-cream-300 bg-cream-50 px-4 py-12 text-center transition-colors hover:border-forest"
        >
          <Camera size={28} className="text-forest" />
          <span className="font-semibold text-forest-dark">Додати фото гриба</span>
          <span className="text-xs text-ink-muted">
            Натисніть, щоб обрати фото з галереї або зробити знімок камерою
          </span>
        </label>
        <input
          id="mushroom-photo"
          type="file"
          accept="image/*"
          capture="environment"
          className="hidden"
          onChange={(e) => onPickFile(e.target.files?.[0])}
        />

        {preview && (
          <div className="mt-4">
            <img
              src={preview}
              alt="Обране фото гриба"
              className="max-h-64 w-full rounded-xl object-cover"
            />
            <p className="mt-2 truncate text-xs text-ink-muted">{fileName}</p>
          </div>
        )}

        <p className="mt-4 rounded-xl bg-cream-100 p-3 text-xs text-ink-muted">
          Нейромережеве розпізнавання буде підключене окремим релізом. Наразі
          скористайтеся вкладкою «Безпека», щоб перевірити небезпечні види.
        </p>
      </section>
    </div>
  );
}