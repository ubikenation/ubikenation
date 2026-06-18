import axios from 'axios';
import { createClient } from '@supabase/supabase-js';
import { supabaseAdmin } from '../src/config/supabase';
import { env } from '../src/config/env';
const BASE = 'https://ubikenation.onrender.com';
const anon = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
(async () => {
  const email = `errand_${Date.now()}@gmail.com`;
  const { data } = await supabaseAdmin.auth.admin.createUser({ email, password: 'passw0rd!', email_confirm: true, user_metadata: { role: 'customer', full_name: 'Errand Test' } });
  await supabaseAdmin.from('profiles').upsert({ id: data.user!.id, role: 'customer', email });
  const { data: s } = await anon.auth.signInWithPassword({ email, password: 'passw0rd!' });
  const token = s.session!.access_token;
  const api = axios.create({ baseURL: BASE, headers: { Authorization: `Bearer ${token}` }, validateStatus: () => true });

  const few = await api.post('/api/fare/errand-estimate', { errandType: 'grocery_shopping', description: '2kg sugar\n1 loaf bread', distanceKm: 3, durationMin: 9 });
  const many = await api.post('/api/fare/errand-estimate', { errandType: 'grocery_shopping', description: '2kg sugar\n1 loaf bread\n500g rice\n1L milk\n6 eggs\n2 soap bars', distanceKm: 3, durationMin: 9 });
  console.log('2 items  ->', JSON.stringify(few.data.data ?? few.data));
  console.log('6 items  ->', JSON.stringify(many.data.data ?? many.data));

  await supabaseAdmin.auth.admin.deleteUser(data.user!.id);
  process.exit(0);
})();
