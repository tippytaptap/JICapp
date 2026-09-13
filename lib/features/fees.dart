import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/fees.dart';
import '../widgets/common.dart';
import 'account.dart';
import 'workspace.dart';

/// Source filters are convenience only; Supabase checks the current user on every request.
class FeeLedgerPage extends StatelessWidget {
  final AppState state;
  final String? formId, studentId, courseId, feeId;
  final bool canManage;
  const FeeLedgerPage(
    this.state, {
    this.formId,
    this.studentId,
    this.courseId,
    this.feeId,
    this.canManage = false,
    super.key,
  });
  @override
  Widget build(BuildContext context) => AccountGate(
    state,
    child: feeId != null
        ? _FeeDetail(state, feeId!, canManage)
        : _FeeLedger(
            state,
            formId: formId,
            studentId: studentId,
            courseId: courseId,
            canManage: canManage,
          ),
  );
}

class _FeeLedger extends StatefulWidget {
  final AppState state;
  final String? formId, studentId, courseId;
  final bool canManage;
  const _FeeLedger(
    this.state, {
    this.formId,
    this.studentId,
    this.courseId,
    required this.canManage,
  });
  @override
  State<_FeeLedger> createState() => _FeeLedgerState();
}

class _FeeLedgerState extends State<_FeeLedger> {
  int page = 0;
  bool outstanding = false;
  late Future<Record> request = load();
  Future<Record> load() async {
    final result = await widget.state.client!
        .rpc(
          'list_fee_requests',
          params: {
            'p_form_id': widget.formId,
            'p_student_id': widget.studentId,
            'p_course_id': widget.courseId,
            'p_outstanding_only': outstanding,
            'p_offset': page * 25,
            'p_limit': 25,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (result is! Map) throw const FormatException('Invalid fee response');
    return Record.from(result);
  }

  void reload() => setState(() => request = load());
  Future<void> create() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AccountGate(
          widget.state,
          child: _FeeEditor(
            widget.state,
            source: {
              'p_form_id': widget.formId,
              'p_student_id': widget.studentId,
              'p_course_id': widget.courseId,
            },
          ),
        ),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Fees & payments',
    actions: [
      IconButton(
        tooltip: 'Refresh fees',
        onPressed: reload,
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.canManage
                    ? 'Track requested fees and confirmed receipts.'
                    : 'View your requested fees, remaining balance and recorded receipts.',
              ),
              if (widget.canManage &&
                  (widget.formId != null ||
                      (widget.studentId != null && widget.courseId != null)))
                FilledButton.icon(
                  onPressed: create,
                  icon: const Icon(Icons.add),
                  label: const Text('Request a fee'),
                ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Outstanding only'),
          value: outstanding,
          onChanged: (value) {
            outstanding = value;
            page = 0;
            reload();
          },
        ),
        Expanded(
          child: FutureBuilder<Record>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: reload,
                    child: const Text('Could not load fees. Retry'),
                  ),
                );
              }
              final data = snapshot.data ?? {}, rows = records(data['rows']);
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('${data['total'] ?? rows.length} fee requests'),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('There are no fee requests here.'),
                    ),
                  for (final fee in rows)
                    Card(
                      child: ListTile(
                        title: Text('${fee['title']}'),
                        subtitle: Text(
                          '${formatFeeAmount((fee['outstanding_minor'] as num?)?.toInt() ?? 0, '${fee['currency']}')} remaining'
                          ' · ${feeStatus(fee)}${fee['due_at'] == null ? '' : '\nDue ${formatWorkspaceDate(fee['due_at'])}'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AccountGate(
                                widget.state,
                                child: _FeeDetail(
                                  widget.state,
                                  '${fee['id']}',
                                  widget.canManage,
                                ),
                              ),
                            ),
                          );
                          if (mounted) reload();
                        },
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: page == 0
                            ? null
                            : () {
                                page--;
                                reload();
                              },
                        child: const Text('Previous'),
                      ),
                      Text('Page ${page + 1}'),
                      TextButton(
                        onPressed: rows.length < 25
                            ? null
                            : () {
                                page++;
                                reload();
                              },
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

String feeStatus(Record fee) =>
    const {
      'unpaid': 'Unpaid',
      'partial': 'Part paid',
      'paid': 'Paid',
      'void': 'Voided',
    }[fee['status']] ??
    'Requested';

class _FeeDetail extends StatefulWidget {
  final AppState state;
  final String id;
  final bool canManage;
  const _FeeDetail(this.state, this.id, this.canManage);
  @override
  State<_FeeDetail> createState() => _FeeDetailState();
}

class _FeeDetailState extends State<_FeeDetail> {
  int page = 0;
  bool busy = false;
  late Future<Record> request = load();
  Future<Record> load() async {
    final values = await Future.wait<dynamic>([
      widget.state.client!.rpc(
        'list_fee_requests',
        params: {'p_fee_id': widget.id, 'p_limit': 1},
      ).then<dynamic>((value) => value),
      widget.state.client!
          .from('fee_receipts')
          .select(
            'id,fee_id,amount_minor,method,reference,note,recorded_by,created_at,reversal_of',
          )
          .eq('fee_id', widget.id)
          .order('created_at', ascending: false)
          .range(page * 25, page * 25 + 24).then<dynamic>((value) => value),
    ]).timeout(const Duration(seconds: 20));
    final rows = values[0] is Map
        ? records((values[0] as Map)['rows'])
        : <Record>[];
    if (rows.length != 1) throw StateError('This fee is unavailable');
    return {'fee': rows.single, 'receipts': records(values[1])};
  }

  void reload() => setState(() => request = load());
  Future<void> adjust(String rpc, String idKey, String id, String title) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title),
    );
    if (reason == null || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.state.client!
          .rpc(rpc, params: {idKey: id, 'p_reason': reason})
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        notice(context, 'The ledger has been updated.');
        reload();
      }
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Could not confirm this change. Refresh before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Fee details',
    actions: [
      IconButton(
        tooltip: 'Refresh fee',
        onPressed: busy ? null : reload,
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: FutureBuilder<Record>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('This fee could not be opened. Retry'),
            ),
          );
        }
        final fee = Record.from(snapshot.data!['fee']),
            receipts = records(snapshot.data!['receipts']);
        final currency = '${fee['currency']}',
            outstanding = (fee['outstanding_minor'] as num).toInt();
        final paid = (fee['paid_minor'] as num).toInt(),
            voided = fee['voided_at'] != null;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${fee['title']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Requested · ${formatFeeAmount((fee['amount_minor'] as num).toInt(), currency)}',
                    ),
                    Text('Recorded paid · ${formatFeeAmount(paid, currency)}'),
                    Text(
                      'Remaining · ${formatFeeAmount(outstanding, currency)}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(feeStatus(fee)),
                    if (fee['due_at'] != null)
                      Text('Due ${formatWorkspaceDate(fee['due_at'])}'),
                    if (voided) Text('Voided: ${fee['void_reason'] ?? ''}'),
                  ],
                ),
              ),
            ),
            if (widget.canManage && !voided) ...[
              if (outstanding > 0)
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AccountGate(
                                widget.state,
                                child: _FeeEditor(widget.state, fee: fee),
                              ),
                            ),
                          );
                          if (mounted) reload();
                        },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Record a manual payment'),
                ),
              if (paid == 0)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => adjust(
                          'void_fee_request',
                          'p_fee_id',
                          widget.id,
                          'Void this fee request?',
                        ),
                  child: const Text('Void fee request'),
                ),
              const Text(
                'Manual confirmation records a staff statement. It does not collect money or verify a bank transfer.',
              ),
            ],
            const SectionTitle('Receipt history'),
            if (receipts.isEmpty) const Text('No receipts have been recorded.'),
            for (final receipt in receipts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        formatFeeAmount(
                          (receipt['amount_minor'] as num).toInt(),
                          currency,
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        receipt['method'] == 'manual'
                            ? 'Manually confirmed by staff'
                            : receipt['method'] == 'stripe'
                            ? 'Verified Stripe payment'
                            : 'Ledger reversal',
                      ),
                      Text(formatWorkspaceDate(receipt['created_at'])),
                      if ('${receipt['reference'] ?? ''}'.isNotEmpty)
                        Text('Reference: ${receipt['reference']}'),
                      if ('${receipt['note'] ?? ''}'.isNotEmpty)
                        Text('${receipt['note']}'),
                      if (widget.canManage &&
                          receipt['method'] == 'manual' &&
                          (receipt['amount_minor'] as num) > 0)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => adjust(
                                  'reverse_fee_receipt',
                                  'p_receipt_id',
                                  '${receipt['id']}',
                                  'Reverse this manual receipt?',
                                ),
                          child: const Text('Reverse ledger entry'),
                        ),
                    ],
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: busy || page == 0
                      ? null
                      : () {
                          page--;
                          reload();
                        },
                  child: const Text('Previous'),
                ),
                Text('Page ${page + 1}'),
                TextButton(
                  onPressed: busy || receipts.length < 25
                      ? null
                      : () {
                          page++;
                          reload();
                        },
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  const _ReasonDialog(this.title);
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final form = GlobalKey<FormState>(), reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This changes the ledger only. It does not refund or move money.',
          ),
          TextFormField(
            controller: reason,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Reason'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a reason' : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: const Text('Confirm change'),
      ),
    ],
  );
}

