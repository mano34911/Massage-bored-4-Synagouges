BETH TORAH MESSAGE BOARD SaaS - SETUP

1. Create a Supabase project.
2. Open SQL Editor and run: supabase-schema.sql
3. In Supabase > Project Settings > API, copy:
   - Project URL
   - Publishable/anon key
4. Paste them into supabase-config.js.
   NEVER put the service_role key in GitHub or browser code.
5. Upload all files in this folder to the SAME GitHub Pages folder.
6. Open register.html and register YOUR master account.
7. In Supabase SQL Editor run:
   update public.profiles set role='master' where email='YOUR_EMAIL_HERE';
8. Log in at login.html. You will be sent to master-admin.html.
9. New synagogue workflow:
   Register -> Pending -> Master Approves -> 7-day free trial -> Active or expired.
10. Each synagogue's public board URL is:
    index.html?s=THEIR-BOARD-ID

IMPORTANT
- The existing index look is preserved.
- The existing admin controls are preserved.
- Settings are saved per synagogue in synagogue_settings.settings.
- RLS isolates member data.
- The public board only loads accounts that are Active or inside a valid 7-day Trial.
- "Delete" in this first version is a SAFE SOFT DELETE: it changes status to deleted and immediately removes access.
- Payments are not charged yet. The master can already set each member's monthly price.
  Stripe can be connected in the next step.
