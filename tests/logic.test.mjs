import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import vm from "node:vm";
import { Blob } from "node:buffer";
const require = createRequire(import.meta.url);
const ts = require("typescript");
const root = fileURLToPath(new URL("../", import.meta.url));
function fixture(seed = {}) {
  const storage = new Map(Object.entries(seed));
  const state = { failWrite: false, blob: null, clicked: false };
  const listeners = {};
  const context = vm.createContext({ console, Date, Intl, Blob, setTimeout: () => 0,
    crypto: { randomUUID },
    localStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => { if (state.failWrite) throw new Error("Quota exceeded"); storage.set(key, value); } },
    window: { addEventListener: (name, handler) => { listeners[name] = handler; } },
    URL: { createObjectURL: blob => { state.blob = blob; return "blob:test"; }, revokeObjectURL() {} },
    document: { createElement: () => ({ click: () => { state.clicked = true; } }) },
  });
  const cache = new Map();
  function load(name) {
    if (cache.has(name)) return cache.get(name);
    const source = readFileSync(root + "src/lib/" + name + ".ts", "utf8");
    const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
    const module = { exports: {} }; cache.set(name, module.exports);
    const compiled = vm.runInContext("(function(require,module,exports){" + code + "\n})", context);
    compiled(path => path === "react" ? { useSyncExternalStore() {} } : load(path.replace("./", "")), module, module.exports);
    return module.exports;
  }
  return { demo: load("demo"), settings: load("settings"), records: load("records"), state, storage, listeners };
}
export async function runTests() {
  const results = [];
  const test = (name, fn) => { fn(); results.push(name); };
  test("Cálculo de jornada, fines de semana y horarios inválidos", () => {
    const { demo } = fixture();
    assert.equal(demo.calculateOvertime("06:15", "17:00").minutes, 105);
    assert.equal(demo.calculateOvertime("08:00", "19:30").minutes, 150);
    assert.equal(demo.calculateOvertime("18:00", "21:00").minutes, 180);
    assert.equal(demo.calculateOvertime("09:00", "13:00", false).minutes, 240);
    assert.equal(demo.calculateOvertime("08:00", "17:00").minutes, 0);
    assert.equal(demo.calculateOvertime("invalid", "19:00").review, true);
    assert.equal(demo.calculateOvertime("24:00", "25:00").review, true);
    assert.equal(demo.calculateOvertime("22:00", "02:00").review, true);
    assert.equal(demo.calculateOvertime("19:00", undefined).review, true);
    assert.equal(demo.calculateOvertime(undefined, "19:00").inferred, true);
    assert.equal(demo.calculateOvertime(undefined, "13:00", false).review, true);
    assert.equal(demo.calculateOvertime("07:00", "19:00", true, { startsAt: "09:00", endsAt: "18:00" }).minutes, 180);
    assert.equal(demo.formatMinutes(1590), "26:30");
  });
  test("Entrada y salida se asocian y persisten sin perder detalles", () => {
    const { records, storage } = fixture();
    const first = records.registerPunch({ kind: "Entrada", institution: "Lugar propio", reason: "Inicio", notes: "Nota entrada", capturedAt: new Date("2026-10-08T21:00:00Z") });
    assert.equal(first.status, "Pendiente"); assert.equal(first.minutes, 0);
    const second = records.registerPunch({ kind: "Salida", institution: "Lugar propio", reason: "Fin", notes: "Nota salida", capturedAt: new Date("2026-10-09T00:00:00Z") });
    assert.equal(second.id, first.id); assert.equal(second.minutes, 180); assert.equal(second.entry, "18:00"); assert.equal(second.exit, "21:00");
    assert.equal(second.notes, "Nota entrada / Nota salida");
    assert.equal(records.getRecords().filter(r => r.id === first.id).length, 1);
    const reloaded = fixture({ "horaclara-records-v1": storage.get("horaclara-records-v1") });
    assert.equal(reloaded.records.getRecords()[0].id, first.id);
  });
  test("No se emparejan movimientos de distinto lugar ni de otro día", () => {
    const { records } = fixture();
    records.registerPunch({ kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2026-10-08T21:00:00Z") });
    const otherPlace = records.registerPunch({ kind: "Salida", institution: "B", reason: "Fin", notes: "", capturedAt: new Date("2026-10-08T22:00:00Z") });
    assert.equal(otherPlace.inferredEntry, true);
    const nextDay = records.registerPunch({ kind: "Salida", institution: "A", reason: "Fin", notes: "", capturedAt: new Date("2026-10-09T05:00:00Z") });
    assert.equal(nextDay.status, "Pendiente"); assert.equal(nextDay.minutes, 0);
  });
  test("Duplicados recientes y errores de almacenamiento no anuncian éxito", () => {
    const { records, state } = fixture();
    const punch = { kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2026-10-08T21:00:00Z") };
    records.registerPunch(punch);
    assert.throws(() => records.registerPunch(punch), /menos de un minuto/);
    const count = records.getRecords().length; state.failWrite = true;
    assert.throws(() => records.registerPunch({ ...punch, capturedAt: new Date("2026-10-08T22:00:00Z") }), /No se pudo guardar/);
    assert.equal(records.getRecords().length, count);
    const broken = fixture({ "horaclara-records-v1": "invalid json" });
    assert.throws(() => broken.records.registerPunch(punch), /No se pudieron leer/);
    assert.equal(broken.storage.get("horaclara-records-v1"), "invalid json");
  });
  test("La capa de guardado rechaza campos vacíos y fechas inválidas", () => {
    const { records } = fixture();
    const input = { kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2026-10-08T21:00:00Z") };
    assert.throws(() => records.registerPunch({ ...input, reason: "   " }), /Revisá/);
    assert.throws(() => records.registerPunch({ ...input, institution: "   " }), /Revisá/);
    assert.throws(() => records.registerPunch({ ...input, notes: "a".repeat(2001) }), /Revisá/);
    assert.throws(() => records.registerPunch({ ...input, capturedAt: new Date("invalid") }), /inválidos/);
  });
  test("Cierre bloquea cambios y reapertura los permite", () => {
    const { records } = fixture();
    assert.throws(() => records.closeMonth("2025-06"), /pendientes/);
    records.updateRecord("r4", { status: "Rechazado" });
    records.closeMonth("2025-06");
    assert.equal(records.getClosures()["2025-06"].records.length, 6);
    assert.throws(() => records.updateRecord("r1", { status: "Rechazado" }), /cerrado/);
    assert.throws(() => records.registerPunch({ kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2025-06-20T21:00:00Z") }), /cerrado/);
    records.reopenMonth("2025-06"); records.updateRecord("r1", { status: "Rechazado" });
    assert.equal(records.getRecords().find(r => r.id === "r1").status, "Rechazado");
  });
  test("Feriados y jornada configurable se aplican a registros nuevos", () => {
    const { records, settings } = fixture();
    settings.saveSettings({ ...settings.defaultSettings, holidays: ["2026-10-08"] });
    records.registerPunch({ kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2026-10-08T12:00:00Z") });
    const result = records.registerPunch({ kind: "Salida", institution: "A", reason: "Fin", notes: "", capturedAt: new Date("2026-10-08T16:00:00Z") });
    assert.equal(result.minutes, 240);
    assert.throws(() => settings.saveSettings({ ...settings.defaultSettings, startsAt: "18:00", endsAt: "08:00" }));
    assert.throws(() => settings.saveSettings({ ...settings.defaultSettings, holidays: ["2026-02-30"] }));
  });
  const fixtureCsv = fixture();
  fixtureCsv.records.exportRecords([{ ...fixtureCsv.records.getRecords()[0], reason: '=HYPERLINK("bad")', notes: "Línea 1\nLínea 2" }]);
  const csv = await fixtureCsv.state.blob.text();
  assert.equal(fixtureCsv.state.clicked, true); assert.ok(csv.includes("'=HYPERLINK")); assert.ok(csv.includes('""bad""')); assert.ok(csv.includes("Línea 1\nLínea 2")); results.push("CSV escapa comillas y neutraliza fórmulas");
  return results;
}
export const results = await runTests();
console.log(results.length + " pruebas aprobadas");
