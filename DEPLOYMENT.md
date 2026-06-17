# U-Bike Deployment Guide

Three things get deployed:

| Piece | Host | Folder |
|---|---|---|
| Backend API | **Render** | `backend/` |
| Admin dashboard | **Vercel** | `admin/` |
| Landing website | **Vercel** (static) | `website/` |

> 🔐 **Before going public:** rotate every key you shared during development and put the new
> values into the host dashboards below — never back into the repo. The repo only contains
> client-public keys (Supabase anon, Paystack *public*, Maps) by design.

---

## 1) Backend → Render

1. Go to **render.com** → **New +** → **Blueprint**.
2. Connect GitHub and pick **`ubikenation/ubikenation`**. Render reads `render.yaml` and
   proposes the **ubike-backend** web service automatically.
3. Click **Apply**. The first deploy will pause for env vars.
4. Open the service → **Environment** → add these (the ones marked secret in `render.yaml`):

   | Key | Value |
   |---|---|
   | `SUPABASE_URL` | `https://eqlreobcizgtxviqegdh.supabase.co` |
   | `SUPABASE_ANON_KEY` | your anon key |
   | `SUPABASE_SERVICE_ROLE_KEY` | your **rotated** service-role key |
   | `PAYSTACK_SECRET_KEY` | your **rotated** Paystack secret |
   | `PAYSTACK_PUBLIC_KEY` | your Paystack public key |
   | `PAYSTACK_WEBHOOK_SECRET` | (set after step 6) |
   | `GOOGLE_MAPS_API_KEY`, `MAPBOX_ACCESS_TOKEN`, `ORS_API_KEY` | your keys |
   | `ZEGO_APP_ID`, `ZEGO_SERVER_SECRET`, `REDIS_URL` | your values |

5. **Manual Deploy → Deploy latest commit.** When it's live, note the URL, e.g.
   `https://ubike-backend.onrender.com`. Verify: open `…/health` → should return `{"status":"ok"}`.
6. **Paystack webhook:** in the Paystack dashboard → Settings → API Keys & Webhooks, set the
   webhook URL to `https://ubike-backend.onrender.com/api/payments/webhook`. Put the signing
   secret into Render as `PAYSTACK_WEBHOOK_SECRET` and redeploy.

> Render's free plan sleeps after inactivity (first request is slow). Upgrade to a paid
> instance before launch so payment webhooks aren't delayed.

---

## 2) Admin dashboard → Vercel

1. Go to **vercel.com** → **Add New… → Project** → import **`ubikenation/ubikenation`**.
2. **Root Directory:** set to **`admin`** (click *Edit* next to Root Directory).
   Framework auto-detects as **Next.js**.
3. **Environment Variables** (Project Settings → Environment Variables):

   | Key | Value |
   |---|---|
   | `NEXT_PUBLIC_API_BASE_URL` | `https://ubike-backend.onrender.com` (your Render URL) |
   | `NEXT_PUBLIC_SUPABASE_URL` | `https://eqlreobcizgtxviqegdh.supabase.co` |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | your anon key |

4. **Deploy.** Log in with your admin account (`profiles.role = 'admin'`).

---

## 3) Landing website → Vercel (static)

1. **Add New… → Project** → import the **same repo** again.
2. **Root Directory:** `website`. **Framework Preset:** **Other**. Leave build command empty,
   output directory `.` (it's a single static `index.html`).
3. **Deploy.** That's your public marketing site.

---

## 4) Mobile apps (Flutter) — build per app

The four Flutter apps point at the API via a compile-time define. Build each with your
production backend URL:

```bash
cd apps/customer        # then rider_bike / rider_car / rider_errands
flutter build apk --release \
  --dart-define=API_BASE_URL=https://ubike-backend.onrender.com \
  --dart-define=SUPABASE_URL=https://eqlreobcizgtxviqegdh.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Upload the resulting APKs / App Bundles to Google Play (and build iOS via `flutter build ipa`).

---

## Post-deploy checklist
- [ ] All keys rotated and set only in Render/Vercel dashboards
- [ ] `…/health` returns ok on Render
- [ ] Paystack webhook points at the Render URL and `PAYSTACK_WEBHOOK_SECRET` is set
- [ ] Admin dashboard loads and logs in
- [ ] Restrict the Google Maps API key by app/referrer in Google Cloud Console
- [ ] Switch Paystack to live only when you're ready to accept real payments
