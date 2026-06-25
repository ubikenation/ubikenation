'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { DeleteButton, ErrorBox } from '../page';

interface Plan {
  id: string;
  errand_type: string;
  description: string;
  frequency: string;
  time_of_day: string;
  fare_estimate: number;
  status: string;
  next_run_at?: string;
  created_at: string;
  profiles?: { full_name?: string } | null;
}

const COLORS: Record<string, string> = {
  active: 'bg-emerald-100 text-emerald-700',
  paused: 'bg-amber-100 text-amber-700',
  cancelled: 'bg-slate-100 text-slate-500',
};

export default function PlansPage() {
  const [plans, setPlans] = useState<Plan[]>([]);
  const [error, setError] = useState<string | null>(null);

  function reload() {
    api.get('/api/admin/plans').then((d) => setPlans(d as Plan[])).catch((e) => setError(e.message));
  }

  useEffect(() => {
    reload();
  }, []);

  const active = plans.filter((p) => p.status === 'active').length;

  return (
    <div>
      <h1 className="mb-1 text-2xl font-bold">Commuter Plans</h1>
      <p className="mb-6 text-sm text-slate-500">Recurring errand subscriptions ({active} active)</p>

      {error && <ErrorBox message={error} />}

      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-slate-500">
            <tr>
              <th className="px-4 py-3 font-medium">Customer</th>
              <th className="px-4 py-3 font-medium">Errand</th>
              <th className="px-4 py-3 font-medium">Schedule</th>
              <th className="px-4 py-3 font-medium">Fare/run</th>
              <th className="px-4 py-3 font-medium">Next run</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {plans.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-slate-400">No commuter plans yet.</td>
              </tr>
            )}
            {plans.map((p) => (
              <tr key={p.id} className="border-t border-slate-100">
                <td className="px-4 py-3 font-medium">{p.profiles?.full_name ?? '—'}</td>
                <td className="px-4 py-3">{p.errand_type.replace(/_/g, ' ')}</td>
                <td className="px-4 py-3 text-slate-500">{p.frequency} @ {String(p.time_of_day).slice(0, 5)}</td>
                <td className="px-4 py-3">KES {p.fare_estimate}</td>
                <td className="px-4 py-3 text-slate-500">{p.next_run_at ? new Date(p.next_run_at).toLocaleString() : '—'}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${COLORS[p.status] ?? 'bg-slate-100 text-slate-600'}`}>
                    {p.status}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <DeleteButton onDelete={async () => { await api.del(`/api/admin/plans/${p.id}`); reload(); }} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
