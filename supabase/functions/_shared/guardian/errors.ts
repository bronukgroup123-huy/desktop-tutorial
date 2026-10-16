import { buildCorsHeaders, corsHeaders } from "../cors.ts";

export class AppError extends Error {
  constructor(
    public code: string,
    message: string,
    public status: number = 400,
    public details?: Record<string, unknown>
  ) {
    super(message);
    this.name = "AppError";
  }
}

export const Errors = {
  unauthorized: (msg = "Unauthorized") =>
    new AppError("unauthorized", msg, 401),

  forbidden: (msg = "Forbidden") =>
    new AppError("forbidden", msg, 403),

  notFound: (msg = "Not found") =>
    new AppError("not_found", msg, 404),

  validation: (msg: string, details?: Record<string, unknown>) =>
    new AppError("validation_error", msg, 422, details),

  conflict: (msg: string, details?: Record<string, unknown>) =>
    new AppError("conflict", msg, 409, details),

  invalidTransition: (from: string, to: string) =>
    new AppError(
      "invalid_transition",
      `Cannot transition from '${from}' to '${to}'`,
      409,
      { from, to }
    ),

  invalidToken: (msg = "Invalid or expired token") =>
    new AppError("invalid_token", msg, 401),

  rateLimited: (msg = "Too many requests") =>
    new AppError("rate_limited", msg, 429),

  internal: (msg = "Internal server error") =>
    new AppError("internal_error", msg, 500),
};

export interface ApiErrorResponse {
  error: string;
  message: string;
  details?: Record<string, unknown>;
}

export interface ApiSuccessResponse<T> {
  data: T;
}

export function errorResponse(err: unknown, req?: Request): Response {
  if (err instanceof AppError) {
    const body: ApiErrorResponse = {
      error: err.code,
      message: err.message,
      ...(err.details ? { details: err.details } : {}),
    };
    const headers = req ? buildCorsHeaders(req) : corsHeaders;
    return new Response(JSON.stringify(body), {
      status: err.status,
      headers: { ...headers, "Content-Type": "application/json" },
    });
  }

  const message = err instanceof Error ? err.message : "Unknown error";
  console.error("[Unhandled error]", err);
  const headers = req ? buildCorsHeaders(req) : corsHeaders;
  return new Response(
    JSON.stringify({ error: "internal_error", message }),
    {
      status: 500,
      headers: { ...headers, "Content-Type": "application/json" },
    }
  );
}

export function successResponse<T>(data: T, status = 200, req?: Request): Response {
  const headers = req ? buildCorsHeaders(req) : corsHeaders;
  return new Response(JSON.stringify({ data }), {
    status,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

export function withErrorHandling(
  handler: (req: Request) => Promise<Response>
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
    }

    // Global body size limit (DoS protection)
    const contentLength = req.headers.get("content-length");
    const MAX_BODY_SIZE = 8 * 1024 * 1024; // 8 MiB
    if (contentLength && parseInt(contentLength, 10) > MAX_BODY_SIZE) {
      return errorResponse(
        new AppError(
          "payload_too_large",
          `Request body exceeds 8 MB`,
          413
        )
      );
    }

    try {
      return await handler(req);
    } catch (err) {
      return errorResponse(err, req);
    }
  };
}
