import { supabaseAdmin } from '../src/config/supabase';
(async () => {
  const { data, error } = await supabaseAdmin.from('fare_config').select('vehicle_class, minimum_fare');
  if (error) { console.log('SCHEMA_NOT_APPLIED:', error.message); process.exit(0); }
  console.log('SCHEMA_OK rows=' + (data?.length ?? 0), JSON.stringify(data));
  process.exit(0);
})();
