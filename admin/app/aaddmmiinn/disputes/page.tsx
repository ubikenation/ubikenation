'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { ErrorBox } from '../page';

interface Dispute {
  id: string;
  status: string;
  final_fare?: number;
  upfront_amount?: number;
  cancel_reason?: string;
  created_at: string;
  profiles?: { full_name?: string } | null;
}

export default function DisputesPage() {
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  function reload() {
    api.get('/api/admin/disputes').then((d) => setDisputes(d as Dispute[])).catch((e) => setError(e.message));
  }

  useEffect(() => {
    reload();
  }, []);

  async function act(id: string, action: 'refund' | 'resolve') {
    setBusyId(id);
    setError(null);
    try {
      await api.post(`/api/admin/trips/${id}/${action}`);
      reload();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div>
      <h1 className="mb-1 text-2xl font-bold">Disputes</h1>
      <p className="mb-6 text-sm text-slate-500">Trips flagged by a customer or rider for resolution ({disputes.length})</p>

      {error && <ErrorBox message={error} />}

      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-slate-500">
            <tr>
              <th className="px-4 py-3 font-medium">Customer</th>
              <th className="px-4 py-3 font-medium">Fare</th>
              <th className="px-4 py-3 font-medium">Reason</th>
              <th className="px-4 py-3 font-medium">Opened</th>
              <th className="px-4 py-3 font-medium">Resolve</th>
            </tr>
          </thead>
          <tbody>
            {disputes.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-slate-400">No open disputes 🎉</td>
              </tr>
            )}
            {disputes.map((d) => (
              <tr key={d.id} className="border-t border-slate-100">
                <td className="px-4 py-3 font-medium">{d.profiles?.full_name ?? '—'}</td>
                <td className="px-4 py-3">KES {d.final_fare ?? '—'}</td>
                <td className="px-4 py-3 text-slate-500">{d.cancel_reason ?? '—'}</td>
                <td className="px-4 py-3 text-slate-500">{new Date(d.created_at).toLocaleString()}</td>
                <td className="px-4 py-3">
                  <div className="flex gap-2">
                    <button
                      onClick={() => act(d.id, 'refund')}
                      disabled={busyId === d.id}
                      className="rounded-lg bg-rose-600 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-rose-700 disabled:opacity-50"
                    >
                      {busyId === d.id ? '…' : 'Refund customer'}
                    </button>
                    <button
                      onClick={() => act(d.id, 'resolve')}
                      disabled={busyId === d.id}
                      className="rounded-lg border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-600 transition hover:bg-slate-50 disabled:opacity-50"
                    >
                      Resolve (no refund)
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
