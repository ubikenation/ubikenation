/// Central configuration for the U-Bike customer app.
///
/// The Supabase anon key is safe to ship in a client (it is protected by Row
/// Level Security). The service-role key must NEVER appear in the app.
class AppConfig {
  AppConfig._();

  /// Backend API base URL.
  /// - Android emulator reaches the host machine at 10.0.2.2
  /// - iOS simulator / web can use localhost
  /// Override at build time with: --dart-define=API_BASE_URL=https://api.ubike.co.ke
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eqlreobcizgtxviqegdh.supabase.co',
  );

  /// Public anon key (RLS-protected). Replace with your rotated key via dart-define.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVxbHJlb2JjaXpndHh2aXFlZ2RoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2OTEyMTAsImV4cCI6MjA5NzI2NzIxMH0.usen6Y2UCgYaNjrxo3jiUWH14h-fEI7p7XnXm0wuLWc',
  );

  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyCF1vIAN9RLx7poKLdaiQUl7fOZNrpDS6k',
  );
}
