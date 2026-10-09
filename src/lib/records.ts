import { useSyncExternalStore } from "react";
import { getSettings } from "./settings";
import { calculateOvertime, initialRecords, type WorkRecord } from "./demo";

export const TIME_ZONE = "America/Argentina/Buenos_Aires";
const KEY = "horaclara-records-v1";
let cache: WorkRecord[] | undefined;
let storageError = "";
const listeners = new Set<() => void>();
export function getRecords(): WorkRecord[] {
  if (cache) return cache;
  try {
    const raw = localStorage.getItem(KEY);
    if (raw === null) return cache = [...initialRecords];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed) || !parsed.every(isRecord)) throw new Error("Formato inválido");
    return cache = parsed;
  } catch {
    storageError = "No se pudieron leer los fichajes guardados. No se sobrescribirán los datos. Revisá el almacenamiento del navegador.";
    return cache = [...initialRecords];
  }
}
function isRecord(value: unknown): value is WorkRecord {
  if (!value || typeof value !== "object") return false;
  const r = value as WorkRecord;
  const validTime = (v: unknown) => v === undefined || (typeof v === "string" && /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(v));
  return [r.id, r.date, r.employee, r.initials, r.institution, r.reason].every(v => typeof v === "string") && validTime(r.entry) && validTime(r.exit) && (r.notes === undefined || typeof r.notes === "string") && (r.isoDate === undefined || (typeof r.isoDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(r.isoDate))) && Number.isFinite(r.minutes) && r.minutes >= 0 && ["Aprobado", "Automático", "Pendiente", "Corregido", "Rechazado"].includes(r.status);
}
function notify() { listeners.forEach(fn => fn()); }
function save(records: WorkRecord[]) {
  if (storageError) throw new Error(storageError);
  try { localStorage.setItem(KEY, JSON.stringify(records)); }
  catch { throw new Error("No se pudo guardar. El navegador puede tener el almacenamiento bloqueado o lleno."); }
  cache = records; notify();
}
window.addEventListener("storage", event => {
  if (event.key === KEY || event.key === null) { cache = undefined; storageError = ""; getRecords(); notify(); }
});
export function subscribeRecords(fn: () => void) { listeners.add(fn); return () => { listeners.delete(fn); }; }
export function useRecords() { return useSyncExternalStore(subscribeRecords, getRecords); }
export function getStorageError() { getRecords(); return storageError; }
export function updateRecord(id: string, changes: Partial<Pick<WorkRecord, "status" | "reason">>) {
  const current = getRecords().find(r => r.id === id);
  if (current && getClosures()[recordMonth(current)]) throw new Error("El período está cerrado. Reabrilo antes de cambiar registros.");
  save(getRecords().map(r => r.id === id ? { ...r, ...changes } : r));
}
export function localDate(date = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}
export function recordMonth(record: WorkRecord) {
  if (record.isoDate) return record.isoDate.slice(0, 7);
  const parts = record.date.split(" ");
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const month = months.indexOf(parts[1]);
  return month >= 0 ? parts[2] + "-" + String(month + 1).padStart(2, "0") : "";
}
export function registerPunch(input: { kind: "Entrada" | "Salida"; institution: string; reason: string; notes: string; capturedAt: Date }) {
  if (!["Entrada", "Salida"].includes(input.kind) || !Number.isFinite(input.capturedAt.getTime())) throw new Error("Movimiento o fecha inválidos.");
  input = { ...input, institution: input.institution.trim(), reason: input.reason.trim(), notes: input.notes.trim() };
  if (!input.institution || input.institution.length > 150 || !input.reason || input.reason.length > 1000 || input.notes.length > 2000) throw new Error("Revisá el lugar, motivo y observaciones.");
  const records = getRecords();
  const isoDate = localDate(input.capturedAt);
  if (getClosures()[isoDate.slice(0, 7)]) throw new Error("Este período está cerrado. Reabrilo antes de registrar movimientos.");
  const time = new Intl.DateTimeFormat("es-AR", { timeZone: TIME_ZONE, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(input.capturedAt);
  const employee = "María González";
  const recent = records.find(r => r.employee === employee && r.lastEventAt);
  if (recent?.lastEventAt && Math.abs(input.capturedAt.getTime() - Date.parse(recent.lastEventAt)) < 60000 && ((input.kind === "Entrada" && !recent.exit) || (input.kind === "Salida" && !!recent.exit))) throw new Error("Ya registraste ese movimiento hace menos de un minuto.");
  const candidate = input.kind === "Salida" ? records.find(r => r.employee === employee && r.isoDate === isoDate && r.entry && !r.exit && r.status === "Pendiente" && r.institution === input.institution) : undefined;
  const entry = input.kind === "Entrada" ? time : candidate?.entry;
  const exit = input.kind === "Salida" ? time : undefined;
  const day = new Date(isoDate + "T12:00:00Z").getUTCDay();
  const settings = getSettings();
  const calculation = calculateOvertime(entry, exit, settings.weekdays.includes(day) && !settings.holidays.includes(isoDate), settings);
  const record: WorkRecord = {
    id: candidate?.id ?? crypto.randomUUID(), date: new Intl.DateTimeFormat("es-AR", { timeZone: TIME_ZONE }).format(input.capturedAt), isoDate,
    scheduleStart: candidate?.scheduleStart ?? settings.startsAt,
    scheduleEnd: candidate?.scheduleEnd ?? settings.endsAt,
    workingDay: candidate?.workingDay ?? (settings.weekdays.includes(day) && !settings.holidays.includes(isoDate)),
    employee, initials: "MG", entry: entry ?? (calculation.inferred ? settings.startsAt : undefined), exit, institution: input.institution,
    reason: candidate ? candidate.reason + " / " + input.reason : input.reason,
    notes: candidate ? [candidate.notes, input.notes].filter(Boolean).join(" / ") : input.notes,
    capturedAt: candidate?.capturedAt ?? input.capturedAt.toISOString(), lastEventAt: input.capturedAt.toISOString(),
    minutes: calculation.minutes, status: calculation.review ? "Pendiente" : "Automático",
    inferredEntry: !entry && calculation.inferred, inferredExit: !exit && calculation.inferred,
  };
  // Las entradas abiertas quedan pendientes para permitir asociar su salida real.
  if (input.kind === "Entrada") { record.status = "Pendiente"; record.minutes = 0; record.inferredExit = false; }
  save([record, ...records.filter(r => r.id !== record.id)]);
  return record;
}
// En la demo se recuperan los cierres al abrirla; en producción corre Supabase Cron.
export function finalizeOpenRecords(now = new Date()) {
  const today = localDate(now);
  const records = getRecords();
  const closures = getClosures();
  let count = 0;
  const next = records.map(r => {
    if (!r.isoDate || r.isoDate >= today || r.status !== "Pendiente" ||
      !r.entry || r.exit || !r.workingDay || !r.scheduleStart || !r.scheduleEnd ||
      r.entry >= r.scheduleEnd || closures[recordMonth(r)]) return r;
    if (records.some(other => other.id !== r.id && other.employee === r.employee &&
      other.isoDate === r.isoDate && other.status !== "Rechazado" &&
      (other.status === "Pendiente" || (other.entry && other.exit &&
        other.entry < r.scheduleEnd! && other.exit > r.entry!)))) return r;
    const result = calculateOvertime(r.entry, r.scheduleEnd, true,
      { startsAt: r.scheduleStart, endsAt: r.scheduleEnd });
    if (result.review) return r;
    count++;
    return { ...r, exit: r.scheduleEnd, inferredExit: true,
      status: "Automático" as const, minutes: result.minutes };
  });
  if (count) save(next);
  return count;
}
export function exportRecords(records: WorkRecord[], filename = "historial.csv") {
  const cell = (value: unknown) => {
    let text = String(value ?? "");
    if (/^[\s]*[=+@-]/.test(text)) text = "'" + text;
    return '"' + text.replace(/"/g, '""') + '"';
  };
  const rows = [["Fecha", "Empleado", "Legajo", "Entrada", "Salida", "Entrada inferida", "Salida inferida", "Institución", "Motivo", "Observaciones", "Minutos extra", "Estado"], ...records.map(r => [r.date, r.employee, r.employeeNumber, r.entry, r.exit, r.inferredEntry ? "Sí" : "No", r.inferredExit ? "Sí" : "No", r.institution, r.reason, r.notes, r.minutes, r.status])];
  const url = URL.createObjectURL(new Blob(["\uFEFF" + rows.map(row => row.map(cell).join(";")).join("\r\n")], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a"); link.href = url; link.download = filename; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export type Closure = { closedAt: string; records: WorkRecord[] };
export function getClosures(): Record<string, Closure> {
  try {
    const data = JSON.parse(localStorage.getItem("horaclara-closures-v1") || "{}");
    if (!data || typeof data !== "object" || Array.isArray(data) || !Object.values(data).every(value => {
      const c = value as Closure;
      return c && typeof c.closedAt === "string" && Array.isArray(c.records) && c.records.every(isRecord);
    })) throw new Error();
    return data;
  } catch { throw new Error("No se pudieron leer los cierres. No se modificarán los datos guardados."); }
}
export function closeMonth(month: string) {
  const records = getRecords().filter(r => recordMonth(r) === month);
  if (storageError) throw new Error(storageError);
  if (!records.length) throw new Error("El período no tiene registros.");
  if (records.some(r => r.status === "Pendiente")) throw new Error("Resolvé las revisiones pendientes antes de cerrar el período.");
  const closures = getClosures();
  if (closures[month]) throw new Error("El período ya está cerrado.");
  localStorage.setItem("horaclara-closures-v1", JSON.stringify({ ...closures, [month]: { closedAt: new Date().toISOString(), records } }));
}
export function reopenMonth(month: string) {
  const closures = getClosures(); delete closures[month];
  localStorage.setItem("horaclara-closures-v1", JSON.stringify(closures));
}
