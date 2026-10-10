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
    const second = records.registerPunch({ kind: "Salida", institution: "Lugar propio", targetId: first.id, reason: "Fin", notes: "Nota salida", capturedAt: new Date("2026-10-09T00:00:00Z") });
    assert.equal(second.id, first.id); assert.equal(second.minutes, 180); assert.equal(second.entry, "18:00"); assert.equal(second.exit, "21:00");
    assert.equal(second.notes, "Nota entrada / Nota salida");
    assert.equal(records.getRecords().filter(r => r.id === first.id).length, 1);
    const reloaded = fixture({ "horaclara-records-v1": storage.get("horaclara-records-v1") });
    assert.equal(reloaded.records.getRecords()[0].id, first.id);
  });
  test("No se puede eludir una entrada abierta eligiendo otra institución", () => {
    const { records } = fixture();
    const first = records.registerPunch({ kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2026-10-08T21:00:00Z") });
    const count = records.getRecords().length;
    assert.throws(() => records.registerPunch({ kind: "Salida", institution: "B", targetId: first.id, reason: "Fin", notes: "", capturedAt: new Date("2026-10-08T22:00:00Z") }), /institución/);
    assert.throws(() => records.registerPunch({ kind: "Salida", institution: "B", confirmWithoutEntry: true, reason: "Urgencia", notes: "", capturedAt: new Date("2026-10-08T22:00:00Z") }), /Elegí la entrada/);
    assert.equal(records.getRecords().length, count);
    assert.throws(() => records.registerPunch({ kind: "Salida", institution: "A", targetId: first.id, reason: "Fin", notes: "", capturedAt: new Date("2026-10-09T05:00:00Z") }), /ya no está abierta/);
    const nextDay = records.registerPunch({ kind: "Salida", institution: "A", confirmWithoutEntry: true, reason: "Fin", notes: "", capturedAt: new Date("2026-10-09T05:00:00Z") });
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
    const entry = records.registerPunch({ kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2026-10-08T12:00:00Z") });
    const result = records.registerPunch({ kind: "Salida", institution: "A", targetId: entry.id, reason: "Fin", notes: "", capturedAt: new Date("2026-10-08T16:00:00Z") });
    assert.equal(result.minutes, 240);
    assert.throws(() => settings.saveSettings({ ...settings.defaultSettings, startsAt: "18:00", endsAt: "08:00" }));
    assert.throws(() => settings.saveSettings({ ...settings.defaultSettings, holidays: ["2026-02-30"] }));
  });
  const fixtureCsv = fixture();
  fixtureCsv.records.exportRecords([{ ...fixtureCsv.records.getRecords()[0], reason: '=HYPERLINK("bad")', notes: "Línea 1\nLínea 2" }]);
  const csv = await fixtureCsv.state.blob.text();
  assert.equal(fixtureCsv.state.clicked, true); assert.ok(csv.includes("'=HYPERLINK")); assert.ok(csv.includes('""bad""')); assert.ok(csv.includes("Línea 1\nLínea 2")); results.push("CSV escapa comillas y neutraliza fórmulas");
  test("Cierre a medianoche argentina, cálculo y persistencia idempotente", () => {
    const { records, storage } = fixture();
    const r = records.registerPunch({ kind: "Entrada", institution: "A", reason: "Inicio", notes: "",
      capturedAt: new Date("2026-10-08T09:00:00Z") });
    assert.equal(records.finalizeOpenRecords(new Date("2026-10-09T02:59:59Z")), 0);
    assert.equal(records.finalizeOpenRecords(new Date("2026-10-09T03:00:00Z")), 1);
    const closed = records.getRecords().find(x => x.id === r.id);
    assert.equal(closed.exit, "17:00"); assert.equal(closed.inferredExit, true);
    assert.equal(closed.status, "Automático"); assert.equal(closed.minutes, 120);
    assert.equal(closed.lastEventAt, r.lastEventAt);
    assert.equal(records.finalizeOpenRecords(new Date("2026-10-10T03:00:00Z")), 0);
    assert.equal(fixture({ "horaclara-records-v1": storage.get("horaclara-records-v1") })
      .records.getRecords().find(x => x.id === r.id).exit, "17:00");
  });
  test("El cierre conserva la jornada original y evita inferencias inseguras", () => {
    const punch = (records, date, time) => records.registerPunch({ kind: "Entrada", institution: "A",
      reason: "Inicio", notes: "", capturedAt: new Date(date + "T" + time + ":00-03:00") });
    const { records, settings } = fixture();
    const first = punch(records, "2026-10-08", "06:00");
    settings.saveSettings({ ...settings.getSettings(), endsAt: "18:00" });
    records.finalizeOpenRecords(new Date("2026-10-09T03:00:00Z"));
    assert.equal(records.getRecords().find(x => x.id === first.id).exit, "17:00");
    const late = fixture().records; punch(late, "2026-10-08", "18:00");
    assert.equal(late.finalizeOpenRecords(new Date("2026-10-09T03:00:00Z")), 0);
    const weekend = fixture().records; punch(weekend, "2026-10-10", "06:00");
    assert.equal(weekend.finalizeOpenRecords(new Date("2026-10-11T03:00:00Z")), 0);
    const ambiguous = fixture().records;
    punch(ambiguous, "2026-10-08", "06:00"); punch(ambiguous, "2026-10-08", "07:00");
    assert.equal(ambiguous.finalizeOpenRecords(new Date("2026-10-09T03:00:00Z")), 0);
  });
  test("Salida por urgencia sin entrada usa el inicio habitual inferido", () => {
    const { records } = fixture();
    const input = { kind: "Salida", institution: "A", reason: "Urgencia", notes: "", capturedAt: new Date("2026-10-08T23:45:00Z") };
    assert.throws(() => records.registerPunch(input), /Confirmá/);
    const r = records.registerPunch({ ...input, confirmWithoutEntry: true });
    assert.equal(r.entry,"08:00"); assert.equal(r.exit,"20:45"); assert.equal(r.inferredEntry,true); assert.equal(r.minutes,225); assert.equal(r.status,"Automático");
  });
  test("Varias entradas requieren elegir una y respetan la jornada original", () => {
    const { records, settings } = fixture();
    const first = records.registerPunch({ kind: "Entrada", institution: "A", reason: "Inicio", notes: "", capturedAt: new Date("2026-10-08T09:00:00Z") });
    const second = records.registerPunch({ kind: "Entrada", institution: "A", reason: "Otro inicio", notes: "", capturedAt: new Date("2026-10-08T10:00:00Z") });
    settings.saveSettings({ ...settings.getSettings(), startsAt: "09:00", endsAt: "18:00" });
    const input = { kind: "Salida", institution: "A", reason: "Fin", notes: "", capturedAt: new Date("2026-10-08T23:00:00Z") };
    assert.throws(() => records.registerPunch(input), /Elegí/);
    const closed = records.registerPunch({ ...input, targetId: second.id });
    assert.equal(closed.id,second.id); assert.equal(closed.minutes,240); assert.equal(closed.scheduleEnd,"17:00");
    assert.equal(records.getRecords().find(r => r.id === first.id).exit,undefined);
  });
  return results;
}
export const results = await runTests();
console.log(results.length + " pruebas aprobadas");
