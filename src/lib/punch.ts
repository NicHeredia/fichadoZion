export type PunchInput = {
  kind: "Entrada" | "Salida";
  institution: string;
  reason: string;
  notes: string;
  targetId?: string | null;
  confirmWithoutEntry?: boolean;
};

