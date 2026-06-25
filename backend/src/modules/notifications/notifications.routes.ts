import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import { registerDevice, unregisterDevice } from './notification.service';

export const notificationsRouter = Router();

// POST /api/devices/register — app stores its FCM token for push.
notificationsRouter.post('/register', requireAuth, handler(async (req, res) => {
  const { token, platform } = z
    .object({ token: z.string().min(10), platform: z.string().optional() })
    .parse(req.body);
  ok(res, await registerDevice(req.user!.id, token, platform));
}));

// POST /api/devices/unregister — drop a token (e.g. on logout).
notificationsRouter.post('/unregister', requireAuth, handler(async (req, res) => {
  const { token } = z.object({ token: z.string().min(10) }).parse(req.body);
  ok(res, await unregisterDevice(req.user!.id, token));
}));
