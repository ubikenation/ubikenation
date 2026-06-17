import type { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../utils/http';
import { logger } from '../utils/logger';

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof ZodError) {
    return res.status(400).json({
      success: false,
      error: { code: 'validation_error', message: 'Invalid request', details: err.issues },
    });
  }
  if (err instanceof AppError) {
    return res.status(err.status).json({
      success: false,
      error: { code: err.code ?? 'error', message: err.message, details: err.details },
    });
  }
  logger.error({ err }, 'Unhandled error');
  return res.status(500).json({
    success: false,
    error: { code: 'internal_error', message: 'Something went wrong' },
  });
}

export function notFoundHandler(_req: Request, res: Response) {
  res.status(404).json({ success: false, error: { code: 'not_found', message: 'Route not found' } });
}
