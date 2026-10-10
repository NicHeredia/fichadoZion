import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

// Motor PostgreSQL aislado. auth y cron se simulan; las funciones de negocio
// y los triggers se cargan directamente de las migraciones del proyecto.
const db = new PGlite();
const sqlFile = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
await db.exec(`
  create role anon; create role authenticated;
  create schema auth;
  create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
  $$;
  grant usage on schema auth to authenticated,anon;
  grant execute on function auth.uid() to authenticated,anon;
  create schema cron;
  create table cron.job(jobid bigint generated always as identity,jobname text,active boolean default true,schedule text);
  create table cron.job_run_details(jobid bigint,end_time timestamptz,start_time timestamptz,status text,return_message text);
  create function cron.schedule(name text,schedule text,command text) returns bigint language sql as $$
    insert into cron.job(jobname,schedule) values(name,schedule) returning jobid;
  $$;
`);
for (const name of ["001_initial_schema", "002_secure_registration", "003_admin_dashboard", "004_automatic_checkout", "005_overtime_compensations", "006_admin_manual_punch", "007_fix_settings_save", "008_daily_workflow", "009_specific_checkout"]) {
  try { await db.exec(sqlFile(`supabase/migrations/${name}.sql`).replace(/^create extension[^;]*;/gm, "")); }
  catch (error) { console.error(`Migración ${name}: ${error.message}; posición ${error.position || error.internalPosition || "desconocida"}; contexto ${error.where || error.internalQuery || ""}`); await db.close(); process.exit(1); }
}
for (const name of ["punch_pairing", "admin", "automatic_checkout", "security", "compensations", "manual_punch", "settings", "daily_workflow", "specific_checkout"]) {
  try {
    await db.exec(sqlFile(`supabase/tests/${name}.sql`));
    console.log(`SQL existente aprobado: ${name}`);
  } catch (error) {
    await db.exec("rollback; reset role");
    console.log(`SQL existente falló: ${name}: ${error.message}`);
    process.exitCode = 1;
  }
}

