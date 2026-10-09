import { useAppRecords } from "../app/useAppRecords";
import { useRemoteData } from "../app/DataContext";
import { ArrowDownRight, ArrowRight, ArrowUpRight, CalendarDays, CheckCircle2, Clock3, Download, Users } from "lucide-react";
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Link } from "react-router";
import { Button, Card, PageTitle, Select } from "../components/ui";
import { StatusBadge } from "../components/StatusBadge";
import { employees, formatMinutes } from "../lib/demo";
import { useState } from "react";
import { exportRecords, localDate, recordMonth } from "../lib/records";

export function Dashboard() {
  const records = useAppRecords();
  const remote = useRemoteData();
  const directory = remote?.employees ?? employees;
  const [month, setMonth] = useState(localDate().slice(0, 7));
  const monthly = records.filter(r => recordMonth(r) === month);
  const accepted = monthly.filter(r => r.status !== "Rechazado");
  const today = records.filter(r => r.isoDate === localDate() && r.status !== "Rechazado");
  const stats = [
    { label: remote ? "Empleados activos" : "Empleados activos de demo", value: String(directory.filter(e => e.status === "Activo").length), note: remote ? "Directorio del equipo" : "Directorio de demostración", icon: Users, color: "blue", trend: "up" },
    { label: "Horas extras · " + month, value: formatMinutes(accepted.reduce((s, r) => s + r.minutes, 0)), note: "Calculadas desde el historial", icon: Clock3, color: "navy", trend: "up" },
    { label: "Horas extras · Hoy", value: formatMinutes(today.reduce((s, r) => s + r.minutes, 0)), note: today.length + (remote ? " registros" : " registros locales"), icon: CalendarDays, color: "green", trend: "up" },
    { label: "Pendientes de revisión", value: String(records.filter(r => r.status === "Pendiente").length), note: "Registros sin validar", icon: CheckCircle2, color: "orange", trend: "down" },
  ];
  const grouped = new Map<string, { name: string; minutes: number }>();
  accepted.forEach(r => { const key = r.employeeId || r.employee; const previous = grouped.get(key); grouped.set(key, { name: r.employee, minutes: (previous?.minutes || 0) + r.minutes }); });
  const bars = [...grouped].map(([id, item]) => ({ id, name: item.name, value: item.minutes / 60 })).sort((a, b) => b.value - a.value).slice(0, 5);
  let cumulative = 0;
  const chartData = Array.from({ length: new Date(Number(month.slice(0, 4)), Number(month.slice(5)), 0).getDate() }, (_, i) => {
    const day = String(i + 1).padStart(2, "0");
    cumulative += accepted.filter(r => (r.isoDate?.slice(8) || r.date.split(" ")[0].padStart(2, "0")) === day).reduce((s, r) => s + r.minutes, 0);
    return { day, current: cumulative / 60 };
  });
  return (
    <>
      <PageTitle
        title={remote ? "Hola, " + remote.profile.name : "Buenos días, Mariana"}
        subtitle={remote ? (remote.profile.role === "admin" ? "Resumen del equipo y horas extras registradas." : "Resumen de tus fichajes y horas extras.") : "Resumen de los datos de demostración y fichajes guardados en este navegador."}
        action={<div className="title-actions"><Select aria-label="Período" value={month} onChange={e => setMonth(e.target.value)}>{[...new Set([localDate().slice(0, 7), ...records.map(recordMonth)])].filter(Boolean).sort().reverse().map(m => <option key={m}>{m}</option>)}</Select><Button variant="secondary" disabled={!monthly.length} onClick={() => exportRecords(monthly)}><Download size={16} /> Exportar</Button></div>}
      />
      <div className="stats-grid">
        {stats.map(({ label, value, note, icon: Icon, color, trend }) => (
          <Card className="stat-card" key={label}>
            <div className={`stat-icon ${color}`}><Icon size={20} /></div>
            <div className="stat-label">{label}</div>
            <div className="stat-value">{value}</div>
            <div className={`stat-note ${trend === "up" ? "positive" : "warning"}`}>
              {trend === "up" ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />} {note}
            </div>
          </Card>
        ))}
      </div>
      <div className="dashboard-grid">
        <Card className="chart-card">
          <div className="card-head"><div><h2>Evolución del mes</h2><p>Horas extras acumuladas por día</p></div><div className="legend"><span><i className="dot current" />{month}</span></div></div>
          <div className="chart">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData} margin={{ top: 12, right: 8, left: -22, bottom: 0 }}>
                <defs><linearGradient id="areaBlue" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="var(--blue)" stopOpacity={0.2} /><stop offset="100%" stopColor="var(--blue)" stopOpacity={0} /></linearGradient></defs>
                <CartesianGrid vertical={false} stroke="var(--border)" strokeDasharray="3 3" />
                <XAxis dataKey="day" axisLine={false} tickLine={false} tick={{ fill: "var(--muted)", fontSize: 11 }} />
                <YAxis axisLine={false} tickLine={false} tick={{ fill: "var(--muted)", fontSize: 11 }} />
                <Tooltip contentStyle={{ borderRadius: 10, borderColor: "var(--border)", boxShadow: "var(--shadow)" }} />
                <Area type="monotone" dataKey="current" stroke="var(--blue)" fill="url(#areaBlue)" strokeWidth={2.5} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </Card>
        <Card className="ranking-card">
          <div className="card-head"><div><h2>Más horas extras</h2><p>Ranking del mes actual</p></div><Link to={remote?.profile.role === "employee" ? "/reportes" : "/empleados"}>Ver todos <ArrowRight size={14} /></Link></div>
          <div className="ranking">
            {bars.map((item, index) => (
              <div className="rank-row" key={item.id}>
                <span className="rank-number">{index + 1}</span><span className="rank-name">{item.name}</span>
                <div className="rank-bar"><i style={{ width: `${(item.value / Math.max(1, ...bars.map(b => b.value))) * 100}%` }} /></div><b>{formatMinutes(Math.round(item.value * 60))}</b>
              </div>
            ))}
          </div>
        </Card>
      </div>
      <Card className="table-card">
        <div className="card-head"><div><h2>Actividad reciente</h2><p>Últimos movimientos registrados por el equipo</p></div><Link to="/historial">Ver historial <ArrowRight size={14} /></Link></div>
        <div className="table-scroll">
          <table><thead><tr><th>Empleado</th><th>Fecha</th><th>Entrada</th><th>Salida</th><th>Institución</th><th>Horas extra</th><th>Estado</th></tr></thead>
          <tbody>{records.slice(0, 5).map((record) => <tr key={record.id}>
            <td><div className="person"><div className="avatar tiny">{record.initials}</div><b>{record.employee}</b></div></td>
            <td>{record.date}</td><td>{record.entry ?? "—"}{record.inferredEntry && <sup>*</sup>}</td><td>{record.exit ?? "—"}{record.inferredExit && <sup>*</sup>}</td>
            <td>{record.institution}</td><td><b>{record.minutes ? `${Math.floor(record.minutes / 60)}h ${record.minutes % 60 ? `${record.minutes % 60}m` : ""}` : "—"}</b></td>
            <td><StatusBadge status={record.status} /></td>
          </tr>)}{!records.length && <tr><td colSpan={7}>Todavía no hay fichajes registrados.</td></tr>}</tbody></table>
        </div>
        <div className="table-foot">Mostrando {Math.min(5, records.length)} de {records.length} movimientos <span>* Horario inferido por el sistema</span></div>
      </Card>
    </>
  );
}


export default Dashboard;
