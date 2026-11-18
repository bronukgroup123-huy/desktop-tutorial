// Тестовий файл для застосунку: deno run -A scripts/trails/make_fixture.ts
import { encode, TrailBuilder } from "./lib.ts";
const b = new TrailBuilder();
for (const line of Deno.readTextFileSync(new URL("./fixture.geojsonseq", import.meta.url)).split("\n")) {
  if (line.trim()) b.add(JSON.parse(line));
}
const out = new URL("../../flutter_client/test/fixtures/trails-test.bin", import.meta.url);
await Deno.mkdir(new URL(".", out), { recursive: true });
await Deno.writeFile(out, encode(b.build()));
console.log("written", out.pathname);
