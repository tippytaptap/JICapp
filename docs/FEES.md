# Native fee ledger

`FeeLedgerPage(state, formId: id, canManage: true)` opens staff charges for a form response. `studentId` with optional `courseId` opens a student's learning fees. `feeId` opens one notification-linked fee; `canManage` defaults to false.

Every route has its own account gate. Supabase RLS and fee RPC permission checks remain authoritative; hiding staff buttons is not the access control.

Implemented:

- Paginated charge lists, outstanding-only filtering, amount/status/due date and receipt history.
- Staff fee creation in GBP with an optional due date.
- Manual receipt confirmation with exact integer pence, required reference and optional note; it is labelled as a staff statement, not provider verification.
- Manual-entry reversal and voiding an unpaid/net-zero fee, with reasons. These actions adjust the ledger; they do not refund money or collect a payment.
- Verified Stripe receipts are distinguished from manual entries. No card entry or payment-intent creation is implemented in this app ledger.
- Receipt and creation requests persist the exact payload and UUID idempotency key in device secure storage before contacting Supabase. Uncertain outcomes retain the same payload/key across retries, closing the screen and app restarts. A pending request is retried unchanged. Server validation rejection allows correction after the failed draft is cleared.
- Amount parsing uses integer arithmetic. Known two-decimal currencies display a conventional amount; unknown currencies display explicit minor units rather than assuming a precision. List summaries do not add different currencies together.

Shared backend contract: website `docs/fees-api.md`. Required functions are `create_fee_request`, `list_fee_requests` (including optional `p_fee_id`), `confirm_fee_payment`, `reverse_fee_receipt`, and `void_fee_request`; creation and confirmation require `p_idempotency_key`.

Tests: `flutter test test/fees_test.dart` verifies exact pence parsing, range/precision rejection, currency formatting and UUID shape/uniqueness. Backend tests independently cover authorization, immutable receipts, concurrency/idempotency and reversals. Staging migration and authenticated device checks remain required before use with real accounts.
