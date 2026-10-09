export type ManualPunchInput = {
  employeeId: string; kind: "Entrada" | "Salida"; institutionId: string;
  date: string; time: string; reason: string; notes: string; targetId: string | null;
};
