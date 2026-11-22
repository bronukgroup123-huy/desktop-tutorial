import assert from "node:assert/strict";
import test from "node:test";
import {
  extractDartClassKeys,
  parseOpenApiSchemas,
  validateModelBindings,
} from "./check-flutter-openapi-models.mjs";

const openapi = `
components:
  schemas:
    Base:
      type: object
      required: [id, label]
      properties:
        id: { type: string }
        label: { type: string }
        optional: { type: string }
    Child:
      allOf:
        - $ref: '#/components/schemas/Base'
        - type: object
          required: [state]
          properties:
            state: { type: string }
`;

const baseDart = `
class BaseModel {
  BaseModel.fromJson(Map<String, dynamic> json) {
    req<String>(json, 'id');
    opt<String>(json, 'label');
  }
}
`;

const childDart = `
class ChildModel {
  ChildModel.fromJson(Map<String, dynamic> json) {
    req<String>(json, 'state');
  }
}
`;

test("OpenAPI parser reads root properties, required fields and allOf refs", () => {
  const schemas = parseOpenApiSchemas(openapi);
  assert.deepEqual([...schemas.get("Base").properties], ["id", "label", "optional"]);
  assert.deepEqual([...schemas.get("Base").required], ["id", "label"]);
  assert.deepEqual([...schemas.get("Child").refs], ["Base"]);
  assert.deepEqual([...schemas.get("Child").required], ["state"]);
});

test("Dart parser finds helper and indexed JSON reads only inside the selected class", () => {
  const source = `${baseDart}\nclass Other { Other(Map<String, dynamic> json) { json['ignored']; } }`;
  assert.deepEqual([...extractDartClassKeys(source, "BaseModel")], ["id", "label"]);
});

test("valid delegated model covers inherited required fields", () => {
  const result = validateModelBindings({
    schemas: parseOpenApiSchemas(openapi),
    bindings: [
      { schema: "Base", file: "base.dart", className: "BaseModel" },
      { schema: "Child", file: "child.dart", className: "ChildModel", delegates: ["Base"] },
    ],
    dartSources: new Map([["base.dart", baseDart], ["child.dart", childDart]]),
  });
  assert.deepEqual(result, { models: 2 });
});

test("missing required OpenAPI field fails", () => {
  const missing = baseDart.replace("opt<String>(json, 'label');", "");
  assert.throws(
    () => validateModelBindings({
      schemas: parseOpenApiSchemas(openapi),
      bindings: [{ schema: "Base", file: "base.dart", className: "BaseModel" }],
      dartSources: new Map([["base.dart", missing]]),
    }),
    /does not parse required fields: label/,
  );
});

test("Dart field absent from OpenAPI fails", () => {
  const drifted = baseDart.replace("req<String>(json, 'id');", "req<String>(json, 'id'); json['secret'];");
  assert.throws(
    () => validateModelBindings({
      schemas: parseOpenApiSchemas(openapi),
      bindings: [{ schema: "Base", file: "base.dart", className: "BaseModel" }],
      dartSources: new Map([["base.dart", drifted]]),
    }),
    /parses fields absent from OpenAPI: secret/,
  );
});
