import { Card, PageTitle } from "../components/ui";
import { useRemoteData } from "../app/DataContext";
import { TIME_ZONE } from "../lib/records";
export default function Audit() {
  const remote = useRemoteData();
  return <><PageTitle title="Auditoría" subtitle="Últimas 100 acciones del equipo. El servidor registra fichajes, decisiones, cambios de acceso, configuración, cierres y compensaciones." /><Card className="table-card"><div className="table-scroll"><table><thead><tr><th>Fecha y hora</th><th>Responsable</th><th>Acción</th><th>Entidad</th></tr></thead><tbody>{remote?.audit.map(event => <tr key={event.id}><td>{new Date(event.created_at).toLocaleString("es-AR", { timeZone: TIME_ZONE })}</td><td>{event.actor_name}</td><td>{event.action}</td><td>{({ time_event: "Fichaje", work_session: "Período", employee: "Empleado", settings: "Configuración", monthly_closure: "Cierre mensual", compensation: "Compensación" } as Record<string, string>)[event.entity_type] || event.entity_type}</td></tr>)}{!remote?.audit.length && <tr><td colSpan={4}>Todavía no hay acciones registradas.</td></tr>}</tbody></table></div></Card></>;
}
