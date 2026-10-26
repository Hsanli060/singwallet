// lib/presentation/screens/drafts/widgets/smart_transaction_form.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../data/models/models.dart';

/// Interactive smart transaction input form for OCR confirmation.
///
/// Features:
/// 1. Prominent 36pt amount input with currency symbol and decimal -> cents conversion.
/// 2. Payment channel dropdown (WeChat, Alipay, Bank Card, Cash, etc.).
/// 3. Transaction type selector (Expense, Income, Transfer, Refund).
/// 4. Merchant name input field with clear button.
/// 5. Transaction date/time picker.
/// 6. Account and Project dropdown selectors with note text field.
class SmartTransactionForm extends StatelessWidget {
  final TextEditingController amountController;
  final TextEditingController merchantController;
  final TextEditingController noteController;
  final String selectedType;
  final ValueChanged<String> onTypeChanged;
  final String selectedChannel;
  final ValueChanged<String> onChannelChanged;
  final String? selectedAccountId;
  final ValueChanged<String?> onAccountChanged;
  final List<Account> accounts;
  final String? selectedProjectId;
  final ValueChanged<String?> onProjectChanged;
  final List<Project> projects;
  final DateTime selectedDateTime;
  final ValueChanged<DateTime> onDateTimeChanged;
  final String? amountErrorText;
  final String? merchantErrorText;

  const SmartTransactionForm({
    super.key,
    required this.amountController,
    required this.merchantController,
    required this.noteController,
    required this.selectedType,
    required this.onTypeChanged,
    required this.selectedChannel,
    required this.onChannelChanged,
    required this.selectedAccountId,
    required this.onAccountChanged,
    required this.accounts,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.projects,
    required this.selectedDateTime,
    required this.onDateTimeChanged,
    this.amountErrorText,
    this.merchantErrorText,
  });

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );

    final finalDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime?.hour ?? selectedDateTime.hour,
      pickedTime?.minute ?? selectedDateTime.minute,
    );

    onDateTimeChanged(finalDateTime);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Compute converted cents helper
    int? parsedCents;
    try {
      if (amountController.text.trim().isNotEmpty) {
        parsedCents = CurrencyUtils.parseToMinorUnits(amountController.text);
      }
    } catch (_) {}

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section 1: Transaction Type Selector
            Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'expense',
                    label: Text('支出'),
                    icon: Icon(Icons.arrow_outward, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'income',
                    label: Text('收入'),
                    icon: Icon(Icons.arrow_downward, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'transfer',
                    label: Text('转账'),
                    icon: Icon(Icons.swap_horiz, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'refund',
                    label: Text('退款'),
                    icon: Icon(Icons.undo, size: 16),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) {
                    onTypeChanged(set.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 20),

            // Section 2: Prominent 36pt Amount Input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: amountErrorText != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.outlineVariant.withAlpha(100),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '交易金额',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '¥',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('draft_amount_input'),
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              color: theme.colorScheme.outline.withAlpha(120),
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (parsedCents != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '存储精度: $parsedCents 分 (${CurrencyUtils.centsToYuanString(parsedCents)} 元)',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.primary.withAlpha(200),
                      ),
                    ),
                  ],
                  if (amountErrorText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      amountErrorText!,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Section 3: Merchant Name with Clear Button
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: merchantController,
              builder: (context, value, _) {
                return TextField(
                  key: const ValueKey('draft_merchant_input'),
                  controller: merchantController,
                  decoration: InputDecoration(
                    labelText: '商户 / 交易对手',
                    hintText: '例如: 星巴克、麦当劳、全家便利店',
                    prefixIcon: const Icon(Icons.storefront_outlined),
                    suffixIcon: value.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => merchantController.clear(),
                          )
                        : null,
                    errorText: merchantErrorText,
                    border: const OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Section 4: Payment Channel and Financial Account
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('draft_channel_dropdown'),
                    initialValue: selectedChannel,
                    borderRadius: BorderRadius.circular(16),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    decoration: const InputDecoration(
                      labelText: '支付渠道',
                      prefixIcon: Icon(Icons.payment_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'wechat',
                        child: Text('微信支付'),
                      ),
                      DropdownMenuItem(
                        value: 'alipay',
                        child: Text('支付宝'),
                      ),
                      DropdownMenuItem(
                        value: 'bank_card',
                        child: Text('银行卡'),
                      ),
                      DropdownMenuItem(
                        value: 'cash',
                        child: Text('现金'),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text('其他渠道'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        onChannelChanged(val);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('draft_account_dropdown'),
                    initialValue: accounts.any((a) => a.id == selectedAccountId)
                        ? selectedAccountId
                        : (accounts.isNotEmpty ? accounts.first.id : null),
                    borderRadius: BorderRadius.circular(16),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    decoration: const InputDecoration(
                      labelText: '结算账户',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                    ),
                    items: accounts
                        .map(
                          (acc) => DropdownMenuItem<String?>(
                            value: acc.id,
                            child: Text(
                              acc.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onAccountChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Section 5: Date/Time Picker
            InkWell(
              key: const ValueKey('draft_datetime_picker'),
              onTap: () => _pickDateTime(context),
              borderRadius: BorderRadius.circular(16),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '交易发生时间',
                  prefixIcon: Icon(Icons.event_outlined),
                  suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                ),
                child: Text(
                  _formatDateTime(selectedDateTime),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Section 6: Project and Notes
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('draft_project_dropdown'),
                    initialValue: selectedProjectId,
                    borderRadius: BorderRadius.circular(16),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    decoration: const InputDecoration(
                      labelText: '归属项目',
                      prefixIcon: Icon(Icons.folder_open_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('无项目标签'),
                      ),
                      ...projects.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: onProjectChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('draft_note_input'),
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: '备注说明',
                      hintText: '可选备注',
                      prefixIcon: Icon(Icons.edit_note_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
