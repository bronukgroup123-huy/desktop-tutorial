import {
  requireMushroomPicker,
  parseBody,
  CreateSessionSchema,
  Errors,
  successResponse,
  withErrorHandling,
} from "../_shared/guardian/index.ts";
import {
  generateGuardianToken,
  buildGuardianUrl,
} from "../_shared/guardian/token.ts";
import {
  getActiveSessionByUser,
  mergeSettings,
  DEFAULT_SESSION_SETTINGS,
} from "../_shared/guardian/db.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const input = await parseBody(req, CreateSessionSchema);

  const existing = await getActiveSessionByUser(db, userId);
  if (existing) {
    throw Errors.conflict("User already has an active session", {
      session_id: existing.id,
      status: existing.status,
    });
  }

  const expectedReturn = new Date(input.expected_return);
  if (expectedReturn <= new Date()) {
    throw Errors.validation("expected_return must be in the future");
  }

  const settings = mergeSettings(input.settings);

  const { data: session, error: sessionError } = await db
    .from("guardian_sessions")
    .insert({
      user_id: userId,
      status: "pending",
      expected_return: expectedReturn.toISOString(),
      original_return: expectedReturn.toISOString(),
      settings,
    })
    .select("*")
    .single();

  if (sessionError || !session) {
    throw Errors.internal(`Failed to create session: ${sessionError?.message}`);
  }

  const createdGuardians: Array<{
    id: string;
    name: string | null;
    token: string;
    url: string;
  }> = [];

  for (const g of input.guardians) {
    const { data: guardianRow, error: guardianError } = await db
      .from("guardians")
      .insert({
        session_id: session.id,
        name: g.name,
        phone: g.phone,
        token_hash: "PENDING",
        token_prefix: "PENDING",
        is_emergency: g.is_emergency,
      })
      .select("id, name")
      .single();

    if (guardianError || !guardianRow) {
      throw Errors.internal(
        `Failed to create guardian: ${guardianError?.message}`
      );
    }

    const generated = await generateGuardianToken(session.id, guardianRow.id);

    const { error: updateError } = await db
      .from("guardians")
      .update({
        token_hash: generated.tokenHash,
        token_prefix: generated.tokenPrefix,
      })
      .eq("id", guardianRow.id);

    if (updateError) {
      throw Errors.internal(
        `Failed to update guardian token: ${updateError.message}`
      );
    }

    createdGuardians.push({
      id: guardianRow.id,
      name: guardianRow.name,
      token: generated.token,
      url: buildGuardianUrl(generated.token),
    });
  }

  return successResponse({
    session,
    guardians: createdGuardians,
  }, 201);
}));
