'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Stats {
  totalUsers: number;
  activeRiders: number;
  tripsToday: number;
  revenueToday: number;
  companyRevenueToday: number;
  pendingVerifications: number;
}

export default function OverviewPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get('/api/admin/stats').then(setStats).catch((e) => setError(e.message));
  }, []);

  const cards = [
    { label: 'Total Users', value: stats?.totalUsers, accent: 'text-sky-600' },
    { label: 'Active Riders (online)', value: stats?.activeRiders, accent: 'text-emerald-600' },
    { label: 'Trips Today', value: stats?.tripsToday, accent: 'text-indigo-600' },
    { label: 'Gross Volume Today', value: stats ? `KES ${stats.revenueToday.toLocaleString()}` : undefined, accent: 'text-amber-600' },
    { label: 'Company Earnings Today (20/25% cut)', value: stats ? `KES ${stats.companyRevenueToday.toLocaleString()}` : undefined, accent: 'text-emerald-600' },
    { label: 'Pending Verifications', value: stats?.pendingVerifications, accent: 'text-rose-600' },
  ];

  return (
    <div>
      <h1 className="mb-1 text-2xl font-bold">Dashboard</h1>
      <p className="mb-6 text-sm text-slate-500">Live platform metrics</p>

      {error && <ErrorBox message={error} />}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {cards.map((c) => (
          <div key={c.label} className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <div className="text-sm text-slate-500">{c.label}</div>
            <div className={`mt-2 text-3xl font-bold ${c.accent}`}>
              {c.value ?? <span className="text-slate-300">—</span>}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/** Small reusable delete action with a confirm prompt. */
export function DeleteButton({ onDelete, label = 'Delete' }: { onDelete: () => Promise<void>; label?: string }) {
  const [busy, setBusy] = useState(false);
  return (
    <button
      onClick={async () => {
        if (!window.confirm('Delete this permanently? This cannot be undone.')) return;
        setBusy(true);
        try {
          await onDelete();
        } catch (e) {
          window.alert((e as Error).message);
        } finally {
          setBusy(false);
        }
      }}
      disabled={busy}
      className="rounded-lg border border-rose-200 px-3 py-1.5 text-xs font-medium text-rose-600 transition hover:bg-rose-50 disabled:opacity-50"
      title="Delete"
    >
      {busy ? '…' : `🗑 ${label}`}
    </button>
  );
}

export function ErrorBox({ message }: { message: string }) {
  return (
    <div className="mb-6 rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
      {message.includes('Failed to fetch')
        ? 'Cannot reach the backend API. Is it running on the configured URL?'
        : message}
    </div>
  );
}
