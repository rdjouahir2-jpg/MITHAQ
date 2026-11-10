-- Keep audit history append-only and inaccessible to direct client table writes.
revoke all on table public.audit_logs from public, anon, authenticated;
grant all on table public.audit_logs to service_role;

-- Direct safety-report table writes are replaced by the participant-checked RPC.
revoke insert, update, delete on table public.safety_reports from public, anon, authenticated;
