export const config = {
  apiBaseUrl: process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8080',
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? 'https://eqlreobcizgtxviqegdh.supabase.co',
  supabaseAnonKey:
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ??
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVxbHJlb2JjaXpndHh2aXFlZ2RoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2OTEyMTAsImV4cCI6MjA5NzI2NzIxMH0.usen6Y2UCgYaNjrxo3jiUWH14h-fEI7p7XnXm0wuLWc',
};
