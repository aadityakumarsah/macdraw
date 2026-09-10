import 'dotenv/config';
import { WebSocket } from 'ws';
import { resolveEnv, createAdminClient } from '@supabase/server/core';
import { createSupabaseContext } from '@supabase/server';

// supabase-js's RealtimeClient needs a global WebSocket; Node < 22 doesn't ship one.
if (!globalThis.WebSocket) globalThis.WebSocket = WebSocket;

/**
 * Resolved Supabase project configuration. Reads SUPABASE_URL, the plural key
 * vars and SUPABASE_JWKS_URL from .env (with the code paths reading directly).
 */
export function supabaseEnv() {
  const { data, error } = resolveEnv();
  if (error) throw error;
  return data;
}

/**
 * Admin client (secret key) — bypasses Row-Level Security.
 * Use only server-side for trusted operations.
 */
export function adminClient() {
  return createAdminClient();
}

/**
 * Request-scoped client honoring RLS. Verifies a Bearer JWT (then falls back to
 * a publishable-key apikey) before handing back the client, per @supabase/server.
 */
export async function requestClient(request) {
  const { data, error } = await createSupabaseContext(request, {
    auth: ['user', 'publishable'],
  });
  if (error) throw error;
  return data.supabase;
}

// Middleware shape for a fetch-style handler (e.g. a future API route).
export { withSupabase } from '@supabase/server';