class _FeeEditor extends StatefulWidget {
  final AppState state;
  final Record? source, fee;
  const _FeeEditor(this.state, {this.source, this.fee});
  @override
  State<_FeeEditor> createState() => _FeeEditorState();
}

class _FeeEditorState extends State<_FeeEditor> {
  static const storage = FlutterSecureStorage();
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      amount = TextEditingController(),
      reference = TextEditingController(),
      note = TextEditingController();
  DateTime? due;
  Record? attempt;
  bool ready = false, busy = false;
  String? error;
  bool get receipt => widget.fee != null;
  String get currency => receipt ? '${widget.fee!['currency']}' : 'GBP';
  String get storageKey =>
      'fees.${widget.state.userId}.${receipt ? 'receipt.${widget.fee!['id']}' : 'request.${widget.source?['p_form_id'] ?? '${widget.source?['p_course_id']}.${widget.source?['p_student_id']}'}'}';
  @override
  void initState() {
    super.initState();
    restore();
  }

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    reference.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> restore() async {
    try {
      final saved = await storage.read(key: storageKey);
      if (saved != null) {
        final value = jsonDecode(saved);
        if (value is! Map ||
            value['params'] is! Map ||
            value['params']['p_idempotency_key'] is! String) {
          throw const FormatException('Invalid pending request');
        }
        attempt = Record.from(value['params']);
        title.text = '${attempt!['p_title'] ?? ''}';
        amount.text = feeInputAmount(
          (attempt!['p_amount_minor'] as num).toInt(),
          currency,
        );
        reference.text = '${attempt!['p_reference'] ?? ''}';
        note.text = '${attempt!['p_note'] ?? ''}';
        due = DateTime.tryParse('${attempt!['p_due_at']}')?.toLocal();
      } else if (receipt) {
        amount.text = feeInputAmount(
          (widget.fee!['outstanding_minor'] as num).toInt(),
          currency,
        );
      }
      ready = true;
    } catch (_) {
      error =
          'A pending entry could not be opened. Return to the ledger and contact an administrator.';
    }
    if (mounted) setState(() {});
  }

