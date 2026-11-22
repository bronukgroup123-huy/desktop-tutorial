/** True only for requests authenticated with this project's service-role key. */
export function isServiceRoleRequest(
  req: Request,
  serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
): boolean {
  if (!serviceRoleKey) return false;
  return req.headers.get("Authorization") === `Bearer ${serviceRoleKey}`;
}
