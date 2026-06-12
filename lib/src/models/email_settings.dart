/// A venue's own SMTP account, used to email customers about bookings,
/// status changes and receipts. Stored per tenant (owner/admin-only RLS).
class TenantEmailSettings {
  const TenantEmailSettings({
    required this.tenantId,
    this.enabled = false,
    this.smtpHost = '',
    this.smtpPort = 587,
    this.smtpUsername = '',
    this.smtpPassword = '',
    this.useTls = false,
    this.fromEmail = '',
    this.fromName = '',
    this.notifyBookings = true,
    this.notifyStatus = true,
    this.sendReceipts = true,
  });

  factory TenantEmailSettings.fromJson(Map<String, dynamic> json) {
    return TenantEmailSettings(
      tenantId: json['tenant_id'] as String,
      enabled: json['enabled'] as bool? ?? false,
      smtpHost: json['smtp_host'] as String? ?? '',
      smtpPort: json['smtp_port'] as int? ?? 587,
      smtpUsername: json['smtp_username'] as String? ?? '',
      smtpPassword: json['smtp_password'] as String? ?? '',
      useTls: json['use_tls'] as bool? ?? false,
      fromEmail: json['from_email'] as String? ?? '',
      fromName: json['from_name'] as String? ?? '',
      notifyBookings: json['notify_bookings'] as bool? ?? true,
      notifyStatus: json['notify_status'] as bool? ?? true,
      sendReceipts: json['send_receipts'] as bool? ?? true,
    );
  }

  final String tenantId;
  final bool enabled;
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final String smtpPassword;

  /// true = implicit TLS (usually port 465); false = plain/STARTTLS (587).
  final bool useTls;
  final String fromEmail;
  final String fromName;
  final bool notifyBookings;
  final bool notifyStatus;
  final bool sendReceipts;

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'enabled': enabled,
        'smtp_host': smtpHost,
        'smtp_port': smtpPort,
        'smtp_username': smtpUsername,
        'smtp_password': smtpPassword,
        'use_tls': useTls,
        'from_email': fromEmail,
        'from_name': fromName,
        'notify_bookings': notifyBookings,
        'notify_status': notifyStatus,
        'send_receipts': sendReceipts,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}
