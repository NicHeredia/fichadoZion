export type CorrectionRequest = {
  id: string
  employee_id: string
  session_id: string | null
  institution_id: string
  work_date: string
  proposed_entry: string | null
  proposed_exit: string | null
  institution_only?: boolean
  reason: string
  status: "pending" | "approved" | "rejected"
  resolution_notes: string | null
  created_at: string
}
export type CorrectionInput = {
  institutionOnly?: boolean
  sessionId: string | null
  institutionId: string
  date: string
  entry: string
  exit: string
  reason: string
}
