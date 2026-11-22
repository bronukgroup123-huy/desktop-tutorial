import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const MODEL_BINDINGS = [
  { schema: "FriendCard", file: "friends.dart", className: "FriendCard" },
  { schema: "HomeRegion", file: "me.dart", className: "HomeRegion" },
  { schema: "Me", file: "me.dart", className: "Me" },
  { schema: "PickCreated", file: "pick.dart", className: "CreatedPick" },
  { schema: "MapPick", file: "pick.dart", className: "MapPick" },
  { schema: "PickCard", file: "pick.dart", className: "PickCard", delegates: ["MapPick"] },
  { schema: "AnalysisUsage", file: "analysis.dart", className: "AnalysisUsage" },
  { schema: "AnalysisArea", file: "analysis.dart", className: "AnalysisArea" },
  { schema: "AnalysisOverview", file: "analysis.dart", className: "AnalysisOverview" },
  {
    schema: "AnalysisSpecies",
    file: "analysis.dart",
    className: "AnalysisSpecies",
    delegates: ["ForecastSpecies"],
  },
  {
    schema: "AnalysisResult",
    file: "analysis.dart",
    className: "AnalysisResult",
    additionalKeys: ["basket", "others"],
  },
  {
    schema: "AnalysisBasketSpecies",
    file: "analysis.dart",
    className: "AnalysisBasketSpecies",
  },
  {
    schema: "AnalysisDayWeather",
    file: "analysis.dart",
    className: "AnalysisWeather",
  },
  {
    schema: "AnalysisDay",
    file: "analysis.dart",
    className: "AnalysisDay",
    additionalKeys: ["basket", "others"],
  },
  { schema: "RegionGeometry", file: "region.dart", className: "RegionGeometry" },
  { schema: "ForecastSpecies", file: "forecast.dart", className: "ForecastSpecies" },
  { schema: "ForecastWeather", file: "forecast.dart", className: "ForecastWeather" },
  { schema: "Forecast", file: "forecast.dart", className: "Forecast" },
];

function indentation(line) {
  return line.length - line.trimStart().length;
}

