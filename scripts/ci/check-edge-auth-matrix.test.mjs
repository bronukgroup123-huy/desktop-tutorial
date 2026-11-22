import assert from "node:assert/strict";
import test from "node:test";
import {
  parseFunctionJwtConfig,
  validateEdgeAuthMatrix,
} from "./check-edge-auth-matrix.mjs";

const validMatrix = {
  publicFn: "public",
  mixedFn: "mixed_handler_auth",
  userFn: "user_jwt",
  serviceFn: "service_role",
  webhookFn: "webhook_secret",
};

const validConfig = parseFunctionJwtConfig(`
[functions.publicFn]
verify_jwt = false
[functions.mixedFn]
verify_jwt = false
[functions.webhookFn]
verify_jwt = false
`);

test("valid matrix classifies every function and only bypasses explicit classes", () => {
  assert.deepEqual(
    validateEdgeAuthMatrix({
      deployedFunctions: Object.keys(validMatrix),
      matrix: validMatrix,
      jwtConfig: validConfig,
    }),
    { deployed: 5, bypass: 3 },
  );
});

test("new function without a classification fails closed", () => {
  assert.throws(
    () =>
      validateEdgeAuthMatrix({
        deployedFunctions: [...Object.keys(validMatrix), "newFn"],
        matrix: validMatrix,
        jwtConfig: validConfig,
      }),
    /unclassified deployed functions: newFn/,
  );
});

test("public or webhook function missing from the bypass config is rejected", () => {
  const config = new Map(validConfig);
  config.delete("webhookFn");
  assert.throws(
    () =>
      validateEdgeAuthMatrix({
        deployedFunctions: Object.keys(validMatrix),
        matrix: validMatrix,
        jwtConfig: config,
      }),
    /verify_jwt=false must exactly match the bypass allowlist/,
  );
});

test("user and service functions cannot disable platform JWT verification", () => {
  const config = new Map(validConfig);
  config.set("serviceFn", false);
  assert.throws(
    () =>
      validateEdgeAuthMatrix({
        deployedFunctions: Object.keys(validMatrix),
        matrix: validMatrix,
        jwtConfig: config,
      }),
    /serviceFn disables platform JWT verification/,
  );
});
