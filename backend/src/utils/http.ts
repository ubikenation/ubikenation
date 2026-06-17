import type { NextFunction, Request, Response } from 'express';

/** Domain error with an HTTP status — thrown by services, caught by error middleware. */
export class AppError extends Error {
  constructor(
    public status: number,
    message: string,
    public code?: string,
    public details?: unknown,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export const badRequest = (m: string, d?: unknown) => new AppError(400, m, 'bad_request', d);
export const unauthorized = (m = 'Unauthorized') => new AppError(401, m, 'unauthorized');
export const forbidden = (m = 'Forbidden') => new AppError(403, m, 'forbidden');
export const notFound = (m = 'Not found') => new AppError(404, m, 'not_found');
export const conflict = (m: string) => new AppError(409, m, 'conflict');

export function ok<T>(res: Response, data: T, status = 200) {
  return res.status(status).json({ success: true, data });
}

/** Wraps async route handlers so thrown errors hit the error middleware. */
export function handler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>,
) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}
