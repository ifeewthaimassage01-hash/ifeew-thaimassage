# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

One product, two web apps, shared design system (`DESIGN.md`, `packages/ui`).

- **Customers** (`apps/customer`, mobile first): Thai locals and tourists who want a massage at a nearby branch. They browse services and branches, check free times, and book for up to several people without an account (guest only, no sign-up). They come back through a tracking link or their phone number to check status, pay the deposit by PromptPay, or cancel. They may log in with LINE to get a confirmation and an appointment reminder in LINE chat. Many arrive from the shop's LINE Official Account.
- **Front-desk staff** (`apps/staff`, on a shared branch tablet): pick their name and enter a 6-digit PIN. They take walk-ins and check in bookings, assign therapists to queues, take payment (cash, QR transfer with slip check, tips), record expenses, and close the day. They work fast, standing, with customers waiting.
- **Therapists**: press their own PIN to accept, start, and finish a queue, and see their own work, estimated commission, and guarantee top-ups.
- **Owner**: oversees all branches from desktop or phone. Sets up branches, services and prices, beds/equipment, staff, schedules, devices, booking and deposit rules, and LINE. Approves day closes, expense voids, refunds, commission payouts, and reviews finance reports.

## Product Purpose

Run a multi-branch Thai massage business end to end: online booking for customers, and the daily operation of each branch (queue, therapists, payment, expenses, day close) plus owner oversight of money and staff. Success means customers book without phoning, nobody double-books a bed or therapist, every baht is accounted for at day close, and therapists are paid correctly.

## Positioning

The shop competes on convenience (several branches, book online any time, no account needed, LINE reminders), atmosphere and cleanliness, value pricing, and skilled therapists. The product's job is to make the convenience real and let the calm, clean, good-value experience show through.

## Operating Context

- Customer site: Thai language today; phones first, often opened inside the LINE app (LIFF). Payment of deposits by PromptPay QR plus slip upload.
- Staff app: shared tablet at each branch's front desk, paired to that branch; staff sessions lock after idle time and log out at 03:00. The owner also uses it on desktop and phone. Mobile layout uses a bottom navigation bar.
- Notifications: Web Push to staff devices and LINE messages to a staff LINE group and to customers.
- Money and time are shown in Thai baht and Asia/Bangkok time.

## Capabilities and Constraints

- Customers are guest only: no registration, login, or member area (LINE login only links bookings to LINE for messages).
- Bookings: up to the configured number of people per booking, slot-based availability across beds and therapists, optional per-person deposit with a payment hold window, self-cancel until a cutoff before the appointment.
- Staff roles: owner versus branch staff; owner-only areas include finance, settings, and reports.
- Every financial change is auditable; destructive or money-moving actions require a reason.
- Backend is Supabase (Postgres RPCs, Edge Functions); apps are Nuxt on Vercel.
- Open decision: an English version of the customer site for tourists (customers include tourists, but the site is Thai only today).

## Brand Commitments

- Name: "Ifeew's Thaimassage" (wordmark), "Ifeew Massage" on the customer hero.
- Visual system is already committed in `DESIGN.md` (Warm Cream). Treat it as binding.

## Evidence on Hand

- Real services, prices, branches, and opening hours live in the database and are shown by the apps; do not hard-code or invent them.
- Customer hero photo: `apps/customer/public/images/hero-massage.png`. Service and branch photos come from Cloudinary via the staff app.
- No testimonials, reviews, ratings, press, customer counts, or awards exist. Do not fabricate them.
- Owner and staff manual: `docs/manual.md`. Deployment: `docs/deploy.md`.

## Product Principles

1. Booking must feel effortless: fewest steps, no account, clear price and time before committing.
2. At the front desk, speed and certainty beat decoration: the next action is always obvious, and mistakes can be undone with a reason.
3. Money is never ambiguous: totals, deposits, and who owes what are always visible and traceable.
4. Calm, clean, and warm, matching the shop's atmosphere, never loud or salesy.
5. Owner sees exceptions first: what needs approval or attention before routine numbers.

## Accessibility & Inclusion

- Text and status colors meet WCAG AA contrast; status is never shown by color alone (rule already in `DESIGN.md`).
- Staff screens must work on a front-desk tablet and a phone with touch targets large enough for quick use.
- Respect reduced motion.
