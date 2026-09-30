# TaskFlow

Production foundation for a verified micro-task platform.

Stack: Vercel, React + Vite, Supabase Auth/PostgreSQL/RLS, GitHub.

## Current access flow

- No phone OTP.
- User enters name + Indian mobile number.
- Supabase Anonymous Sign-In creates a temporary authenticated session.
- The application is stored as **pending**.
- Users see an Account Waiting / Pending Activation screen.
- An administrator manually approves or rejects every application.
- Only approved accounts can receive tasks or earn rewards.
- The browser never decides activation status or reward amounts.

Supabase documents anonymous sign-ins as authenticated users with an is_anonymous JWT claim. Because anonymous accounts cannot be recovered after sign-out, clearing browser data, or changing device, this flow is intentionally a pending-on-this-device workflow until a permanent authentication method is added later. CAPTCHA is recommended for anonymous sign-ins to reduce abuse.

## Admin approval

1. Enable **Anonymous Sign-Ins** in Supabase Authentication.
2. Create a separate permanent Supabase admin user using an appropriate permanent authentication method.
3. Copy that user's Auth UUID.
4. After running `supabase/schema.sql`, set the admin flag:

```sql
update public.profiles
set is_admin = true
where id = '<ADMIN_AUTH_USER_UUID>';
```

5. Open `/admin` in the deployed app and sign in with that admin account.
6. Approve or reject pending applications from the admin queue.

Admin approval functions are server-side PostgreSQL functions protected by an is_admin check. Never expose a Supabase secret/service-role key in the browser.

## Task system

Included:
- Server-side task assignment and answer validation
- Wallet ledger
- Row Level Security
- Automated-task-ready schema
- Four locked task categories: image, text, data, OCR
- YES/NO and A/B/C/D answer formats
- No hard-coded demo tasks or fake balances
- Task access blocked until manual activation
- Rewarded-ad unlocking blocked until a provider/format explicitly permits incentivized traffic

## Deployment

1. Create a Supabase project.
2. Run `supabase/schema.sql` in Supabase SQL Editor.
3. Enable **Anonymous Sign-Ins** in Authentication.
4. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` to Vercel.
5. Configure CAPTCHA/Turnstile and anonymous-sign-in abuse controls.
6. Create the permanent admin account and set `is_admin=true`.
7. Test application submission and `/admin` approval before enabling task access.
8. Add the automated licensed data-ingestion/task-generation worker.
9. Add an explicitly permitted incentivized/rewarded-ad integration.
10. Add withdrawals/KYC/payment provider after legal/compliance review.

## Important

Anonymous sign-in is not a substitute for phone verification. Without OTP, the submitted phone number is an application attribute and is **not verified ownership**. Manual approval is therefore an administrative activation process, not proof that the applicant controls the number.

Before public launch, add a permanent authentication/recovery method and appropriate anti-abuse controls if users need to return to their accounts across devices.

Never trust client-side reward amounts or task correctness.
