import { useRemoteData } from "../app/DataContext";
import { useRef, useState } from "react";
import { Save } from "lucide-react";
import { Button, Card, Input, PageTitle } from "../components/ui";
import { defaultSettings, getSettings, saveSettings, type SettingsData } from "../lib/settings";
import { TIME_ZONE } from "../lib/records";
export function Settings() {
  const remote = useRemoteData();
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [initial] = useState(() => { try { return { data: remote?.settings ?? getSettings(), error: "" }; } catch { return { data: { ...defaultSettings }, error: "La configuración guardada no se pudo leer. Revisá los valores y guardá para reemplazarla." }; } });
  const [settings, setSettings] = useState<SettingsData>(initial.data);
  const [places, setPlaces] = useState(settings.institutions.join("\n"));
  const [holidays, setHolidays] = useState(settings.holidays.join("\n"));
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (lock.current) return;
    lock.current = true; setBusy(true);
    try {
      const next = { ...settings, institutions: [...new Set(places.split("\n").map(v => v.trim()).filter(Boolean))], holidays: [...new Set(holidays.split("\n").map(v => v.trim()).filter(Boolean))] };
      if (remote) await remote.saveSettings(next); else saveSettings(next);
      setError(""); setNotice("Configuración guardada. Se aplicará a los próximos fichajes; los anteriores conservan su cálculo.");
    } catch (failure) { setNotice(""); setError(failure instanceof Error ? failure.message : "No se pudo guardar la configuración."); }
    finally { lock.current = false; setBusy(false); }
  }
  return <><PageTitle title="Configuración e instituciones" subtitle={remote ? "Jornada, instituciones y feriados del equipo. Los períodos existentes conservan las reglas con las que fueron creados." : "Reglas locales de la demostración. No modifican datos ni permisos en Supabase."} />
    {initial.error && !notice && <p role="alert" className="error-banner">{initial.error}</p>}
    {error && <p role="alert" className="error-banner">{error}</p>}{notice && <p role="status" className="success-banner">{notice}</p>}
    <form onSubmit={save} className="settings-content"><fieldset disabled={busy} className="settings-content"><Card><h2>Jornada habitual</h2><div className="form-grid"><label>Entrada<Input type="time" required value={settings.startsAt} onChange={e => setSettings({ ...settings, startsAt: e.target.value })} /></label><label>Salida<Input type="time" required value={settings.endsAt} onChange={e => setSettings({ ...settings, endsAt: e.target.value })} /></label><label className="full">Días laborales<div className="day-picker">{["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"].map((day, index) => <button type="button" aria-pressed={settings.weekdays.includes(index)} key={day} className={settings.weekdays.includes(index) ? "selected" : ""} onClick={() => setSettings({ ...settings, weekdays: settings.weekdays.includes(index) ? settings.weekdays.filter(d => d !== index) : [...settings.weekdays, index] })}>{day}</button>)}</div></label></div><p>Zona horaria: {TIME_ZONE}. Los turnos que cruzan medianoche quedan pendientes de revisión.</p></Card>
    <Card><h2>Instituciones</h2><label>Un lugar por línea<textarea value={places} onChange={e => setPlaces(e.target.value)} rows={5} required /></label><p>{remote ? "Las instituciones quitadas se deshabilitan; sus movimientos anteriores se conservan." : "Además, el formulario permite indicar otro lugar."}</p></Card><Card><h2>Feriados</h2><label>Una fecha por línea, formato AAAA-MM-DD<textarea value={holidays} onChange={e => setHolidays(e.target.value)} rows={4} placeholder="2026-12-25" /></label><p>En días no laborables se cuenta el período completo cuando están ambos horarios.</p></Card><Button type="submit" disabled={busy}><Save size={16} /> {busy ? "Guardando…" : "Guardar cambios"}</Button></fieldset></form>
  </>;
}
export default Settings;
