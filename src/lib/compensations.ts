export type CompensationStatus = "scheduled" | "completed" | "cancelled";
export type Compensation = {
  id: string; employeeId: string; minutes: number; restDate: string;
  reason: string; status: CompensationStatus; cancellationReason: string | null;
  createdAt: string; updatedAt: string;
};
export type CompensationBalance = { employeeId: string; earned: number; reserved: number; used: number; available: number };
export type CompensationInput = { employeeId: string; minutes: number; restDate: string; reason: string; status: "scheduled" | "completed" };
export type CompensationData = { compensations: Compensation[]; balances: CompensationBalance[] };
export const compensationLabels: Record<CompensationStatus,string> = { scheduled: "Programado", completed: "Realizado", cancelled: "Cancelado" };
export function parseDuration(value: string): number {
  const match = /^(\d{1,6}):([0-5]\d)$/.exec(value.trim());
  if (!match) throw new Error("Ingresá las horas en formato H:MM, por ejemplo 3:30.");
  const minutes = Number(match[1]) * 60 + Number(match[2]);
  if (minutes <= 0) throw new Error("La cantidad debe ser mayor que cero.");
  return minutes;
}
export function exportCompensations(items: Compensation[], employees: { id: string; name: string; employeeNumber?: string }[], filename = "compensaciones.csv") {
  const cell = (value: unknown) => {
    let text = String(value ?? "");
    if (/^\s*[=+@-]/.test(text)) text = "'" + text;
    return '"' + text.replace(/"/g, '""') + '"';
  };
  const rows = [["Empleado", "Legajo", "Fecha descanso", "Horas", "Minutos", "Estado", "Motivo", "Motivo cancelación"], ...items.map(item => {
    const employee = employees.find(e => e.id === item.employeeId);
    return [employee?.name, employee?.employeeNumber, item.restDate, `${Math.floor(item.minutes / 60)}:${String(item.minutes % 60).padStart(2,"0")}`, item.minutes, compensationLabels[item.status], item.reason, item.cancellationReason];
  })];
  const url = URL.createObjectURL(new Blob(["\uFEFF" + rows.map(row => row.map(cell).join(";")).join("\r\n")], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a"); link.href = url; link.download = filename; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
