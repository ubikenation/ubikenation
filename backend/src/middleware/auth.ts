import type { NextFunction, Request, Response } from 'express';
import { supabaseAdmin } from '../config/supabase';
import { forbidden, unauthorized } from '../utils/http';

export interface AuthUser {
  id: string;
  email?: string;
  role: string;
  token: string;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

/** Verifies the Supabase JWT and loads the caller's role from `profiles`. */
export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  try {
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) throw unauthorized('Missing bearer token');

    const { data, error } = await supabaseAdmin.auth.getUser(token);
    if (error || !data.user) throw unauthorized('Invalid or expired token');

    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('role')
      .eq('id', data.user.id)
      .single();

    req.user = {
      id: data.user.id,
      email: data.user.email,
      role: profile?.role ?? 'customer',
      token,
    };
    next();
  } catch (e) {
    next(e);
  }
}

/** Restricts a route to one or more roles. Use after requireAuth. */
export function requireRole(...roles: string[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) return next(unauthorized());
    if (!roles.includes(req.user.role)) return next(forbidden('Insufficient role'));
    next();
  };
}
