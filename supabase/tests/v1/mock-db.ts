// Мінімальний мок supabase-js для тестів v1-* (без мережі).
// Результати задаються за ключем "<table>.<op>" (op: select | update | insert | upsert)
// або "rpc.<fn>". Усі виклики записуються в `calls`.

export interface Result { data: unknown; error: unknown }
export type Results = Record<string, Result | ((call: Call) => Result)>;
export interface Call { key: string; table?: string; op?: string; args: unknown[]; filters: Array<[string, unknown]> }

export function mockDb(results: Results = {}) {
  const calls: Call[] = [];
  const resolve = (call: Call): Result => {
    const r = results[call.key];
    if (r === undefined) return { data: null, error: null };
    return typeof r === "function" ? r(call) : r;
  };

  const db = {
    calls,
    from(table: string) {
      const call: Call = { key: `${table}.select`, table, op: "select", args: [], filters: [] };
      const builder: Record<string, unknown> = {};
      const chain = (op?: string) => (...args: unknown[]) => {
        if (op) {
          call.op = op;
          call.key = `${table}.${op}`;
          call.args = args;
        }
        return builder;
      };
      builder.select = (...args: unknown[]) => {
        if (call.op === "select") call.args = args;
        return builder;
      };
      builder.update = chain("update");
      builder.insert = chain("insert");
      builder.upsert = chain("upsert");
      builder.eq = (col: string, val: unknown) => { call.filters.push([col, val]); return builder; };
      // Сортування й обмеження не впливають на мок — лише запам'ятовуються.
      builder.order = (col: string) => { call.filters.push(["order", col]); return builder; };
      builder.limit = (n: number) => { call.filters.push(["limit", n]); return builder; };
      builder.maybeSingle = () => { calls.push(call); return Promise.resolve(resolve(call)); };
      builder.single = builder.maybeSingle;
      builder.then = (onOk: (r: Result) => unknown, onErr?: (e: unknown) => unknown) => {
        calls.push(call);
        return Promise.resolve(resolve(call)).then(onOk, onErr);
      };
      return builder;
    },
    rpc(fn: string, params: Record<string, unknown>) {
      const call: Call = { key: `rpc.${fn}`, args: [params], filters: [] };
      calls.push(call);
      return Promise.resolve(resolve(call));
    },
  };
  return db;
}

/** Rate limit завжди дозволяє. */
export const RL_OK: Results = { "rpc.check_and_increment_ip_rate_limit": { data: { count: 1 }, error: null } };
export const RL_BLOCKED: Results = { "rpc.check_and_increment_ip_rate_limit": { data: { count: 999 }, error: null } };

export const verifyAs = (id: string, isAnonymous = false) => () => Promise.resolve({ id, isAnonymous });
export const verifyNone = () => Promise.resolve(null);

export function req(method: string, url: string, body?: unknown, headers: Record<string, string> = {}): Request {
  return new Request(url, {
    method,
    headers: { Authorization: "Bearer test-jwt", "Content-Type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
