// ============================================================================
// GET /regions — pure handler (group 9.2)
//
// Віддає список 27 областей без геометрії (Flutter Home dropdown).
// Логіка винесена сюди, щоб тестувати без supabase-js/esm.sh —
// index.ts лише створює service_role-клієнт і викликає handleRegionsRequest.
// service_role обходить RLS (policy regions_read тільки для authenticated).
// ============================================================================

import { buildCorsHeaders } from "../cors.ts";

/** Мінімальний структурний тип Supabase-клієнта (як DbClient у db.ts).
 *  Postgrest-білдер — thenable (PromiseLike), а не Promise. */
export interface RegionsQueryClient {
  from(table: string): {
    select(cols: string): {
      order(
        column: string,
        opts?: { ascending?: boolean }
      ): PromiseLike<{ data: unknown; error: unknown }>;
    };
  };
}

/** Формат відповіді: без geometry — тільки атрибути для UI */
export interface RegionListItem {
  id: number;
  name: string;
  slug: string;
  koatuu: string | null;
  katottg: string | null;
}

const SELECT_COLUMNS = "id, name, slug, koatuu, katottg";

function jsonResponse(data: unknown, status: number, req: Request): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...buildCorsHeaders(req), "Content-Type": "application/json" },
  });
}

/**
 * Обробник GET /regions.
 *
 * Статуси: 204 OPTIONS | 405 non-GET | 200 {data} | 500 db_error.
 * Сортування по name (ascending) — стабільний UI.
 */
export async function handleRegionsRequest(
  db: RegionsQueryClient,
  req: Request
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
  }
  if (req.method !== "GET") {
    return jsonResponse({ error: "method_not_allowed" }, 405, req);
  }

  try {
    const { data, error } = await db
      .from("regions")
      .select(SELECT_COLUMNS)
      .order("name", { ascending: true });

    if (error) {
      console.error("regions query failed:", error);
      return jsonResponse({ error: "db_error" }, 500, req);
    }

    return jsonResponse({ data: (data as RegionListItem[]) ?? [] }, 200, req);
  } catch (err) {
    console.error("regions error:", err);
    return jsonResponse({ error: "internal_error" }, 500, req);
  }
}