export function parseOpenApiSchemas(yaml) {
  const lines = yaml.split(/\r?\n/);
  const schemasLine = lines.findIndex((line) => line === "  schemas:");
  if (schemasLine < 0) throw new Error("OpenAPI components.schemas section is missing");

  const starts = [];
  for (let index = schemasLine + 1; index < lines.length; index += 1) {
    const match = /^ {4}([A-Za-z0-9_]+):\s*$/.exec(lines[index]);
    if (match) starts.push({ name: match[1], index });
  }

  const schemas = new Map();
  for (let position = 0; position < starts.length; position += 1) {
    const { name, index } = starts[position];
    const end = starts[position + 1]?.index ?? lines.length;
    const block = lines.slice(index + 1, end);
    const propertyMarkers = block
      .map((line, blockIndex) => ({ line, blockIndex, indent: indentation(line) }))
      .filter(({ line }) => /^\s+properties:\s*$/.test(line));
    const propertyIndent = propertyMarkers.length
      ? Math.min(...propertyMarkers.map(({ indent }) => indent))
      : null;
    const propertyMarker = propertyMarkers.find(({ indent }) => indent === propertyIndent);
    const properties = new Set();
    if (propertyMarker) {
      for (let offset = propertyMarker.blockIndex + 1; offset < block.length; offset += 1) {
        const line = block[offset];
        const indent = indentation(line);
        if (line.trim() && indent <= propertyIndent) break;
        if (indent === propertyIndent + 2) {
          const field = /^\s*([A-Za-z0-9_]+):/.exec(line);
          if (field) properties.add(field[1]);
        }
      }
    }

    const requiredCandidates = block
      .map((line) => ({ line, indent: indentation(line) }))
      .filter(({ line }) => /^\s+required:\s*\[/.test(line));
    const requiredIndent = requiredCandidates.length
      ? Math.min(...requiredCandidates.map(({ indent }) => indent))
      : null;
    const required = new Set();
    for (const { line, indent } of requiredCandidates) {
      if (indent !== requiredIndent || (propertyIndent != null && indent > propertyIndent)) continue;
      const values = /required:\s*\[([^\]]*)\]/.exec(line)?.[1] ?? "";
      for (const value of values.split(",").map((part) => part.trim()).filter(Boolean)) {
        required.add(value.replace(/^['"]|['"]$/g, ""));
      }
    }

    const refs = new Set();
    for (const line of block) {
      if (propertyIndent != null && indentation(line) >= propertyIndent) continue;
      const ref = /\$ref:\s*['"]?#\/components\/schemas\/([A-Za-z0-9_]+)/.exec(line);
      if (ref) refs.add(ref[1]);
    }
    schemas.set(name, { properties, required, refs });
  }
  return schemas;
}

export function extractDartClassKeys(source, className) {
  const classStart = source.search(new RegExp(`\\bclass\\s+${className}\\b`));
  if (classStart < 0) throw new Error(`Dart class ${className} is missing`);
  const braceStart = source.indexOf("{", classStart);
  if (braceStart < 0) throw new Error(`Dart class ${className} has no body`);

  let depth = 0;
  let end = -1;
  for (let index = braceStart; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") depth -= 1;
    if (depth === 0) {
      end = index + 1;
      break;
    }
  }
  if (end < 0) throw new Error(`Dart class ${className} body is not balanced`);
  const block = source.slice(braceStart, end);
  const keys = new Set();
  const helperPattern = /(?:req|opt|stringList)(?:<[^\n()]+>)?\(\s*(?:json|j)\s*,\s*['"]([^'"]+)['"]/g;
  const indexPattern = /(?:json|j)\s*\[\s*['"]([^'"]+)['"]\s*\]/g;
  for (const pattern of [helperPattern, indexPattern]) {
    for (const match of block.matchAll(pattern)) keys.add(match[1]);
  }
  return keys;
}

function union(target, values) {
  for (const value of values) target.add(value);
  return target;
}

export function validateModelBindings({ schemas, bindings, dartSources }) {
  const errors = [];
  const bindingBySchema = new Map(bindings.map((binding) => [binding.schema, binding]));
  const resolvedSchemas = new Map();
  const modelKeys = new Map();

  function resolveSchema(name, stack = []) {
    if (resolvedSchemas.has(name)) return resolvedSchemas.get(name);
    const schema = schemas.get(name);
    if (!schema) throw new Error(`OpenAPI schema ${name} is missing`);
    if (stack.includes(name)) throw new Error(`OpenAPI schema reference cycle: ${[...stack, name].join(" -> ")}`);
    const resolved = {
      properties: new Set(schema.properties),
      required: new Set(schema.required),
    };
    for (const ref of schema.refs) {
      const parent = resolveSchema(ref, [...stack, name]);
      union(resolved.properties, parent.properties);
      union(resolved.required, parent.required);
    }
    resolvedSchemas.set(name, resolved);
    return resolved;
  }

  function resolveModelKeys(name, stack = []) {
    if (modelKeys.has(name)) return modelKeys.get(name);
    const binding = bindingBySchema.get(name);
    if (!binding) throw new Error(`Model binding for delegated schema ${name} is missing`);
    if (stack.includes(name)) throw new Error(`Model binding cycle: ${[...stack, name].join(" -> ")}`);
    const source = dartSources.get(binding.file);
    if (source == null) throw new Error(`Dart source ${binding.file} is missing`);
    const keys = extractDartClassKeys(source, binding.className);
    union(keys, binding.additionalKeys ?? []);
    for (const delegate of binding.delegates ?? []) {
      union(keys, resolveModelKeys(delegate, [...stack, name]));
    }
    modelKeys.set(name, keys);
    return keys;
  }

  for (const binding of bindings) {
    let schema;
    let keys;
    try {
      schema = resolveSchema(binding.schema);
      keys = resolveModelKeys(binding.schema);
    } catch (error) {
      errors.push(error.message);
      continue;
    }
    const missing = [...schema.required].filter((key) => !keys.has(key)).sort();
    const undocumented = [...keys].filter((key) => !schema.properties.has(key)).sort();
    if (missing.length) {
      errors.push(`${binding.schema}/${binding.className} does not parse required fields: ${missing.join(", ")}`);
    }
    if (undocumented.length) {
      errors.push(`${binding.schema}/${binding.className} parses fields absent from OpenAPI: ${undocumented.join(", ")}`);
    }
  }

  if (errors.length) throw new Error(errors.join("\n"));
  return { models: bindings.length };
}

export function checkRepository(root) {
  const modelsRoot = resolve(root, "flutter_client/lib/data/models");
  const dartSources = new Map(
    [...new Set(MODEL_BINDINGS.map(({ file }) => file))]
      .map((file) => [file, readFileSync(resolve(modelsRoot, file), "utf8")]),
  );
  return validateModelBindings({
    schemas: parseOpenApiSchemas(readFileSync(resolve(root, "openapi/v1.yaml"), "utf8")),
    bindings: MODEL_BINDINGS,
    dartSources,
  });
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === currentFile) {
  const root = resolve(dirname(currentFile), "../..");
  const result = checkRepository(root);
  console.log(`Flutter/OpenAPI model contract valid: ${result.models} models checked`);
}
