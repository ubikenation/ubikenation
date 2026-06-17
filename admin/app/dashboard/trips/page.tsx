'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { ErrorBox } from '../page';

interface Trip {
  id: string;
  trip_type: string;
  vehicle_class: string;
  status: string;
  final_fare?: number;
  base_fare: number;
  created_at: string;
  profiles?: { full_name?: string };
}

const STATUS_COLORS: Record<string, string> = {
  completed: 'bg-emerald-100 text-emerald-700',
  in_progress: 'bg-sky-100 text-sky-700',
  searching: 'bg-amber-100 text-amber-700',
  cancelled: 'bg-rose-100 text-rose-700',
  pending_payment: 'bg-slate-100 text-slate-600',
};

export default function TripsPage() {
  const [trips, setTrips] = useState<Trip[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get('/api/admin/trips').then((d) => setTrips(d as Trip[])).catch((e) => setError(e.message));
  }, []);

  return (
    <div>
      <h1 className="mb-1 text-2xl font-bold">Trips</h1>
      <p className="mb-6 text-sm text-slate-500">Most recent trips & errands</p>

      {error && <ErrorBox message={error} />}

      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-slate-500">
            <tr>
              <th className="px-4 py-3 font-medium">Customer</th>
              <th className="px-4 py-3 font-medium">Service</th>
              <th className="px-4 py-3 font-medium">Fare</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">When</th>
            </tr>
          </thead>
          <tbody>
            {trips.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-slate-400">No trips yet.</td>
              </tr>
            )}
            {trips.map((t) => (
              <tr key={t.id} className="border-t border-slate-100">
                <td className="px-4 py-3 font-medium">{t.profiles?.full_name ?? '—'}</td>
                <td className="px-4 py-3 capitalize">{t.vehicle_class.replace('_', ' ')}</td>
                <td className="px-4 py-3">KES {t.final_fare ?? t.base_fare}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_COLORS[t.status] ?? 'bg-slate-100 text-slate-600'}`}>
                    {t.status.replace('_', ' ')}
                  </span>
                </td>
                <td className="px-4 py-3 text-slate-500">{new Date(t.created_at).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
