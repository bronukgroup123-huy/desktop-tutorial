// ============================================================================
// Textbee SMS adapter — unit tests (audit G3 Phase B)
// Мок fetch (без реальних викликів API).
// ============================================================================

import { assertEquals, assert } from 'jsr:@std/assert';
import {
  sendSmsViaTextbee,
  isTextbeePermanentError,
  isTextbeeRateLimited,
} from '../../functions/_shared/guardian/notifications/textbee.ts';

const originalFetch = globalThis.fetch;

type EnvVars = Record<string, string>;

/** Тимчасово встановлює env-змінні, повертає awaitable з результатом fn */
async function withEnv<T>(vars: EnvVars, fn: () => Promise<T> | T): Promise<T> {
  const saved = new Map<string, string | undefined>();
  for (const k of Object.keys(vars)) saved.set(k, Deno.env.get(k));
  for (const [k, v] of Object.entries(vars)) Deno.env.set(k, v);

  try {
    return await fn();
  } finally {
    for (const [k, v] of saved) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

function mockFetch(
  handler: (url: string, init?: RequestInit) => Response | Promise<Response>
) {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  globalThis.fetch = ((url: string, init?: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(handler(url, init));
  }) as typeof fetch;
  return calls;
}

function restore() {
  globalThis.fetch = originalFetch;
}

const OK_SEND = {
  data: {
    success: true,
    smsBatchId: 'batch-123',
    recipientCount: 1,
  },
};

// ─── 1. disabled ────────────────────────────────────────────────────────────

Deno.test('textbee: TEXTBEE_ENABLED != true → textbee_disabled (без fetch)', async () => {
  const calls = mockFetch(() => new Response('should not be called'));
  const result = await withEnv({ TEXTBEE_ENABLED: 'false' }, () =>
    sendSmsViaTextbee({ phone: '+380671234567', text: 'test' })
  );
  restore();

  assertEquals(result.success, false);
  assertEquals(result.queued, false);
  assertEquals(result.errorMessage, 'textbee_disabled');
  assertEquals(calls.length, 0, 'fetch не повинен викликатись');
});

// ─── 2. happy path ──────────────────────────────────────────────────────────

Deno.test('textbee: 200 + success → {success:true, queued:true, providerMessageId}', async () => {
  const calls = mockFetch(() => new Response(JSON.stringify(OK_SEND), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  }));

  const result = await withEnv(
    { TEXTBEE_ENABLED: 'true', TEXTBEE_API_KEY: 'k' },
    () => sendSmsViaTextbee({ phone: '+380671234567', text: 'SOS!' })
  );
  restore();

  assertEquals(result.success, true);
  assertEquals(result.queued, true, 'acceptance != delivery — queued');
  assertEquals(result.providerMessageId, 'batch-123');
  assertEquals(calls.length, 1);
  assertEquals(calls[0].url, 'https://api.textbee.dev/api/v1/gateway/send-sms');
});

Deno.test('textbee: шле x-api-key header + recipients/message body', async () => {
  const calls = mockFetch(() => new Response(JSON.stringify(OK_SEND), { status: 200 }));
  await withEnv(
    { TEXTBEE_ENABLED: 'true', TEXTBEE_API_KEY: 'SECRET-KEY' },
    () => sendSmsViaTextbee({ phone: '380671234567', text: 'hello' })
  );
  restore();

  const init = calls[0].init as RequestInit;
  const headers = init.headers as Record<string, string>;
  assertEquals(headers['x-api-key'], 'SECRET-KEY');
  const body = JSON.parse(init.body as string);
  assertEquals(body.message, 'hello');
  assertEquals(body.recipients, ['+380671234567'], 'нормалізація +380');
  assert(!('deviceId' in body), 'deviceId опційний — не шлемо без env');
});

// ─── 3. error mapping ───────────────────────────────────────────────────────

Deno.test('textbee: 401 → success:false (permanent)', async () => {
  mockFetch(() => new Response('Unauthorized', { status: 401 }));
  const result = await withEnv(
    { TEXTBEE_ENABLED: 'true', TEXTBEE_API_KEY: 'bad' },
    () => sendSmsViaTextbee({ phone: '+380671234567', text: 'x' })
  );
  restore();
  assertEquals(result.success, false);
  assert(result.errorMessage?.includes('401'), result.errorMessage);
  assertEquals(isTextbeePermanentError(result.errorMessage ?? ''), true);
});

Deno.test('textbee: 429 → success:false, rate-limited (не permanent)', async () => {
  mockFetch(() => new Response('plan limit used up', { status: 429 }));
  const result = await withEnv(
    { TEXTBEE_ENABLED: 'true', TEXTBEE_API_KEY: 'k' },
    () => sendSmsViaTextbee({ phone: '+380671234567', text: 'x' })
  );
  restore();
  assertEquals(result.success, false);
  assertEquals(isTextbeeRateLimited(result.errorMessage ?? ''), true);
  assertEquals(isTextbeePermanentError(result.errorMessage ?? ''), false, '429 — transient');
});

Deno.test('textbee: 500 → transient (не permanent)', async () => {
  mockFetch(() => new Response('server error', { status: 500 }));
  const result = await withEnv(
    { TEXTBEE_ENABLED: 'true', TEXTBEE_API_KEY: 'k' },
    () => sendSmsViaTextbee({ phone: '+380671234567', text: 'x' })
  );
  restore();
  assertEquals(result.success, false);
  assertEquals(isTextbeePermanentError(result.errorMessage ?? ''), false);
  assertEquals(isTextbeeRateLimited(result.errorMessage ?? ''), false);
});

Deno.test('textbee: invalid phone → textbee_invalid_phone, без fetch', async () => {
  const calls = mockFetch(() => new Response('nope', { status: 500 }));
  const result = await withEnv(
    { TEXTBEE_ENABLED: 'true', TEXTBEE_API_KEY: 'k' },
    () => sendSmsViaTextbee({ phone: '12345', text: 'x' })
  );
  restore();
  assertEquals(result.success, false);
  assert(result.errorMessage?.includes('invalid_phone'), result.errorMessage);
  assertEquals(calls.length, 0);
});

Deno.test('textbee: bandwidth — message truncate 480', async () => {
  const calls = mockFetch(() => new Response(JSON.stringify(OK_SEND), { status: 200 }));
  await withEnv({ TEXTBEE_ENABLED: 'true', TEXTBEE_API_KEY: 'k' }, () =>
    sendSmsViaTextbee({ phone: '+380671234567', text: 'A'.repeat(1000) })
  );
  restore();
  const body = JSON.parse((calls[0].init as RequestInit).body as string);
  assertEquals(body.message.length, 480);
});

// ─── 4. classification helpers ──────────────────────────────────────────────

Deno.test('isTextbeePermanentError: 400/401 → true, 429/500 → false', () => {
  assertEquals(isTextbeePermanentError('textbee_http_400: no device'), true);
  assertEquals(isTextbeePermanentError('textbee_http_401: bad key'), true);
  assertEquals(isTextbeePermanentError('textbee_http_404: gone'), true);
  assertEquals(isTextbeePermanentError('textbee_no_api_key'), true);
  assertEquals(isTextbeePermanentError('textbee_invalid_phone: 1'), true);
  assertEquals(isTextbeePermanentError('textbee_http_429: limit'), false);
  assertEquals(isTextbeePermanentError('textbee_http_500: oops'), false);
  assertEquals(isTextbeePermanentError('textbee_network: timeout'), false);
});

Deno.test('isTextbeeRateLimited: 429/plan → true, інше → false', () => {
  assertEquals(isTextbeeRateLimited('textbee_http_429: daily limit'), true);
  assertEquals(isTextbeeRateLimited('textbee: monthly plan limit used up'), true);
  assertEquals(isTextbeeRateLimited('textbee_rate_limited'), true);
  assertEquals(isTextbeeRateLimited('textbee_http_400: no device'), false);
  assertEquals(isTextbeeRateLimited('textbee_network: reset'), false);
});
