'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { ErrorBox } from '../page';

interface Rider {
  id: string;
  kind: string;
  status: string;
  is_founding: boolean;
  registration_fee: number;
  registration_paid: boolean;
  rating_avg: number;
  created_at: string;
  profiles?: { full_name?: string; phone?: string; email?: string };
}

const STATUSES = ['under_review', 'submitted', 'approved', 'activated', 'suspended', 'banned'];

export default function RidersPage() {
  const [riders, setRiders] = useState<Rider[]>([]);
  const [filter, setFilter] = useState('under_review');
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const data = await api.get(`/api/admin/riders?status=${filter}`);
      setRiders(data as Rider[]);
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }, [filter]);

  useEffect(() => {
    load();
  }, [load]);

  async function act(id: string, action: 'approve' | 'reject', ban = false) {
    setBusyId(id);
    try {
      await api.post(`/api/admin/riders/${id}/${action}`, action === 'reject' ? { ban } : undefined);
      await load();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div>
      <h1 className="mb-1 text-2xl font-bold">Rider Verifications</h1>
      <p className="mb-6 text-sm text-slate-500">Approve or reject rider applications</p>

      <div className="mb-4 flex flex-wrap gap-2">
        {STATUSES.map((s) => (
          <button
            key={s}
            onClick={() => setFilter(s)}
            className={`rounded-full px-3 py-1 text-sm capitalize ${
              filter === s ? 'bg-sky-600 text-white' : 'bg-white text-slate-600 ring-1 ring-slate-200'
            }`}
          >
            {s.replace('_', ' ')}
          </button>
        ))}
      </div>

      {error && <ErrorBox message={error} />}

      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-slate-500">
            <tr>
              <th className="px-4 py-3 font-medium">Rider</th>
              <th className="px-4 py-3 font-medium">Type</th>
              <th className="px-4 py-3 font-medium">Fee</th>
              <th className="px-4 py-3 font-medium">Founding</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Action</th>
            </tr>
          </thead>
          <tbody>
            {riders.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-slate-400">
                  No riders with status “{filter.replace('_', ' ')}”.
                </td>
              </tr>
            )}
            {riders.map((r) => (
              <tr key={r.id} className="border-t border-slate-100">
                <td className="px-4 py-3">
                  <div className="font-medium">{r.profiles?.full_name ?? '—'}</div>
                  <div className="text-xs text-slate-400">{r.profiles?.phone ?? r.profiles?.email ?? ''}</div>
                </td>
                <td className="px-4 py-3 capitalize">{r.kind}</td>
                <td className="px-4 py-3">{r.registration_fee === 0 ? 'FREE' : `KES ${r.registration_fee}`}</td>
                <td className="px-4 py-3">{r.is_founding ? '🎖️ Yes' : 'No'}</td>
                <td className="px-4 py-3 capitalize">{r.status.replace('_', ' ')}</td>
                <td className="px-4 py-3">
                  {['submitted', 'under_review', 'approved'].includes(r.status) ? (
                    <div className="flex gap-2">
                      <button
                        disabled={busyId === r.id}
                        onClick={() => act(r.id, 'approve')}
                        className="rounded-md bg-emerald-600 px-3 py-1 text-xs font-medium text-white disabled:opacity-50"
                      >
                        Approve
                      </button>
                      <button
                        disabled={busyId === r.id}
                        onClick={() => act(r.id, 'reject')}
                        className="rounded-md bg-rose-600 px-3 py-1 text-xs font-medium text-white disabled:opacity-50"
                      >
                        Reject
                      </button>
                    </div>
                  ) : (
                    <span className="text-xs text-slate-400">—</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
