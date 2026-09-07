import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';

/// Shown only after main.dart has already exchanged a password-recovery
/// link's token_hash for a real session (see `_recoverySessionReady` in
/// main.dart). Lets the host set a new password and lands them in the
/// dashboard directly — no sign-out step, unlike the signup-confirmation
/// flow: clicking the emailed recovery link IS the identity proof for a
/// password reset.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isLoading = false;
  bool _showPassword = false;
  String? _fieldError;

  static const _minPasswordLength = 8;

  @override
  void initState() {
    super.initState();
    // Safety net: this screen is only ever routed to after main.dart already
    // confirmed a valid recovery session — but if that session is somehow
    // gone by the time this builds, don't show a form that can only fail.
    if (Supabase.instance.client.auth.currentSession == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AuthScreen(recoveryLinkExpired: true)),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  /// Same rules as auth_screen.dart's sign-up validation, duplicated rather
  /// than shared: only two call sites, and this keeps each screen's
  /// validation self-contained per this codebase's existing convention.
  (String?, FocusNode?) _validateNewPassword(String password, String confirm) {
    if (password.length < _minPasswordLength) {
      return ('Use at least $_minPasswordLength characters.', _passwordFocus);
    }
    if (!RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return (
        'Use upper- and lower-case letters and at least one number.',
        _passwordFocus,
      );
    }
    if (password != confirm) {
      return ("Passwords don't match.", _confirmFocus);
    }
    return (null, null);
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final (problem, focusOn) = _validateNewPassword(password, confirm);
    if (problem != null) {
      setState(() => _fieldError = problem);
      focusOn?.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _fieldError = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: context.palette.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: context.palette.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: context.palette.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.home_work_rounded,
                          color: context.palette.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Alfred',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        color: context.palette.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Set a new password',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose a new password for your account',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: context.palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  onChanged: (_) {
                    if (_fieldError != null) setState(() => _fieldError = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText:
                        'At least 8 characters, with upper- and lower-case and a number',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: context.palette.textMuted,
                        ),
                        splashRadius: 22,
                        tooltip: _showPassword ? 'Hide password' : 'Show password',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmController,
                  focusNode: _confirmFocus,
                  onChanged: (_) {
                    if (_fieldError != null) setState(() => _fieldError = null);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _isLoading ? null : _submit(),
                ),
                if (_fieldError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _fieldError!,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: context.palette.danger),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Set new password',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
