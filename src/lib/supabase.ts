import { createClient, SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL?.trim()
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim()

export const supabaseConfigError = !url || !anonKey
  ? 'Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Copy .env.example to .env.local and add your Supabase project values.'
  : null

export const supabase: SupabaseClient | null = supabaseConfigError
  ? null
  : createClient(url!, anonKey!, { auth: { persistSession: true, autoRefreshToken: true } })

export function getSupabase(): SupabaseClient {
  if (!supabase) throw new Error(supabaseConfigError ?? 'Supabase is not configured.')
  return supabase
}
