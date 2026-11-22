import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SIGNING_SECRETS = [
  "ANDROID_KEYSTORE_BASE64",
  "ANDROID_KEYSTORE_PASSWORD",
  "ANDROID_KEY_ALIAS",
  "ANDROID_KEY_PASSWORD",
];

export function validateAndroidSigningSeparation({ gradle, testWorkflow, storeWorkflow }) {
  const errors = [];

  if (!gradle.includes('providers.gradleProperty("requireReleaseSigning")')) {
    errors.push("Gradle must read the requireReleaseSigning property");
  }
  if (!gradle.includes("if (requireReleaseSigning && !hasReleaseKey)")) {
    errors.push("Gradle must fail when store signing is required but unavailable");
  }
  if (!gradle.includes("Incomplete Android release signing configuration")) {
    errors.push("Gradle must reject partial release signing configuration");
  }

  if (SIGNING_SECRETS.some((name) => testWorkflow.includes(`secrets.${name}`))) {
    errors.push("test APK workflow must not receive store signing secrets");
  }
  if (!testWorkflow.includes("ORG_GRADLE_PROJECT_requireReleaseSigning: 'false'")) {
    errors.push("test APK workflow must explicitly select test signing");
  }
  if (!testWorkflow.includes("mushroom-radar-test.apk")) {
    errors.push("test APK artifact must be clearly labelled as test-only");
  }
  if (/flutter build\s+appbundle/.test(testWorkflow)) {
    errors.push("test APK workflow must not produce an Android App Bundle");
  }

  if (!/^\s{2}workflow_dispatch:\s*$/m.test(storeWorkflow)) {
    errors.push("store bundle workflow must be manual-only");
  }
  if (/^\s{2}(?:push|pull_request):/m.test(storeWorkflow)) {
    errors.push("store bundle workflow must not run on push or pull_request");
  }
  for (const name of SIGNING_SECRETS) {
    if (!storeWorkflow.includes(`secrets.${name}`)) {
      errors.push(`store bundle workflow is missing ${name}`);
    }
  }
  if (
    !storeWorkflow.includes(
      "for secret_name in KEYSTORE_BASE64 KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD",
    ) || !storeWorkflow.includes('if [ "$missing" -ne 0 ]')
  ) {
    errors.push("store bundle workflow must fail early when any signing secret is empty");
  }
  if (!storeWorkflow.includes("ORG_GRADLE_PROJECT_requireReleaseSigning: 'true'")) {
    errors.push("store bundle workflow must require real release signing in Gradle");
  }
  if (!/flutter build\s+appbundle\s+--release/.test(storeWorkflow)) {
    errors.push("store bundle workflow must build a release AAB");
  }
  if (storeWorkflow.includes("test-signing.jks")) {
    errors.push("store bundle workflow must never reference the public test key");
  }
  if (/softprops\/action-gh-release|upload-google-play|r0adkll\/upload-google-play/.test(storeWorkflow)) {
    errors.push("store bundle workflow must not publish without owner review");
  }

  if (errors.length) throw new Error(errors.join("\n"));
  return { signingSecrets: SIGNING_SECRETS.length };
}

export function checkRepository(root) {
  return validateAndroidSigningSeparation({
    gradle: readFileSync(resolve(root, "flutter_client/android/app/build.gradle.kts"), "utf8"),
    testWorkflow: readFileSync(resolve(root, ".github/workflows/android.yml"), "utf8"),
    storeWorkflow: readFileSync(resolve(root, ".github/workflows/android-store.yml"), "utf8"),
  });
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === currentFile) {
  const root = resolve(dirname(currentFile), "../..");
  const result = checkRepository(root);
  console.log(
    `Android signing separation valid: test APK isolated, ${result.signingSecrets} store secrets required`,
  );
}
