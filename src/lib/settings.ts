export type SettingsData = { startsAt: string; endsAt: string; weekdays: number[]; institutions: string[]; holidays: string[] };
export const defaultSettings: SettingsData = { startsAt: "08:00", endsAt: "17:00", weekdays: [1, 2, 3, 4, 5], institutions: ["Institución A", "Institución B", "Institución C"], holidays: [] };
export function validateSettings(value: unknown): asserts value is SettingsData {
  const s = value as SettingsData;
  const validTime = (v: string) => typeof v === "string" && /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(v);
  if (!s || !validTime(s.startsAt) || !validTime(s.endsAt) || s.endsAt <= s.startsAt || !Array.isArray(s.weekdays) || !s.weekdays.every(d => Number.isInteger(d) && d >= 0 && d <= 6) || !Array.isArray(s.institutions) || !s.institutions.length || !s.institutions.every(i => typeof i === "string" && i.trim().length > 0 && i.length <= 150) || !Array.isArray(s.holidays) || !s.holidays.every(d => typeof d === "string" && /^\d{4}-\d{2}-\d{2}$/.test(d) && new Date(d + "T12:00:00Z").toISOString().slice(0,10) === d)) throw new Error("Revisá horarios, días, instituciones y fechas de feriados.");
}
export function getSettings(): SettingsData {
  const raw = localStorage.getItem("horaclara-settings-v1");
  if (!raw) return { ...defaultSettings };
  const value: unknown = JSON.parse(raw); validateSettings(value); return value;
}
export function saveSettings(value: SettingsData) {
  validateSettings(value);
  localStorage.setItem("horaclara-settings-v1", JSON.stringify(value));
}
