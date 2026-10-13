import { assertEquals } from 'jsr:@std/assert';
import {
  calibrate,
  CALIBRATION_TARGET,
  CALIBRATION_TOLERANCE,
  CALIBRATION_MAX_DELTA,
} from '../../functions/_shared/forecast/calibration.ts';
import type { CalibrationInput } from '../../functions/_shared/forecast/calibration.ts';

// ─── Helpers ───────────────────────────────────────────────

function pick(
  species: string,
  actualFound: boolean,
  predictedLevel: CalibrationInput['predictedLevel'] = 'medium',
): CalibrationInput {
  return { species, predictedLevel, actualFound, date: '2026-09-01' };
}

/** n picks виду, з яких found — з actualFound=true */
function batch(species: string, found: number, total: number): CalibrationInput[] {
  const logs: CalibrationInput[] = [];
  for (let i = 0; i < found; i++) logs.push(pick(species, true));
  for (let i = found; i < total; i++) logs.push(pick(species, false));
  return logs;
}

// ─── Tests ─────────────────────────────────────────────────

Deno.test('calibration: порожній масив → []', () => {
  assertEquals(calibrate([]), []);
});

Deno.test('calibration: precision=0.5 (в нормі) → []', () => {
  // 5/10 = 0.5 = TARGET — точно в нормі
  assertEquals(calibrate(batch('boletus_edulis', 5, 10)), []);
});

Deno.test('calibration: precision=0.2 (низька) → delta=-0.05', () => {
  const adjustments = calibrate(batch('boletus_edulis', 2, 10));
  assertEquals(adjustments.length, 1);
  assertEquals(adjustments[0].species, 'boletus_edulis');
  assertEquals(adjustments[0].param, 'weight');
  assertEquals(adjustments[0].delta, -0.05);
  assertEquals(adjustments[0].delta, -CALIBRATION_MAX_DELTA);
});

Deno.test('calibration: precision=0.8 (висока) → delta=+0.05', () => {
  const adjustments = calibrate(batch('boletus_edulis', 8, 10));
  assertEquals(adjustments.length, 1);
  assertEquals(adjustments[0].species, 'boletus_edulis');
  assertEquals(adjustments[0].param, 'weight');
  assertEquals(adjustments[0].delta, 0.05);
  assertEquals(adjustments[0].delta, CALIBRATION_MAX_DELTA);
});

Deno.test('calibration: межа precision=0.4 (=0.5-0.1) → []', () => {
  // 4/10 = 0.4 = TARGET - TOLERANCE — межовий випадок, у нормі (не < lower)
  assertEquals(CALIBRATION_TARGET - CALIBRATION_TOLERANCE, 0.4);
  assertEquals(calibrate(batch('boletus_edulis', 4, 10)), []);
});

Deno.test('calibration: межа precision=0.6 (=0.5+0.1) → []', () => {
  // 6/10 = 0.6 = TARGET + TOLERANCE — межовий випадок, у нормі (не > upper)
  assertEquals(CALIBRATION_TARGET + CALIBRATION_TOLERANCE, 0.6);
  assertEquals(calibrate(batch('boletus_edulis', 6, 10)), []);
});

Deno.test('calibration: no_data логи ігноруються', () => {
  // 10 no_data + 5/10 з реальним прогнозом = в нормі → []
  const logs: CalibrationInput[] = [];
  for (let i = 0; i < 10; i++) {
    logs.push({ species: 'boletus_edulis', predictedLevel: 'no_data', actualFound: true, date: '2026-09-01' });
  }
  logs.push(...batch('boletus_edulis', 5, 10));
  assertEquals(calibrate(logs), []);

  // всі логи no_data → [] (немає прогнозів)
  const onlyNoData: CalibrationInput[] = Array.from({ length: 10 }, () => ({
    species: 'cantharellus_cibarius', predictedLevel: 'no_data' as const, actualFound: true, date: '2026-09-01',
  }));
  assertEquals(calibrate(onlyNoData), []);
});

Deno.test('calibration: два види → два adjustments у правильному порядку', () => {
  const logs = [
    ...batch('boletus_edulis', 2, 10),   // precision 0.2 → -0.05
    ...batch('cantharellus_cibarius', 8, 10), // precision 0.8 → +0.05
  ];
  const adjustments = calibrate(logs);
  assertEquals(adjustments.length, 2);
  // порядок — за першою появою у logs
  assertEquals(adjustments[0].species, 'boletus_edulis');
  assertEquals(adjustments[0].delta, -0.05);
  assertEquals(adjustments[1].species, 'cantharellus_cibarius');
  assertEquals(adjustments[1].delta, 0.05);
});

Deno.test('calibration: вид у нормі не отримує adjustment', () => {
  const logs = [
    ...batch('boletus_edulis', 2, 10), // 0.2 → -0.05
    ...batch('cantharellus_cibarius', 5, 10), // 0.5 → skip
  ];
  const adjustments = calibrate(logs);
  assertEquals(adjustments.length, 1);
  assertEquals(adjustments[0].species, 'boletus_edulis');
});
