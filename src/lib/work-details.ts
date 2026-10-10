import type { WorkRecord } from "./demo"
import { recordMonth } from "./records"

export function recordDate(r: WorkRecord) {
  if (r.isoDate) return r.isoDate
  if (/^\d{2}\/\d{2}\/\d{4}$/.test(r.date))
    return r.date.split("/").reverse().join("-")
  const month = recordMonth(r)
  return month ? `${month}-${r.date.split(" ")[0].padStart(2, "0")}` : ""
}
export function effectiveTimes(r: WorkRecord) {
  return {
    entry: r.entry || (r.inferredEntry ? r.scheduleStart : undefined),
    exit: r.exit || (r.inferredExit ? r.scheduleEnd : undefined),
  }
}
export function needsReview(r: WorkRecord) {
  return (
    r.status === "Pendiente" ||
    (r.status === "Automático" && !!(r.inferredEntry || r.inferredExit))
  )
}
export function reviewReason(r: WorkRecord) {
  if (r.inferredEntry || r.inferredExit) return "Horario inferido"
  if (!r.entry || !r.exit) return "Movimiento incompleto"
  return "Período por revisar"
}
export function recognized(r: WorkRecord) {
  return ["Automático", "Aprobado", "Corregido"].includes(r.status)
}
export function overtimeDetail(r: WorkRecord) {
  const { entry, exit } = effectiveTimes(r)
  if (!entry || !exit || exit <= entry) return null
  const minutes = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3))
  const start = minutes(entry),
    end = minutes(exit)
  if (r.workingDay === false) return { before: 0, after: 0, full: end - start }
  if (!r.scheduleStart || !r.scheduleEnd || r.workingDay === undefined)
    return null
  return {
    before: Math.max(0, Math.min(end, minutes(r.scheduleStart)) - start),
    after: Math.max(0, end - Math.max(start, minutes(r.scheduleEnd))),
    full: 0,
  }
}
