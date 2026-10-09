import { createClient, type SupabaseClient } from "@supabase/supabase-js";
const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY;
export const isDemoMode = import.meta.env.VITE_DATA_MODE !== "supabase";
export let configurationError: string | null = null;
function initialize(): SupabaseClient | null {
  if (isDemoMode) return null;
  if (!url || !key) { configurationError = "Completá VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY en .env.local y reiniciá el servidor."; return null; }
  try {
    if (key.startsWith("sb_secret_")) throw new Error("Usá la clave pública publishable/anon, nunca una secret o service_role.");
    if (key.split(".").length === 3) {
      const payload = JSON.parse(atob(key.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
      if (payload.role === "service_role") throw new Error("Usá la clave pública publishable/anon, nunca una secret o service_role.");
    }
    return createClient(url, key);
  } catch (failure) { configurationError = failure instanceof Error ? failure.message : "Configuración de Supabase inválida."; return null; }
}
export const supabase = initialize();
