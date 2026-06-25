'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

const NAV = [
  { href: '/aaddmmiinn', label: 'Overview', icon: '📊' },
  { href: '/aaddmmiinn/riders', label: 'Verifications', icon: '🪪' },
  { href: '/aaddmmiinn/founding', label: 'Founding Riders', icon: '🎖️' },
  { href: '/aaddmmiinn/trips', label: 'Trips', icon: '🛣️' },
  { href: '/aaddmmiinn/payouts', label: 'Payouts', icon: '💸' },
  { href: '/aaddmmiinn/plans', label: 'Commuter Plans', icon: '🔁' },
  { href: '/aaddmmiinn/disputes', label: 'Disputes', icon: '⚖️' },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) {
        router.replace('/login');
      } else {
        setReady(true);
      }
    });
  }, [router]);

  async function signOut() {
    await supabase.auth.signOut();
    router.replace('/login');
  }

  if (!ready) {
    return <div className="flex min-h-screen items-center justify-center text-slate-400">Loading…</div>;
  }

  return (
    <div className="flex min-h-screen bg-slate-50 text-slate-800">
      <aside className="flex w-60 flex-col border-r border-slate-200 bg-white">
        <div className="px-5 py-5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="U-Bike" className="h-9 w-auto" />
        </div>
        <nav className="flex-1 space-y-1 px-3">
          {NAV.map((item) => {
            const active = pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition ${
                  active ? 'bg-sky-50 text-sky-700' : 'text-slate-600 hover:bg-slate-100'
                }`}
              >
                <span>{item.icon}</span>
                {item.label}
              </Link>
            );
          })}
        </nav>
        <button onClick={signOut} className="m-3 rounded-lg px-3 py-2 text-left text-sm text-slate-500 hover:bg-slate-100">
          ⎋ Sign out
        </button>
      </aside>
      <main className="flex-1 overflow-auto p-8">{children}</main>
    </div>
  );
}