  Future<void> submit() async {
    if (busy || !ready || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      attempt ??= {
        if (receipt) 'p_fee_id': widget.fee!['id'] else ...widget.source!,
        if (!receipt) 'p_title': title.text.trim(),
        'p_amount_minor': parseFeeMinor(
          amount.text,
          decimal: hasDecimalFeeCurrency(currency),
        ),
        if (!receipt) 'p_currency': 'GBP',
        if (!receipt) 'p_due_at': due?.toUtc().toIso8601String(),
        if (receipt) 'p_reference': reference.text.trim(),
        if (receipt) 'p_note': note.text.trim(),
        'p_idempotency_key': feeAttemptId(),
      };
      // Retain exact payload/key across timeouts, navigation and app restarts.
      // A retry either returns the previous success or creates this one entry.
      await storage.write(
        key: storageKey,
        value: jsonEncode({'params': attempt}),
      );
      await widget.state.client!
          .rpc(
            receipt ? 'confirm_fee_payment' : 'create_fee_request',
            params: attempt,
          )
          .timeout(const Duration(seconds: 25));
      await storage.delete(key: storageKey);
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (const {
        '22023',
        '23514',
        '42501',
        'P0001',
        '23503',
      }.contains(e.code)) {
        try {
          await storage.delete(key: storageKey);
          attempt = null;
          error = 'This entry was not accepted. Check the amount, details and your access, then try again.';
        } catch (_) {
          error = 'The entry was not accepted, but the saved draft could not be updated. Check device storage before retrying.';
        }
      } else {
        error =
            'The result could not be confirmed. Retry this same entry safely.';
      }
    } catch (_) {
      error =
          'The result could not be confirmed. Retry this same entry safely.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: receipt ? 'Record payment' : 'Request a fee',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!ready && error == null) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (ready)
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  receipt
                      ? 'Record a payment you have confirmed manually. No money is collected here.'
                      : 'Create a fee request in GBP for this form response or enrolled student.',
                ),
                if (attempt != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'An entry is awaiting confirmation. Retry the same details to avoid creating a duplicate.',
                    ),
                  ),
                if (!receipt)
                  TextFormField(
                    controller: title,
                    readOnly: busy || attempt != null,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: 'What is this fee for?',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter a fee title'
                        : null,
                  ),
                TextFormField(
                  controller: amount,
                  readOnly: busy || attempt != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: hasDecimalFeeCurrency(currency)
                        ? 'Amount ($currency)'
                        : 'Amount in minor units ($currency)',
                  ),
                  validator: (v) {
                    final minor = parseFeeMinor(
                      v ?? '',
                      decimal: hasDecimalFeeCurrency(currency),
                    );
                    if (minor == null) {
                      return 'Enter a positive amount${hasDecimalFeeCurrency(currency) ? ' with up to two decimal places' : ' in whole minor units'}';
                    }
                    if (receipt &&
                        attempt == null &&
                        minor > (widget.fee!['outstanding_minor'] as num)) {
                      return 'The amount exceeds the remaining balance';
                    }
                    return null;
                  },
                ),
                if (receipt) ...[
                  TextFormField(
                    controller: reference,
                    readOnly: busy || attempt != null,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: 'Payment reference',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter a reference'
                        : null,
                  ),
                  TextFormField(
                    controller: note,
                    readOnly: busy || attempt != null,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                ] else ...[
                  TextButton.icon(
                    onPressed: busy || attempt != null
                        ? null
                        : () async {
                            final value = await pickWorkspaceDate(
                              context,
                              initial: due,
                            );
                            if (value != null && mounted) {
                              setState(() => due = value);
                            }
                          },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      due == null
                          ? 'Add a due date (optional)'
                          : formatWorkspaceDate(due!.toIso8601String()),
                    ),
                  ),
                  if (due != null)
                    TextButton(
                      onPressed: busy || attempt != null
                          ? null
                          : () => setState(() => due = null),
                      child: const Text('Remove due date'),
                    ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? 'Saving…'
                        : attempt != null
                        ? 'Retry same entry'
                        : receipt
                        ? 'Confirm manual payment'
                        : 'Create fee request',
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
