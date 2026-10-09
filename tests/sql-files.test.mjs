import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../supabase/", import.meta.url));
const files = ["setup.sql", "promote_admin.sql", ...["migrations", "tests"].flatMap(dir => readdirSync(root + dir).filter(name => name.endsWith(".sql")).map(name => dir + "/" + name))];
for (const file of files) {
  const sql = readFileSync(root + file, "utf8");
  // Las funciones usan bloques $$ o $nombre$; un $ aislado rompe PostgreSQL.
  const withoutTags = sql.replace(/\$(?:[A-Za-z_]\w*)?\$/g, "");
  assert.ok(!withoutTags.includes("$"), file + ": delimitador SQL incompleto");
  const tags = sql.match(/\$(?:[A-Za-z_]\w*)?\$/g) || [];
  const counts = new Map();
  for (const tag of tags) counts.set(tag, (counts.get(tag) || 0) + 1);
  for (const [tag, count] of counts) assert.equal(count % 2, 0, file + ": bloque " + tag + " sin cierre");
}
console.log(files.length + " archivos SQL con delimitadores válidos");
