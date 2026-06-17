import { supabaseAdmin } from '../src/config/supabase';
(async () => {
  const tables = ['profiles','riders','trips','payments','payouts','wallets'];
  for (const t of tables) {
    const { count } = await supabaseAdmin.from(t).select('id', { count: 'exact', head: true });
    console.log(`  ${t}: ${count ?? 0}`);
  }
  process.exit(0);
})();
