# BOS Supabase Foundation

This directory holds the source-controlled PostgreSQL schema, RLS policies,
and storage configuration for the future Supabase backend. The schema is
reproducible: a fresh project can be rebuilt from these migrations alone.

## Setup

1. Create a Supabase project (development project for testing — never test
   destructive RLS/migration changes against production).
2. Apply the migrations in order:

   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```

   or run each `migrations/*.sql` file in order through the SQL editor.

3. Run the Flutter app with the project's URL and **publishable (anon) key**:

   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=<publishable-key>
   ```

## Google Sign-In (native Android/iOS)

The app uses `google_sign_in` + `auth.signInWithIdToken` (the native flow,
not a browser redirect). Configuration is intentionally done in the
consoles, never hardcoded:

1. **Google Cloud Console** → APIs & Services → Credentials:
   - Create an OAuth **Web application** client. This Web client ID is what
     the app passes as `serverClientId` — note it down.
   - Create an OAuth **Android** client with the app's package id
     (`com.example.bos_application`) and the SHA-1 (and SHA-256) of every
     signing key you use (debug key for development, upload key for
     production). Get fingerprints with:
     `cd android && ./gradlew signingReport`.
   - For iOS also create an iOS client with the app bundle id.
2. **Supabase Dashboard** → Authentication → Providers → Google:
   - Enable the provider.
   - Under *Client IDs*, paste the Web client ID **and** the Android (and
     iOS) client IDs, comma-separated, Web first.
   - Client secret: the Web client's secret.
3. Run the app with the Web client ID supplied at build time:

   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=... \
     --dart-define=SUPABASE_ANON_KEY=... \
     --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com \
     --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>.apps.googleusercontent.com  # iOS only
   ```

4. New Google users get a `profiles` row automatically via the existing
   `handle_new_user` trigger (0002). Existing users keep their profile and
   business memberships — no duplicate accounts are created.

Without `GOOGLE_SERVER_CLIENT_ID` the app builds and runs fine, but the
Google button reports "Google sign-in isn't configured for this build."

## Password reset emails

`resetPasswordForEmail` uses the project's **Site URL / redirect allow
list** (Dashboard → Authentication → URL Configuration). Add the page that
hosts your set-new-password form there. The recovery link is delivered by
email and completed in the browser; the app only sends the request.


## What must never be committed

- The **service-role key** — never present in the Flutter app or this repo.
- The **publishable key** is safe to ship in the client (it's designed for
  client use); authorization is enforced by RLS, not by hiding the key.
  Prefer passing it via `--dart-define` / CI secrets rather than hardcoding.

## Migrations

| File | Purpose |
|------|---------|
| `0001_extensions_and_helpers.sql` | pgcrypto + shared `set_updated_at` trigger. |
| `0002_profiles.sql` | `public.profiles` (id == auth UUID) + `handle_new_user` trigger. |
| `0003_businesses_and_memberships.sql` | `businesses`, `business_memberships`, `create_business_with_owner` function. |
| `0004_core_business_tables.sql` | All business-owned tables with composite same-business FKs. |
| `0005_rls.sql` | RLS on every exposed table + membership helper functions. |
| `0006_storage.sql` | Private buckets (`business-assets`, `receipts`) + Storage RLS. |
| `0007`–`0010`, `0012`, `0013` | Change feed and RPCs, business invites, business profile columns, product categories. |
| `0011_complete_sync_change_feed.sql` | Superseded no-op (it could not be applied); see the alignment migration. |
| `20261003151947_user_device_registry.sql` | Account-owned installation registry, JWT-session correlation, device/session controls, and RLS device authorization. |
| `20261004010000_cloud_schema_alignment.sql` | Cloud tables/columns the app already uses (POS, recipes, shopping carts, price history, permission overrides, extra product/supply columns), their RLS, and the completed change feed. |
| `20261004040000_business_profile_sync.sql` | Business profile edits join the change feed (so every device with the same account gets the same profile) and existing rows are backfilled into it. |
| `20261026130006_sync_change_commit_order.sql` | Serializes change-feed sequence allocation per business to prevent cursor races. |
| `20261026131334_branch_scope_stock_transfers.sql` | Restricts transfer rows to users with access to an endpoint branch. |
| `20261026142900_server_verified_audit_trail.sql` | Records committed business-row changes through database triggers and prevents clients from inserting authoritative audit rows. |

Apply the commit-order migration before releasing the matching Flutter update.
That update rewinds each installation's feed cursor once so it can recover any
historical entries skipped by the previous cursor behavior.

The server-verified audit migration must be applied with the matching Flutter
update. Database-triggered events are the authoritative cloud audit trail.
Client-created audit notes continue to sync for visibility, but are marked
`client_reported` and cannot be represented as database-verified events. The
Audit Trail labels both sources. Run
`verification/server_verified_audit_check.sql` against a local or throwaway
database to verify row-change capture, redaction, and rejection of client
claims with a `database` source.

## Verification scripts

`verification/cloud_schema_alignment_check.sql` checks the alignment migration
(inserts every bootstrap table, change-feed entries, same-business integrity,
role limits, revoked devices, `anon`) and is run the same way.

`verification/device_registry_rls_check.sql` is a self-contained SQL check of
the device registry and its RLS boundary: unregistered/revoked sessions lose
business access, devices cannot revoke themselves, other accounts cannot see
or modify a device, reactivation needs a fresh session, and `anon` is denied.
Run it against a local or throwaway database that has every migration applied
(never production):

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/verification/device_registry_rls_check.sql
```

It runs inside a transaction that is rolled back and exits non-zero on any
failure. Both scripts passed against a from-scratch build (all migrations in
order) and against a copy of the hosted project's state.

## Authorization model

```
auth.uid()
  ↓
public.is_business_member(business_id)   (security-definer helper)
  ↓
business_memberships  (active membership, role)
  ↓
business-owned record  (explicit business_id on every tenant table)
```

- **Read** — any active member of the business.
- **Insert/Update** — any active member; composite FKs reject cross-business
  references at the database level.
- **Delete** — financial/ledger tables are owner/manager only; master data
  deletes are member-allowed for cleanup.
- **Business delete** — owner only.
- **Storage** — objects live under `businesses/{business_id}/...`; RLS reads
  the business id from the path and checks membership.

Device identity identifies a BOS installation only; it does not fingerprint
hardware. A user's device registry is separate from Supabase Auth sessions,
and business membership remains the authority for business access. Session
records correlate a server-derived JWT `session_id`; no access or refresh
tokens are stored in BOS tables. Revocation marks the device and its tracked
sessions, and the shared business-membership RLS boundary checks that state on
each request. A revoked JWT may remain cryptographically valid until expiry,
but cannot pass the BOS business-data RLS check.

The Flutter client must be updated alongside these migrations. Existing
offline outbox rows are local business data and are not removed by device
revocation. New outbox work is also attributed locally to the authenticated
account that created it. Rows created before that ownership fence, or by a
different account, are held from upload rather than silently reassigned. The
Security → My devices screen reports what is held and why. Older unattributed
changes in businesses the signed-in account belongs to can be adopted with an
explicit confirmation ("Upload older changes as me"); changes owned by another
account are never reassigned and upload only when that account signs in.
