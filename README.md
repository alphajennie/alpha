# TaskFlow

Production foundation for a verified micro-task platform.

Stack: Vercel/Netlify, React + Vite, Supabase Auth/PostgreSQL/RLS, GitHub.

Included:
- Real Supabase phone OTP authentication
- Server-side task assignment and answer validation
- Wallet ledger
- Row Level Security
- Automated-task-ready schema
- No hard-coded demo tasks or fake balances
- Rewarded-ad unlocking blocked until a provider/format explicitly permits incentivized traffic

Important: hosted Supabase phone OTP currently documents a minimum of 6 digits, so the production UI uses 6 digits.

Deployment:
1. Create a Supabase project.
2. Run supabase/schema.sql in Supabase SQL Editor.
3. Enable Phone authentication and configure an SMS provider.
4. Copy project URL and publishable key.
5. Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to Vercel.
6. Configure Supabase Site URL and redirect settings.
7. Configure CAPTCHA and OTP rate limits.
8. Add the automated licensed data-ingestion/task-generation worker.
9. Add an explicitly permitted incentivized/rewarded-ad integration.
10. Add withdrawals/KYC/payment provider after legal/compliance review.

Never put a Supabase service-role key in the frontend. Never trust client-side reward amounts or task correctness.