const output = [];
await db.exec(sqlFile("supabase/VALIDAR_BASE_REAL.sql"));
console.log("Validación unificada aprobada en motor local; Cron local simulado.");
async function scenario(name, events, expected, { working = true, finalize = false, changeSchedule = false } = {}) {
  await db.exec("begin");
  try {
    const { rows: [ids] } = await db.query("select gen_random_uuid() as u,gen_random_uuid() as a,gen_random_uuid() as b");
    await db.query("insert into auth.users values($1,$2,$3::jsonb)", [ids.u, ids.u + "@example.invalid", '{"display_name":"Escenario"}']);
    await db.query("insert into public.institutions(id,name) values($1,'A'),($2,'B')", [ids.a, ids.b]);
    await db.exec(`update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=${working ? "array[0,1,2,3,4,5,6]" : "array[]::integer[]"}; delete from public.holidays where holiday_date between '2195-01-05' and '2195-01-06'`);
    const { rows: [employee] } = await db.query("select id from public.employees where profile_id=$1", [ids.u]);
    for (const [kind, time, place = "a", day = "05"] of events) {
      await db.query(`insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
        values($1,$2,$3::public.event_type,$4::timestamptz,'Prueba',$5)`,
      [employee.id, ids[place], kind, `2195-01-${day} ${time}:00-03`, ids.u]);
      if (changeSchedule && kind === "entry") await db.exec("update public.app_settings set starts_at='09:00',ends_at='18:00'");
    }
    if (finalize) await db.exec("select public.app_finalize_open_sessions('2195-01-06 03:00:00+00')");
    const { rows } = await db.query(`select to_char(s.starts_at at time zone 'America/Argentina/Buenos_Aires','HH24:MI') as entry,
      to_char(s.ends_at at time zone 'America/Argentina/Buenos_Aires','HH24:MI') as exit,
      s.status,c.total_minutes as minutes,s.entry_inferred,s.exit_inferred
      from public.work_sessions s join public.overtime_calculations c on c.session_id=s.id
      where s.employee_id=$1 order by s.work_date,s.starts_at nulls last,s.ends_at nulls last`, [employee.id]);
    assert.deepEqual(rows.map(r => [r.entry,r.exit,r.status,r.minutes]), expected, name);
    const { rows: [count] } = await db.query("select count(*)::int as n from public.time_events where employee_id=$1", [employee.id]);
    assert.equal(count.n, events.length, name + ": eventos conservados");
    output.push({ name, events: count.n, sessions: rows });
    console.log("OK: " + name);
  } finally { await db.exec("rollback"); }
}
await scenario("06–20 laboral", [["entry","06:00"],["exit","20:00"]], [["06:00","20:00","automatic",300]]);
await scenario("06–16 laboral", [["entry","06:00"],["exit","16:00"]], [["06:00","16:00","automatic",120]]);
await scenario("08–17 laboral", [["entry","08:00"],["exit","17:00"]], [["08:00","17:00","automatic",0]]);
await scenario("09–16 laboral", [["entry","09:00"],["exit","16:00"]], [["09:00","16:00","automatic",0]]);
await scenario("18–20 laboral", [["entry","18:00"],["exit","20:00"]], [["18:00","20:00","automatic",120]]);
await scenario("06–07 laboral", [["entry","06:00"],["exit","07:00"]], [["06:00","07:00","automatic",60]]);
await scenario("07:45–17:30 laboral", [["entry","07:45"],["exit","17:30"]], [["07:45","17:30","automatic",45]]);
await scenario("06–20 no laboral", [["entry","06:00"],["exit","20:00"]], [["06:00","20:00","automatic",840]], { working:false });
await scenario("Solo entrada 06 antes del cierre", [["entry","06:00"]], [["06:00",null,"pending",0]]);
await scenario("Solo entrada 06 al finalizar día", [["entry","06:00"]], [["06:00","17:00","automatic",120]], { finalize:true });
await scenario("Solo entrada 18 al finalizar día", [["entry","18:00"]], [["18:00",null,"pending",0]], { finalize:true });
await scenario("Solo entrada no laboral", [["entry","06:00"]], [["06:00",null,"pending",0]], { working:false,finalize:true });
await scenario("Solo salida 20 laboral", [["exit","20:00"]], [["08:00","20:00","automatic",180]]);
await scenario("Solo salida 16 laboral", [["exit","16:00"]], [["08:00","16:00","automatic",0]]);
await scenario("Solo salida 07 laboral", [["exit","07:00"]], [[null,"07:00","pending",0]]);
await scenario("Solo salida no laboral", [["exit","20:00"]], [[null,"20:00","pending",0]], { working:false });
await scenario("Dos entradas y una salida", [["entry","06:00"],["entry","07:00"],["exit","20:00"]], [["06:00",null,"pending",0],["07:00",null,"pending",0],[null,"20:00","pending",0]], { finalize:true });
await scenario("Instituciones diferentes", [["entry","06:00","a"],["exit","20:00","b"]], [["06:00",null,"pending",0],["08:00","20:00","automatic",180]], { finalize:true });
await scenario("Cruce de medianoche", [["entry","22:00"],["exit","02:00","a","06"]], [["22:00",null,"pending",0],[null,"02:00","pending",0]], { finalize:true });
await scenario("Dos períodos separados", [["entry","06:00"],["exit","10:00"],["entry","15:00"],["exit","20:00"]], [["06:00","10:00","automatic",120],["15:00","20:00","automatic",180]]);
await scenario("Cambio de jornada después de entrada", [["entry","06:00"],["exit","20:00"]], [["06:00","20:00","automatic",300]], { changeSchedule:true });
await db.close();
console.log(`${output.length} escenarios SQL aprobados; base local aislada.`);
