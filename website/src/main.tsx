import { StrictMode, useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Routes, Route, useNavigate } from 'react-router-dom';
import App from './App';
import ResetPassword from './pages/ResetPassword';
import { supabase } from './lib/supabase';
import './index.css';

/** Sends users who arrive via a password-reset email link to the reset page. */
function RecoveryRedirect() {
  const navigate = useNavigate();
  useEffect(() => {
    if (window.location.hash.includes('type=recovery')) {
      navigate('/reset-password', { replace: true });
    }
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY') navigate('/reset-password', { replace: true });
    });
    return () => sub.subscription.unsubscribe();
  }, [navigate]);
  return null;
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <RecoveryRedirect />
      <Routes>
        <Route path="/" element={<App />} />
        <Route path="/reset-password" element={<ResetPassword />} />
      </Routes>
    </BrowserRouter>
  </StrictMode>,
);
