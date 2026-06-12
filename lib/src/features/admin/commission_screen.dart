import 'package:book_it/src/models/platform_models.dart';
import 'package:book_it/src/repositories/tenant_repository.dart';
import 'package:book_it/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CommissionScreen extends ConsumerStatefulWidget {
  const CommissionScreen({super.key});

  @override
  ConsumerState<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends ConsumerState<CommissionScreen> {
  final _rateController = TextEditingController();
  final _currencyController = TextEditingController(text: 'ZAR');
  final _windowController = TextEditingController(text: '24');
  bool _isLoading = false;
  String? _settingsId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings =
        await ref.read(tenantRepositoryProvider).getPlatformSettings();
    if (settings != null) {
      _settingsId = settings.id;
      _rateController.text = settings.commissionRate.toString();
      _currencyController.text = settings.currency;
      _windowController.text = settings.cancellationWindowHours.toString();
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    _currencyController.dispose();
    _windowController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final settings = PlatformSettings(
        id: _settingsId ?? '',
        commissionRate: double.tryParse(_rateController.text) ?? 10.0,
        currency: _currencyController.text.trim(),
        cancellationWindowHours: int.tryParse(_windowController.text) ?? 24,
        updatedAt: DateTime.now(),
      );
      final repo = ref.read(tenantRepositoryProvider);
      // Update the existing singleton row when we have one; only insert the
      // very first time. (A plain upsert with no id inserted a new row on
      // every save, which then broke the single-row read.)
      if (_settingsId != null) {
        await repo.updatePlatformSettings(settings);
      } else {
        await repo.upsertPlatformSettings(settings);
      }
      ref.invalidate(platformSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Commission & Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Commission is applied as a percentage on top of every booking. Tenants see the net amount, platform retains the commission.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Commission Rate', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _rateController,
              decoration: const InputDecoration(
                labelText: 'Rate (%)',
                suffixText: '%',
                hintText: 'e.g. 10',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 24),
            Text('Currency', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _currencyController,
              decoration: const InputDecoration(
                labelText: 'Currency Code',
                hintText: 'USD, EUR, GBP...',
              ),
            ),
            const SizedBox(height: 24),
            Text('Cancellation Policy', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _windowController,
              decoration: const InputDecoration(
                labelText: 'Free cancellation window',
                suffixText: 'hours',
                hintText: 'e.g. 24',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
