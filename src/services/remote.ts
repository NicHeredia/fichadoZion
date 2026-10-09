import { supabase } from "../lib/supabase";
import type { RemoteData } from "../app/DataContext";

export async function callRpc<T>(name: string, args?: Record<string, unknown>): Promise<T> {
  if (!supabase) throw new Error("La conexión no está configurada.");
  const { data, error } = await supabase.rpc(name, args);
  if (error) {
    if (error.code === "PGRST202" || error.code === "42883") throw new Error("Falta instalar la migración 003_admin_dashboard.sql en Supabase. Consultá SUPABASE_SETUP.md.");
    throw new Error(error.message || "No se pudo completar la operación. Revisá la conexión.");
  }
  return data as T;
}
export async function loadRemoteData(): Promise<RemoteData> {
  const data = await callRpc<RemoteData>("get_app_data");
  if (!data?.profile || !Array.isArray(data.records) || !Array.isArray(data.employees)) throw new Error("La respuesta del servidor es inválida.");
  return data;
}
