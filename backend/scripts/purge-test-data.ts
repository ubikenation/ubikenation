/* Wipes ALL operational data for a clean production start.
 * Keeps the schema and the admin login (admin@ubike.co.ke) only. */
import { supabaseAdmin } from '../src/config/supabase';

const KEEP_ADMIN_EMAIL = 'admin@ubike.co.ke';
const ALL = '00000000-0000-0000-0000-000000000000';

async function wipe(table: string, idCol = 'id') {
  const { error, count } = await supabaseAdmin.from(table).delete({ count: 'exact' }).neq(idCol, ALL);
  console.log(`  ${error ? '❌ ' + table + ': ' + error.message : `✅ ${table}: ${count ?? 0} rows deleted`}`);
}

async function main() {
  console.log('\n=== PURGING TEST DATA (keeping admin only) ===\n');

  // Delete in FK-safe order (children first).
  await wipe('chat_messages');
  await wipe('ratings');
  await wipe('rider_violations');
  await wipe('payouts');
  await wipe('escrow', 'trip_id');
  await wipe('payments');
  await wipe('wallet_ledger');
  await wipe('wallets', 'profile_id');
  await wipe('trips');
  await wipe('vehicles');
  await wipe('riders');

  // Profiles + auth users, except the admin.
  const { data: adminProfile } = await supabaseAdmin
    .from('profiles').select('id').eq('email', KEEP_ADMIN_EMAIL).maybeSingle();
  const adminId = adminProfile?.id ?? ALL;

  const { error: pErr, count: pCount } = await supabaseAdmin
    .from('profiles').delete({ count: 'exact' }).neq('id', adminId);
  console.log(`  ${pErr ? '❌ profiles: ' + pErr.message : `✅ profiles: ${pCount ?? 0} deleted (admin kept)`}`);

  // Delete auth users except admin.
  const { data: list } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  let removed = 0;
  for (const u of list.users) {
    if (u.email === KEEP_ADMIN_EMAIL) continue;
    await supabaseAdmin.auth.admin.deleteUser(u.id);
    removed++;
  }
  console.log(`  ✅ auth users: ${removed} deleted (admin kept)`);

  // Reset founding program toggle/slots to defaults (slot usage derives from riders, now empty).
  await supabaseAdmin.from('founding_program').update({ enabled: true, bike_slots: 10, car_slots: 10 }).eq('id', 1);
  console.log('  ✅ founding_program reset (10 bike / 10 car free, enabled)');

  console.log('\n=== DONE. Database now holds only real data (zero until real signups). ===\n');
  process.exit(0);
}

main().catch((e) => { console.error('FATAL', e); process.exit(1); });
