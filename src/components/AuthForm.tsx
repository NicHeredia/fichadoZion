import { useRef, useState, type FormEvent } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";
import { ArrowRight, Eye, EyeOff, LockKeyhole, Mail, UserRound } from "lucide-react";

type Mode = "login" | "signup";
function authMessage(failure: unknown, mode: Mode) {
  const code = failure && typeof failure === "object" && "code" in failure ? String(failure.code) : "";
  switch (code) {
    case "user_already_exists": case "email_exists": return "Este correo ya tiene una cuenta. Elegí Iniciar sesión.";
    case "signup_disabled": return "El registro está deshabilitado. Contactá al administrador.";
    case "email_not_confirmed": return "Tu correo todavía no está confirmado. Revisá tu correo o contactá al administrador.";
    case "weak_password": return "La contraseña no cumple los requisitos. Probá con una contraseña más larga.";
    case "email_address_invalid": return "Revisá que el correo esté escrito correctamente.";
    case "over_email_send_rate_limit": case "over_request_rate_limit": return "Hubo demasiados intentos. Esperá un momento y volvé a intentar.";
    default: return mode === "signup" ? "No se pudo crear la cuenta. Revisá los datos y la conexión e intentá nuevamente." : "No se pudo iniciar sesión. Revisá el correo, la contraseña y la conexión.";
  }
}

export default function AuthForm({ onAuthenticated }: { onAuthenticated: (session: Session) => void }) {
  const [mode, setMode] = useState<Mode>("login");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const lock = useRef(false);
  function changeMode(next: Mode) {
    if (lock.current) return;
    setMode(next); setError(""); setNotice(""); setShowPassword(false);
  }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (lock.current || !supabase) return;
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") || "").trim();
    const password = String(form.get("password") || "");
    const name = String(form.get("name") || "").trim();
    setError(""); setNotice("");
    if (!email || !password || (mode === "signup" && (!name || name.length > 150 || password.length < 6))) {
      setError(mode === "signup" ? "Completá tu nombre, correo y una contraseña de al menos 6 caracteres." : "Completá el correo y la contraseña.");
      return;
    }
    lock.current = true; setBusy(true);
    try {
      if (mode === "signup") {
        const { data, error } = await supabase.auth.signUp({ email, password, options: { data: { display_name: name } } });
        if (error) throw error;
        if (data.session) onAuthenticated(data.session);
        else if (!data.user) throw new Error("No se recibió el usuario.");
        else if (data.user.identities?.length === 0) setError("Este correo ya tiene una cuenta. Elegí Iniciar sesión.");
        else setNotice("Revisá tu correo para activar la cuenta. Después podés iniciar sesión.");
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        if (!data.session) throw new Error("No se recibió una sesión.");
        onAuthenticated(data.session);
      }
    } catch (failure) { setError(authMessage(failure, mode)); }
    finally { lock.current = false; setBusy(false); }
  }
  return <section className="auth-form" aria-labelledby="auth-heading">
    <div className="auth-switch" aria-label="Acceso a Fichado Zion ortopedia"><button type="button" aria-pressed={mode === "login"} disabled={busy} className={mode === "login" ? "active" : ""} onClick={() => changeMode("login")}>Iniciar sesión</button><button type="button" aria-pressed={mode === "signup"} disabled={busy} className={mode === "signup" ? "active" : ""} onClick={() => changeMode("signup")}>Crear cuenta</button></div>
    <span className="auth-form-eyebrow">{mode === "signup" ? "SUMATE AL EQUIPO" : "BIENVENIDO A ZION"}</span>
    <h2 id="auth-heading">{mode === "signup" ? "Creá tu cuenta" : "Qué bueno verte"}</h2>
    <p className="auth-description">{mode === "signup" ? "Completá tus datos para empezar a registrar tu jornada." : "Ingresá a tu espacio de trabajo con tu correo y contraseña."}</p>
    {error && <p className="error-banner" role="alert">{error}</p>}
    {notice && <p className="success-banner" role="status">{notice}</p>}
    <form key={mode} onSubmit={submit}><fieldset disabled={busy}>
      {mode === "signup" && <label>Nombre y apellido<span className="auth-input"><UserRound size={18} aria-hidden="true" /><input name="name" placeholder="Tu nombre completo" autoComplete="name" required maxLength={150} /></span></label>}
      <label>Correo electrónico<span className="auth-input"><Mail size={18} aria-hidden="true" /><input type="email" name="email" placeholder="nombre@correo.com" autoComplete={mode === "signup" ? "email" : "username"} required /></span></label>
      <label>Contraseña<span className="auth-input"><LockKeyhole size={18} aria-hidden="true" /><input type={showPassword ? "text" : "password"} name="password" placeholder={mode === "signup" ? "Al menos 6 caracteres" : "Ingresá tu contraseña"} autoComplete={mode === "signup" ? "new-password" : "current-password"} minLength={mode === "signup" ? 6 : undefined} required /><button className="auth-password-toggle" type="button" aria-label={showPassword ? "Ocultar contraseña" : "Mostrar contraseña"} aria-pressed={showPassword} onClick={() => setShowPassword(!showPassword)}>{showPassword ? <EyeOff size={18} /> : <Eye size={18} />}</button></span></label>
      {mode === "signup" && <p className="auth-hint">Al menos 6 caracteres. Tu cuenta se crea como empleado.</p>}
      <button className="btn btn-primary auth-submit" disabled={busy}>{busy ? (mode === "signup" ? "Creando cuenta…" : "Ingresando…") : (mode === "signup" ? "Crear cuenta" : "Ingresar")}<ArrowRight size={18} aria-hidden="true" /></button>
    </fieldset></form>
  </section>;
}
