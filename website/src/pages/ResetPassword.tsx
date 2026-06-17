import { useEffect, useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import { supabase } from '../lib/supabase';

/**
 * Handles the Supabase password-reset link. When the user clicks the email
 * link they arrive here with a recovery token; supabase-js exchanges it into a
 * session, then this form lets them set a new password.
 */
export default function ResetPassword() {
  const [ready, setReady] = useState(false);
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    // A valid recovery session must exist for the form to work.
    supabase.auth.getSession().then(({ data }) => setReady(!!data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY' || session) setReady(true);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (password.length < 6) return setError('Password must be at least 6 characters.');
    if (password !== confirm) return setError('Passwords do not match.');
    setBusy(true);
    const { error } = await supabase.auth.updateUser({ password });
    setBusy(false);
    if (error) return setError(error.message);
    setDone(true);
    await supabase.auth.signOut();
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-black px-4 font-sans">
      <div className="w-full max-w-sm rounded-3xl bg-white p-8">
        <img src="/logo.png" alt="U-Bike" className="mx-auto mb-4 h-10 w-auto" />
        {done ? (
          <div className="text-center">
            <h1 className="text-xl font-bold text-slate-900">Password updated 🎉</h1>
            <p className="mt-2 text-sm text-slate-500">
              You can now open the U-Bike app and log in with your new password.
            </p>
          </div>
        ) : !ready ? (
          <div className="text-center">
            <h1 className="text-lg font-semibold text-slate-800">Reset link</h1>
            <p className="mt-2 text-sm text-slate-500">
              Open this page from the password-reset link in your email. If you got here directly,
              request a new reset link from the app.
            </p>
          </div>
        ) : (
          <form onSubmit={submit}>
            <h1 className="text-xl font-bold text-slate-900">Set a new password</h1>
            <p className="mt-1 text-sm text-slate-500">Choose a strong password you’ll remember.</p>
            <div className="relative mt-5">
              <input
                type={show ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="New password"
                className="w-full rounded-lg border border-slate-200 px-3 py-2.5 pr-10 outline-none focus:border-sky-500"
              />
              <button
                type="button"
                onClick={() => setShow((s) => !s)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400"
                aria-label="Toggle password"
              >
                {show ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
              </button>
            </div>
            <input
              type={show ? 'text' : 'password'}
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              placeholder="Confirm password"
              className="mt-3 w-full rounded-lg border border-slate-200 px-3 py-2.5 outline-none focus:border-sky-500"
            />
            {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
            <button
              type="submit"
              disabled={busy}
              className="mt-5 w-full rounded-lg bg-sky-600 py-2.5 font-medium text-white transition hover:bg-sky-700 disabled:opacity-60"
            >
              {busy ? 'Updating…' : 'Update password'}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
