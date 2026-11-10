import { createClient } from '@supabase/supabase-js'
import { publicConfig } from './public-config'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || publicConfig.supabaseUrl
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || publicConfig.supabaseAnonKey

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null
