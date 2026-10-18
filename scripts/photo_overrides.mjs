// ============================================================================
// PHOTO OVERRIDES
// Жорстке прив'язування української назви виду до латинського імені файла
// у Supabase Storage. Потрібне для 6 видів, чії фото не завантажуються,
// бо поточна sanitizePath() некоректно обробляє кирилицю, пробіли та дужки.
// ============================================================================

export const PHOTO_OVERRIDES_BY_NAME = {
  'Гомф булавоподібний': 'gomphus_clavatus.webp',
  'Квітохвісник Арчера': 'anthurus_archeri.webp',
  'Міріостома шийкова': 'myriostoma_coliforme.webp',
  'Фелоринія геркулесова': 'phellorinia_herculeana.webp',
  'Хрящ-молочник чорний': 'lactarius_lignyotus.webp',
  'Шишкогриб лускатий': 'strobilomyces_strobilaceus.webp',
};

/**
 * Повертає латійське ім'я файла (з розширенням .webp) для української назви виду,
 * або null, якщо перевиз для цього виду не задано.
 * Ігнорує текст в дужках в кінці назви (наприклад "Навид (додаток)").
 */
export function resolveOverride(nameUa) {
  if (typeof nameUa !== 'string' || nameUa.length === 0) {
    return null;
  }
  const key = nameUa.replace(/\s*\([^)]*\)\s*$/, '').trim();
  return PHOTO_OVERRIDES_BY_NAME[key] ?? null;
}

/**
 * Повертає базове ім'я файла без розширення для перевизу, або null.
 * Наприклад 'Гомф булавоподібний' -> 'gomphus_clavatus'.
 */
export function overrideBase(nameUa) {
  const value = resolveOverride(nameUa);
  return value ? value.replace(/\.webp$/i, '') : null;
}
