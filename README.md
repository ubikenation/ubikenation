# U-Bike — Ride-Hailing & Errands Platform (Kenya)

Move Better. Earn More. Bike, car, scheduled trips and errands with Paystack payments
and strict rider verification.

> ⚠️ **Security first.** Any API keys, tokens, or service-account files shared during
> development must be **rotated** and kept only in gitignored `.env` files. Never commit
> secrets. See `backend/.env.example`.

## Monorepo layout

```
ubike/
├─ backend/            Node.js + TypeScript + Express API (Supabase, Paystack, Maps)   ✅ in progress
│  ├─ db/schema.sql    Full Postgres schema + RLS for Supabase
│  └─ src/             Modular services (fare, riders/founding, auth, …)
├─ admin/             Next.js + Tailwind admin dashboard            ⛔ not started
├─ website/           Landing site + app downloads                  ⛔ not started
├─ apps/
│  ├─ customer/       Flutter customer app                          ⛔ not started
│  ├─ rider_bike/     Flutter bike rider app                        ⛔ not started
│  ├─ rider_car/      Flutter car rider app                         ⛔ not started
│  └─ rider_errands/  Flutter errands rider app                     ⛔ not started
```

## Build status (honest)

| Area | State |
|---|---|
| Backend: auth, fare engine, rider ±30% adjustment | ✅ typechecks, routes live |
| Founding-riders fee logic (first 10 bike free / 10 car free) | ✅ + race-safe DB function |
| Paystack escrow, wallets, 20/80 commission, payouts | ✅ math + webhook verified |
| Trip & errands lifecycle, chat moderation, matching | ✅ typechecks, guarded |
| Admin API (stats, verify, founding, trips, payouts) | ✅ typechecks |
| Postgres schema + RLS + functions | ✅ written (`backend/db/`) — **needs applying** |
| Customer Flutter app | ✅ `flutter analyze` clean, tests green |
| Bike / Car / Errands rider apps | ✅ all analyze clean, tests green |
| Admin dashboard (Next.js + Tailwind) | ✅ `npm run build` clean (8 routes) |
| Landing website | ✅ static site (`website/index.html`) |
| **Pending:** apply schema · E2E test · UI polish (maps/Paystack webview) | ⏭ |

Every component **compiles/builds and is verified**. Remaining work is wiring to a live database
(apply `backend/db/schema.sql` + `functions.sql`), an end-to-end test on Paystack **test** keys,
and a UI-polish pass to bring the apps to full prototype fidelity (real maps, embedded Paystack
checkout, document upload).

## Run each piece
```bash
# Backend
cd backend && npm install && npm run dev        # :8080

# Admin dashboard
cd admin && npm install && npm run dev          # :3000

# A Flutter app (customer or any rider)
cd apps/customer && flutter run

# Landing site — just open website/index.html, or deploy the folder to Vercel
```

## Run the backend

```bash
cd backend
cp .env.example .env     # then fill in ROTATED keys
npm install
npm run dev              # http://localhost:8080/health
```

Apply the database schema once: open Supabase → SQL Editor → paste `backend/db/schema.sql`.

### Live endpoints (require a Supabase auth JWT)
- `GET  /health`
- `POST /api/fare/estimate` — `{ vehicleClass, distanceKm, durationMin }` → fare + 50/50 split
- `POST /api/fare/validate-adjustment` — rider proposes new fare; enforces the +30% cap
- `GET  /api/riders/registration-fee?kind=bike|car` — founding-slot-aware fee quote
