/// Configuration for the U-Bike Bike Rider app.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eqlreobcizgtxviqegdh.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVxbHJlb2JjaXpndHh2aXFlZ2RoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2OTEyMTAsImV4cCI6MjA5NzI2NzIxMH0.usen6Y2UCgYaNjrxo3jiUWH14h-fEI7p7XnXm0wuLWc',
  );
}
