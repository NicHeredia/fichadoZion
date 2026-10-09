export type Status = "Aprobado" | "Automático" | "Pendiente" | "Corregido" | "Rechazado";

export type Employee = {
  id: string;
  name: string;
  initials: string;
  user: string;
  role: string;
  status: "Activo" | "Inactivo";
  hours: number;
  approved: number;
  pending: number;
  events: number;
  last: string;
};

export type WorkRecord = {
  employeeId?: string;
  employeeNumber?: string;
  id: string;
  date: string;
  isoDate?: string;
  notes?: string;
  capturedAt?: string;
  lastEventAt?: string;
  employee: string;
  initials: string;
  entry?: string;
  exit?: string;
  inferredEntry?: boolean;
  inferredExit?: boolean;
  institution: string;
  reason: string;
  minutes: number;
  status: Status;
};

export const employees: Employee[] = [
  { id: "1", name: "María González", initials: "MG", user: "mgonzalez", role: "Administración", status: "Activo", hours: 26.5, approved: 22, pending: 4.5, events: 18, last: "Hoy, 19:12" },
  { id: "2", name: "Lucas Rodríguez", initials: "LR", user: "lrodriguez", role: "Logística", status: "Activo", hours: 22.25, approved: 18.75, pending: 3.5, events: 15, last: "Hoy, 18:34" },
  { id: "3", name: "Sofía Martínez", initials: "SM", user: "smartinez", role: "Coordinación", status: "Activo", hours: 19.5, approved: 19.5, pending: 0, events: 12, last: "Ayer, 20:03" },
  { id: "4", name: "Diego Fernández", initials: "DF", user: "dfernandez", role: "Mantenimiento", status: "Activo", hours: 17.75, approved: 13, pending: 4.75, events: 14, last: "Ayer, 18:45" },
  { id: "5", name: "Camila López", initials: "CL", user: "clopez", role: "Administración", status: "Activo", hours: 15, approved: 12.5, pending: 2.5, events: 10, last: "12 Jun, 19:20" },
  { id: "6", name: "Martín Sánchez", initials: "MS", user: "msanchez", role: "Logística", status: "Activo", hours: 13.25, approved: 11.25, pending: 2, events: 9, last: "12 Jun, 18:10" },
  { id: "7", name: "Valentina Ruiz", initials: "VR", user: "vruiz", role: "Atención", status: "Activo", hours: 11.5, approved: 11.5, pending: 0, events: 8, last: "11 Jun, 19:05" },
  { id: "8", name: "Nicolás Pérez", initials: "NP", user: "nperez", role: "Mantenimiento", status: "Inactivo", hours: 7.25, approved: 6, pending: 1.25, events: 6, last: "30 May, 17:42" },
];

export const initialRecords: WorkRecord[] = [
  { id: "r1", date: "13 Jun 2025", employee: "María González", initials: "MG", entry: "06:15", exit: "17:00", inferredExit: true, institution: "Institución A", reason: "Entrega de materiales", minutes: 105, status: "Automático" },
  { id: "r2", date: "13 Jun 2025", employee: "Lucas Rodríguez", initials: "LR", entry: "08:00", inferredEntry: true, exit: "19:30", institution: "Institución B", reason: "Trabajo administrativo", minutes: 150, status: "Automático" },
  { id: "r3", date: "12 Jun 2025", employee: "Sofía Martínez", initials: "SM", entry: "18:00", exit: "21:00", institution: "Institución C", reason: "Atención fuera de horario", minutes: 180, status: "Aprobado" },
  { id: "r4", date: "12 Jun 2025", employee: "Diego Fernández", initials: "DF", entry: "19:00", institution: "Institución A", reason: "Traslado de equipamiento", minutes: 0, status: "Pendiente" },
  { id: "r5", date: "08 Jun 2025", employee: "Camila López", initials: "CL", entry: "09:00", exit: "13:00", institution: "Institución B", reason: "Inventario de depósito", minutes: 240, status: "Aprobado" },
  { id: "r6", date: "06 Jun 2025", employee: "Martín Sánchez", initials: "MS", entry: "06:00", exit: "19:00", institution: "Institución C", reason: "Jornada operativa especial", minutes: 240, status: "Corregido" },
];

export const chartData = [
  { day: "01", current: 4, previous: 3 }, { day: "03", current: 7, previous: 5 },
  { day: "05", current: 5, previous: 4 }, { day: "07", current: 11, previous: 7 },
  { day: "09", current: 8, previous: 8 }, { day: "11", current: 13, previous: 9 },
  { day: "13", current: 10, previous: 7 }, { day: "15", current: 15, previous: 11 },
  { day: "17", current: 12, previous: 10 }, { day: "19", current: 17, previous: 12 },
  { day: "21", current: 15, previous: 13 }, { day: "23", current: 20, previous: 15 },
  { day: "25", current: 18, previous: 14 }, { day: "27", current: 22, previous: 16 },
  { day: "29", current: 24, previous: 18 },
];

export function formatMinutes(minutes: number) {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
}

export function calculateOvertime(entry?: string, exit?: string, workingDay = true, schedule = { startsAt: "08:00", endsAt: "17:00" }) {
  const validTime = (value: string) => /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value);
  if ((entry !== undefined && !validTime(entry)) || (exit !== undefined && !validTime(exit))) return { minutes: 0, inferred: false, review: true };
  if (!validTime(schedule.startsAt) || !validTime(schedule.endsAt) || schedule.endsAt <= schedule.startsAt) return { minutes: 0, inferred: false, review: true };
  if (!entry && !exit) return { minutes: 0, inferred: false, review: true };
  if (!workingDay && (!entry || !exit)) return { minutes: 0, inferred: false, review: true };
  const toMinutes = (value: string) => {
    const [h, m] = value.split(":").map(Number);
    return h * 60 + m;
  };
  const workingStart = toMinutes(schedule.startsAt);
  const workingEnd = toMinutes(schedule.endsAt);
  const start = entry ? toMinutes(entry) : workingStart;
  const end = exit ? toMinutes(exit) : workingEnd;
  if (end <= start) return { minutes: 0, inferred: false, review: true };
  if (!workingDay) return { minutes: end - start, inferred: false, review: false };
  const before = Math.max(0, Math.min(end, workingStart) - start);
  const after = Math.max(0, end - Math.max(start, workingEnd));
  const unsafeInference = (!exit && start >= workingEnd) || (!entry && end <= workingStart);
  return { minutes: unsafeInference ? 0 : before + after, inferred: !entry || !exit, review: unsafeInference };
}
