import { supabaseAdmin } from '../src/config/supabase';
const EMAIL = 'admin@ubike.co.ke';
const PASSWORD = 'UBikeAdmin2026!';
(async () => {
  const { data: list } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  const existing = list.users.find((u) => u.email === EMAIL);
  let id = existing?.id;
  if (existing) {
    await supabaseAdmin.auth.admin.updateUserById(existing.id, { password: PASSWORD, email_confirm: true });
  } else {
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
      email: EMAIL, password: PASSWORD, email_confirm: true,
      user_metadata: { full_name: 'U-Bike Admin', role: 'admin' },
    });
    if (error) { console.log('ERR', error.message); process.exit(1); }
    id = data.user!.id;
  }
  await supabaseAdmin.from('profiles').upsert({ id, role: 'admin', full_name: 'U-Bike Admin', email: EMAIL });
  console.log('ADMIN_READY email=' + EMAIL + ' password=' + PASSWORD);
  process.exit(0);
})();
