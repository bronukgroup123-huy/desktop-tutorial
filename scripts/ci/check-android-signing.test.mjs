import assert from "node:assert/strict";
import test from "node:test";
import { validateAndroidSigningSeparation } from "./check-android-signing.mjs";

const gradle = `
val hasReleaseKey = true
val requireReleaseSigning = providers.gradleProperty("requireReleaseSigning").orNull == "true"
if (configured.isNotEmpty() && !hasReleaseKey) {
  throw GradleException("Incomplete Android release signing configuration")
}
if (requireReleaseSigning && !hasReleaseKey) {
  throw GradleException("Store signing is required")
}`;

const testWorkflow = `
on:
  push:
jobs:
  build:
    env:
      ORG_GRADLE_PROJECT_requireReleaseSigning: 'false'
    run: flutter build apk --release && mv app-release.apk mushroom-radar-test.apk
`;

const storeWorkflow = `
on:
  workflow_dispatch:
jobs:
  build:
    env:
      A: \${{ secrets.ANDROID_KEYSTORE_BASE64 }}
      B: \${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
      C: \${{ secrets.ANDROID_KEY_ALIAS }}
      D: \${{ secrets.ANDROID_KEY_PASSWORD }}
      ORG_GRADLE_PROJECT_requireReleaseSigning: 'true'
    run: |
      missing=0
      for secret_name in KEYSTORE_BASE64 KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do true; done
      if [ "$missing" -ne 0 ]; then exit 1; fi
      flutter build appbundle --release
`;

test("valid setup separates test APK from a fail-closed store AAB", () => {
  assert.deepEqual(
    validateAndroidSigningSeparation({ gradle, testWorkflow, storeWorkflow }),
    { signingSecrets: 4 },
  );
});

test("store workflow cannot run automatically", () => {
  const automatic = storeWorkflow.replace("  workflow_dispatch:", "  push:");
  assert.throws(
    () => validateAndroidSigningSeparation({ gradle, testWorkflow, storeWorkflow: automatic }),
    /store bundle workflow must be manual-only|must not run on push/,
  );
});

test("test workflow cannot receive a store signing secret", () => {
  const unsafeTest = `${testWorkflow}\n# \${{ secrets.ANDROID_KEYSTORE_BASE64 }}`;
  assert.throws(
    () => validateAndroidSigningSeparation({ gradle, testWorkflow: unsafeTest, storeWorkflow }),
    /test APK workflow must not receive store signing secrets/,
  );
});

test("store workflow must enable the Gradle fail-closed guard", () => {
  const unguarded = storeWorkflow.replace(
    "ORG_GRADLE_PROJECT_requireReleaseSigning: 'true'",
    "ORG_GRADLE_PROJECT_requireReleaseSigning: 'false'",
  );
  assert.throws(
    () => validateAndroidSigningSeparation({ gradle, testWorkflow, storeWorkflow: unguarded }),
    /store bundle workflow must require real release signing/,
  );
});

test("store workflow must reject empty signing secrets before Gradle", () => {
  const noEarlyCheck = storeWorkflow.replace(
    'if [ "$missing" -ne 0 ]; then exit 1; fi',
    'echo "continue"',
  );
  assert.throws(
    () => validateAndroidSigningSeparation({ gradle, testWorkflow, storeWorkflow: noEarlyCheck }),
    /store bundle workflow must fail early when any signing secret is empty/,
  );
});

test("partial signing configuration must be rejected by Gradle", () => {
  const permissiveGradle = gradle.replace(
    'throw GradleException("Incomplete Android release signing configuration")',
    'println("incomplete")',
  );
  assert.throws(
    () => validateAndroidSigningSeparation({ gradle: permissiveGradle, testWorkflow, storeWorkflow }),
    /Gradle must reject partial release signing configuration/,
  );
});
