'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { ErrorBox } from '../page';

interface Payout {
  id: string;
  amount: number;
  mpesa_number: string;
  status: string;
  created_at: string;
  processed_at?: string;
}

const COLORS: Record<string, string> = {
  completed: 'bg-emerald-100 text-emerald-700',
  processing: 'bg-sky-100 text-sky-700',
  pending: 'bg-amber-100 text-amber-700',
  failed: 'bg-rose-100 text-rose-700',
};

export default function PayoutsPage() {
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get('/api/admin/payouts').then((d) => setPayouts(d as Payout[])).catch((e) => setError(e.message));
  }, []);

  const totalPending = payouts.filter((p) => p.status === 'pending').reduce((s, p) => s + p.amount, 0);

  return (
    <div>
      <h1 className="mb-1 text-2xl font-bold">Payouts</h1>
      <p className="mb-6 text-sm text-slate-500">Rider settlements to M-Pesa (80% share, 24–48h)</p>

      {error && <ErrorBox message={error} />}

      <div className="mb-6 inline-block rounded-2xl border border-amber-200 bg-amber-50 px-6 py-4">
        <div className="text-sm text-amber-700">Pending payouts</div>
        <div className="text-2xl font-bold text-amber-800">KES {totalPending.toLocaleString()}</div>
      </div>

      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-slate-500">
            <tr>
              <th className="px-4 py-3 font-medium">M-Pesa</th>
              <th className="px-4 py-3 font-medium">Amount</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Requested</th>
            </tr>
          </thead>
          <tbody>
            {payouts.length === 0 && (
              <tr>
                <td colSpan={4} className="px-4 py-8 text-center text-slate-400">No payouts yet.</td>
              </tr>
            )}
            {payouts.map((p) => (
              <tr key={p.id} className="border-t border-slate-100">
                <td className="px-4 py-3 font-medium">{p.mpesa_number || '—'}</td>
                <td className="px-4 py-3">KES {p.amount}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${COLORS[p.status] ?? 'bg-slate-100 text-slate-600'}`}>
                    {p.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-slate-500">{new Date(p.created_at).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
