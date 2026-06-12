import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/repositories/auth_repository.dart';

// ──────── Forgot Password ────────

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final email = _emailController.text.trim();
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetCode(email);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OtpVerifyScreen.recovery(email: email),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Enter your account email and we'll send a 6-digit code "
                  'to reset your password.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v == null || !v.contains('@')
                      ? 'Enter valid email'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendCode,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send Code'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────── 6-digit Code Verification ────────

enum _OtpPurpose { signup, recovery }

/// Collects the emailed 6-digit code; for password recovery it also takes
/// the new password. A successful verification signs the user in.
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen.signup({
    required this.email,
    required this.fullName,
    this.role = 'user',
    super.key,
  }) : _purpose = _OtpPurpose.signup;

  const OtpVerifyScreen.recovery({required this.email, super.key})
      : _purpose = _OtpPurpose.recovery,
        fullName = '',
        role = 'user';

  final String email;
  final String fullName;
  final String role;
  final _OtpPurpose _purpose;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;

  bool get _isRecovery => widget._purpose == _OtpPurpose.recovery;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final repo = ref.read(authRepositoryProvider);
    try {
      final response = await repo.verifyEmailCode(
        email: widget.email,
        code: _codeController.text.trim(),
        type: _isRecovery ? OtpType.recovery : OtpType.signup,
      );
      if (_isRecovery) {
        await repo.updatePassword(_passwordController.text);
      } else if (response.user != null) {
        await repo.completeProfile(
          userId: response.user!.id,
          email: widget.email,
          fullName: widget.fullName,
          role: widget.role,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isRecovery
                  ? 'Password updated — you are signed in.'
                  : 'Welcome to VenueVibe!',
            ),
          ),
        );
        context.go('/');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    final repo = ref.read(authRepositoryProvider);
    try {
      if (_isRecovery) {
        await repo.sendPasswordResetCode(widget.email);
      } else {
        await repo.resendSignupCode(widget.email);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A new code is on its way.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not resend: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRecovery ? 'Enter Reset Code' : 'Confirm Your Email'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'We emailed a 6-digit code to ${widget.email}.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: '6-digit code',
                    prefixIcon: Icon(Icons.pin_outlined),
                    counterText: '',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  validator: (v) => v == null || v.trim().length != 6
                      ? 'Enter the 6-digit code'
                      : null,
                ),
                if (_isRecovery) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      prefixIcon: const Icon(Icons.lock_outlined),
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
                    validator: (v) =>
                        v == null || v.length < 6 ? 'Min 6 characters' : null,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verify,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isRecovery
                                ? 'Reset Password'
                                : 'Confirm & Sign In',
                          ),
                  ),
                ),
                TextButton(
                  onPressed: _resend,
                  child: const Text('Resend code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
