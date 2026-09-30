# TaskFlow

TaskFlow is a task-based earning platform for short image, text, data and OCR verification work.

## User experience

The public website is intentionally focused on earning, not internal operations.

- Landing page: earning-focused messaging, task types and a simple how-it-works flow.
- User access has two clear choices: **Register** and **Login**.
- Registration uses name + Indian mobile number + password.
- Login uses the registered Indian mobile number + password.
- No OTP is used by the TaskFlow UI.
- Every new application remains **pending** until an administrator approves it.
- Approved users can receive tasks and earn rewards.
- The user dashboard shows only earning-relevant information: balance, available tasks and task completion.
- Internal task-engine, ingestion and admin workflow details are kept out of the user-facing experience.

Supabase supports password authentication using a phone number. For this no-OTP flow, enable Phone authentication and disable phone confirmation in the Supabase Auth settings; otherwise signup will return without an active session and the TaskFlow UI will stop the account flow.

## Admin approval

1. Enable **Phone** authentication in Supabase Authentication.
2. Disable **Confirm phone** because TaskFlow intentionally does not use OTP.
3. Keep user signup enabled.
4. Create a separate permanent Supabase admin user.
5. Copy that user's Auth UUID.
6. After running supabase/schema.sql, set the admin flag:

```sql
update public.profiles
set is_admin = true
where id = '<ADMIN_AUTH_USER_UUID>';
```

7. Open `/admin` in the deployed app and sign in with that administrator account.
8. Approve or reject pending applications from the admin queue.

Admin approval functions are server-side PostgreSQL functions protected by an `is_admin` check. Never expose a Supabase secret/service-role key in the browser.

## Task system

Included:

- Server-side task assignment and answer validation
- Wallet ledger
- Row Level Security
- Four locked task categories: image, text, data, OCR
- YES/NO and A/B/C/D answer formats
- Task access blocked until manual activation
- Reward calculation and wallet crediting on the server
- Source/license fields on tasks for the future licensed ingestion pipeline

## Deployment

1. Create a Supabase project.
2. Run `supabase/schema.sql` in Supabase SQL Editor.
3. Configure Supabase Phone Auth as described above.
4. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` to Vercel.
5. Configure appropriate CAPTCHA/rate limits and other abuse controls before public signup.
6. Create the permanent admin account and set `is_admin=true`.
7. Test Register → Pending → Admin approval → Login → Task → Reward.
8. Add the automated licensed data-ingestion/task-generation worker.
9. Add an explicitly permitted incentivized/rewarded-ad integration.
10. Add withdrawals/KYC/payment provider after legal/compliance review.

## Important

Phone + password provides persistent login, but disabling phone confirmation means the phone number is **not independently verified by SMS**. Manual approval is an administrative access decision, not proof that the applicant controls the number.

For production money movement, add appropriate anti-fraud controls, payout/KYC/tax handling, withdrawal rules, audit logging and legal/compliance review.

Never trust client-side reward amounts or task correctness.

## Supabase authentication reference

Supabase documents phone/password signup and login, including the requirement to enable phone authentication and the effect of phone confirmation settings.
