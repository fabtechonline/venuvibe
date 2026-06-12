import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venue_vibe/src/models/email_settings.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';

/// Tenant-owned SMTP configuration: booking notifications, status changes
/// and receipts are emailed to customers from the venue's own address.
class EmailSettingsScreen extends ConsumerStatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  ConsumerState<EmailSettingsScreen> createState() =>
      _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends ConsumerState<EmailSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '587');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _fromEmailCtrl = TextEditingController();
  final _fromNameCtrl = TextEditingController();
  bool _enabled = false;
  bool _useTls = false;
  bool _notifyBookings = true;
  bool _notifyStatus = true;
  bool _sendReceipts = true;
  bool _obscurePassword = true;
  bool _loaded = false;
  bool _saving = false;
  bool _testing = false;
  String? _tenantId;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _fromEmailCtrl.dispose();
    _fromNameCtrl.dispose();
    super.dispose();
  }

  TenantEmailSettings _collect() => TenantEmailSettings(
        tenantId: _tenantId!,
        enabled: _enabled,
        smtpHost: _hostCtrl.text.trim(),
        smtpPort: int.tryParse(_portCtrl.text.trim()) ?? 587,
        smtpUsername: _userCtrl.text.trim(),
        smtpPassword: _passCtrl.text,
        useTls: _useTls,
        fromEmail: _fromEmailCtrl.text.trim(),
        fromName: _fromNameCtrl.text.trim(),
        notifyBookings: _notifyBookings,
        notifyStatus: _notifyStatus,
        sendReceipts: _sendReceipts,
      );

  Future<bool> _save({bool quiet = false}) async {
    if (!_formKey.currentState!.validate() || _tenantId == null) return false;
    setState(() => _saving = true);
    try {
      await ref.read(tenantRepositoryProvider).upsertEmailSettings(_collect());
      ref.invalidate(tenantEmailSettingsProvider);
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email settings saved')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTest() async {
    // Persist first so the function tests exactly what is stored.
    if (!await _save(quiet: true)) return;
    setState(() => _testing = true);
    try {
      final sentTo =
          await ref.read(tenantRepositoryProvider).sendTestEmail(_tenantId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test email sent to $sentTo')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(currentTenantProvider);
    final settingsAsync = ref.watch(tenantEmailSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Email Settings')),
      body: tenantAsync.when(
        data: (tenant) {
          if (tenant == null) {
            return const Center(child: Text('No venue linked to your account'));
          }
          _tenantId = tenant.id;
          final settings = settingsAsync.valueOrNull;
          if (!_loaded && !settingsAsync.isLoading) {
            _loaded = true;
            if (settings != null) {
              _enabled = settings.enabled;
              _hostCtrl.text = settings.smtpHost;
              _portCtrl.text = settings.smtpPort.toString();
              _userCtrl.text = settings.smtpUsername;
              _passCtrl.text = settings.smtpPassword;
              _useTls = settings.useTls;
              _fromEmailCtrl.text = settings.fromEmail;
              _fromNameCtrl.text = settings.fromName;
              _notifyBookings = settings.notifyBookings;
              _notifyStatus = settings.notifyStatus;
              _sendReceipts = settings.sendReceipts;
            } else {
              _fromNameCtrl.text = tenant.name;
            }
          }
          if (settingsAsync.isLoading && !_loaded) {
            return const Center(child: CircularProgressIndicator());
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Send booking emails to your customers from your own '
                      'email address. Works with any SMTP provider '
                      '(e.g. Gmail app passwords, Outlook, your hosting).',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable email notifications'),
                      subtitle: const Text(
                        'Nothing is sent until this is on and a test passes',
                      ),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'SMTP server',
                        hintText: 'e.g. smtp.gmail.com',
                      ),
                      validator: (v) =>
                          _enabled && (v == null || v.trim().isEmpty)
                              ? 'Required when enabled'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _portCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              hintText: '587 or 465',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final p = int.tryParse(v?.trim() ?? '');
                              return p == null || p < 1 || p > 65535
                                  ? '1–65535'
                                  : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Implicit TLS'),
                            subtitle: const Text('On for port 465'),
                            value: _useTls,
                            onChanged: (v) => setState(() => _useTls = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(
                        labelText: 'SMTP username',
                        hintText: 'usually your email address',
                      ),
                      validator: (v) =>
                          _enabled && (v == null || v.trim().isEmpty)
                              ? 'Required when enabled'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtrl,
                      decoration: InputDecoration(
                        labelText: 'SMTP password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (v) => _enabled && (v == null || v.isEmpty)
                          ? 'Required when enabled'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fromEmailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'From email',
                        hintText: 'bookings@yourvenue.co.za',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          _enabled && (v == null || !v.contains('@'))
                              ? 'Valid email required when enabled'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fromNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'From name',
                        hintText: 'shown in the customer’s inbox',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const Text(
                      'What to send',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('New bookings & requests'),
                      value: _notifyBookings,
                      onChanged: (v) => setState(() => _notifyBookings = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Status changes'),
                      subtitle: const Text(
                        'Approved, declined, cancelled, rescheduled',
                      ),
                      value: _notifyStatus,
                      onChanged: (v) => setState(() => _notifyStatus = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Receipts & invoices'),
                      value: _sendReceipts,
                      onChanged: (v) => setState(() => _sendReceipts = v),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving || _testing ? null : _save,
                        child: _saving
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
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _saving || _testing ? null : _sendTest,
                        icon: _testing
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.outgoing_mail, size: 20),
                        label: const Text('Save & Send Test Email'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
