export type ManualPunchInput = {
  employeeId: string
  kind: "Entrada" | "Salida"
  institutionId: string
  date: string
  time: string
  reason: string
  notes: string
  targetId: string | null
}
export type ManualSessionInput = Omit<ManualPunchInput, "kind" | "time" | "targetId"> & {
  entry: string
  exit: string
}
