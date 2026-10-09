import { Badge } from "./ui";

export function StatusBadge({ status }: { status: string }) {
  const tone = status === "Aprobado" || status === "Automático" ? "green" : status === "Pendiente" ? "orange" : status === "Rechazado" ? "red" : "blue";
  return <Badge tone={tone}>{status}</Badge>;
}
export default StatusBadge;
