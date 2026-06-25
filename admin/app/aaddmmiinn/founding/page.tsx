'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { DeleteButton, ErrorBox } from '../page';

interface Founder {
  id: string;
  kind: string;
  status: string;
  created_at: string;
  approved_at?: string;
  profiles?: { full_name?: string };
}

interface Program {
  enabled: boolean;
  bikeSlots: number;
  carSlots: number;
  bikeUsed: number;
  carUsed: number;
  bikeRemaining: number;
  carRemaining: number;
  founders: Founder[];
}

export default function FoundingPage() {
  const [program, setProgram] = useState<Program | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    try {
      setProgram(await api.get('/api/admin/founding'));
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function toggle() {
    if (!program) return;
    setBusy(true);
    try {
      setProgram(await api.patch('/api/admin/founding', { enabled: !program.enabled }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <h1 className="mb-1 text-2xl font-bold">Founding Riders Program</h1>
      <p className="mb-6 text-sm text-slate-500">First 10 bike & 10 car riders register free</p>

      {error && <ErrorBox message={error} />}

      {program && (
        <>
          <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
            <SlotCard title="Bike Slots" remaining={program.bikeRemaining} used={program.bikeUsed} total={program.bikeSlots} text="text-emerald-600" bar="bg-emerald-500" />
            <SlotCard title="Car Slots" remaining={program.carRemaining} used={program.carUsed} total={program.carSlots} text="text-sky-600" bar="bg-sky-500" />
          </div>

          <div className="mb-8 flex items-center gap-3 rounded-xl border border-slate-200 bg-white p-4">
            <span className={`h-2.5 w-2.5 rounded-full ${program.enabled ? 'bg-emerald-500' : 'bg-slate-300'}`} />
            <span className="text-sm font-medium">Promotion is {program.enabled ? 'enabled' : 'disabled'}</span>
            <button
              onClick={toggle}
              disabled={busy}
              className="ml-auto rounded-lg bg-slate-800 px-4 py-1.5 text-sm font-medium text-white disabled:opacity-50"
            >
              {program.enabled ? 'Disable' : 'Enable'}
            </button>
          </div>

          <h2 className="mb-3 text-lg font-semibold">Founding Riders ({program.founders.length})</h2>
          <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left text-slate-500">
                <tr>
                  <th className="px-4 py-3 font-medium">Name</th>
                  <th className="px-4 py-3 font-medium">Type</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Registered</th>
                  <th className="px-4 py-3 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {program.founders.length === 0 && (
                  <tr>
                    <td colSpan={5} className="px-4 py-8 text-center text-slate-400">No founding riders yet.</td>
                  </tr>
                )}
                {program.founders.map((f) => (
                  <tr key={f.id} className="border-t border-slate-100">
                    <td className="px-4 py-3 font-medium">{f.profiles?.full_name ?? '—'}</td>
                    <td className="px-4 py-3 capitalize">{f.kind}</td>
                    <td className="px-4 py-3 capitalize">{f.status.replace('_', ' ')}</td>
                    <td className="px-4 py-3 text-slate-500">{new Date(f.created_at).toLocaleDateString()}</td>
                    <td className="px-4 py-3">
                      <DeleteButton onDelete={async () => { await api.del(`/api/admin/riders/${f.id}`); load(); }} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}

function SlotCard({ title, remaining, used, total, text, bar }: { title: string; remaining: number; used: number; total: number; text: string; bar: string }) {
  const pct = total > 0 ? (used / total) * 100 : 0;
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-6">
      <div className="flex items-baseline justify-between">
        <span className="text-sm text-slate-500">{title}</span>
        <span className={`text-2xl font-bold ${text}`}>{remaining} free left</span>
      </div>
      <div className="mt-3 h-2 w-full overflow-hidden rounded-full bg-slate-100">
        <div className={`h-full ${bar}`} style={{ width: `${pct}%` }} />
      </div>
      <div className="mt-2 text-xs text-slate-400">{used} of {total} slots used</div>
    </div>
  );
}
