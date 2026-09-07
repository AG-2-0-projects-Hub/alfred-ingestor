import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  /// True when the host just arrived from the "confirm your email" link. The
  /// session that link created has been dropped on purpose (it would otherwise
  /// sign anyone holding the email straight in), so tell them why they're here.
  final bool justConfirmed;

  /// True when the host arrived via a password-reset link that turned out to
  /// be expired or already used (main.dart already tried and failed to
  /// establish a recovery session). Shows a banner offering to send a new one.
  final bool recoveryLinkExpired;

  const AuthScreen({
    super.key,
    this.justConfirmed = false,
    this.recoveryLinkExpired = false,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _showPassword = false;
  String? _fieldError;

  /// Set once a sign-up succeeds but returns no session, i.e. the account needs
  /// email confirmation. The form is replaced by a "check your inbox" panel.
  String? _awaitingConfirmationFor;

  /// True while showing the "forgot password" mini-form instead of the normal
  /// sign-in/sign-up form. Only ever reachable from sign-in mode.
  bool _showForgotPassword = false;

  /// Set once a password-reset email has been sent; swaps the mini-form for a
  /// "check your inbox" panel, mirroring _awaitingConfirmationFor.
  String? _resetSentTo;

  bool _isSendingReset = false;

  static const _minPasswordLength = 8;

  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  /// Sign-up only. Returns (error message, the field to send them back to), or
  /// (null, null) when the input is good.
  (String?, FocusNode?) _validateSignUp(String password, String confirm) {
    if (password.length < _minPasswordLength) {
      return ('Use at least $_minPasswordLength characters.', _passwordFocus);
    }
    // A host's account holds their guests' conversations, so make the password
    // do some work: an 8-char all-lowercase password is barely a password.
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
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    if (!_isLogin) {
      final (problem, focusOn) = _validateSignUp(password, _confirmController.text);
      if (problem != null) {
        setState(() => _fieldError = problem);
        // Put the caret back in the offending field. Without this the form lost
        // focus after a rejected submit and the password field became
        // un-editable until a page reload.
        focusOn?.requestFocus();
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _fieldError = null;
    });
    try {
      if (_isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        final redirectTo = '${Uri.base.scheme}://${Uri.base.host}';
        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: redirectTo,
        );
        // With email confirmation on, sign-up returns a user but NO session.
        // Sending them to the dashboard anyway left them signed out but looking
        // signed in — no email, no stats, and nothing loadable. Show the
        // confirmation step instead, and never navigate without a session.
        if (res.session == null) {
          if (mounted) {
            setState(() => _awaitingConfirmationFor = email);
          }
          return;
        }
      }
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

  /// Sends the Supabase password-reset email. No `redirectTo` is passed: the
  /// The `flow=recovery` marker on redirectTo is how main.dart tells this
  /// link apart from a signup-confirmation link — both are a bare PKCE
  /// `?code=` otherwise. Supabase's default email template (unconfigurable on
  /// projects without custom SMTP — confirmed empirically on prod) still
  /// works fine here: redirectTo's own query params ride along with whatever
  /// `code` Supabase appends, so no template edit is needed on either project.
  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _fieldError = 'Enter your email address.');
      return;
    }
    setState(() {
      _isSendingReset = true;
      _fieldError = null;
    });
    try {
      final redirectTo = '${Uri.base.scheme}://${Uri.base.host}/?flow=recovery';
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
      );
      if (mounted) setState(() => _resetSentTo = email);
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
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (isWide) return _buildWideLayout();
        return _buildNarrowLayout();
      }),
    );
  }

  // ── Two-panel layout for desktop ─────────────────────────────────────────
  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left: brand panel
        Expanded(
          flex: 5,
          child: _buildBrandPanel(),
        ),
        // Right: form panel
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _buildForm(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Single-column layout for mobile ──────────────────────────────────────
  Widget _buildNarrowLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 24),
              _buildLogo(large: false),
              const SizedBox(height: 32),
              _buildForm(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Brand panel (left side on desktop) ───────────────────────────────────
  Widget _buildBrandPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1F0E3D), // deepest obsidian-amethyst
            Color(0xFF3D1C6B), // deep amethyst
            Color(0xFF6E38A7), // ethereal amethyst
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Subtle pattern overlay
          Positioned.fill(
            child: CustomPaint(painter: _DotPatternPainter()),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogo(large: true, light: true),
                const Spacer(),
                Text(
                  'Give yourself\nthe gift of time.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: AppTheme.responsiveFontSize(context, 42),
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Alfred answers every guest message,\n'
                  '24/7 — while you live your life.',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),
                _buildFeaturePill(
                    Icons.smart_toy_outlined, 'AI that knows your property'),
                const SizedBox(height: 14),
                _buildFeaturePill(
                    Icons.schedule_outlined, 'Replies at 3am so you don\'t'),
                const SizedBox(height: 14),
                _buildFeaturePill(
                    Icons.sentiment_satisfied_alt_outlined,
                    'Guests love it, hosts love it more'),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.9),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLogo({required bool large, bool light = false}) {
    final color = light ? Colors.white : context.palette.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: large ? 44 : 36,
          height: large ? 44 : 36,
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.2)
                : context.palette.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.home_work_rounded,
            color: color,
            size: large ? 26 : 20,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Alfred',
          style: GoogleFonts.plusJakartaSans(
            fontSize: large ? 28 : 22,
            fontWeight: FontWeight.w300,
            color: color,
          ),
        ),
      ],
    );
  }

  // ── "Confirm your email" step (sign-up returned no session) ───────────────
  Widget _buildAwaitingConfirmation() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_unread_outlined,
            size: 44, color: context.palette.primary),
        const SizedBox(height: 20),
        Text(
          'Confirm your email',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w300,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a confirmation link to $_awaitingConfirmationFor.\n'
          'Open it to activate your account, then sign in.',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: () => setState(() {
              _awaitingConfirmationFor = null;
              _isLogin = true;
              _passwordController.clear();
              _confirmController.clear();
            }),
            child: Text(
              'Back to sign in',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  // ── "Check your inbox" step after a password-reset email is sent ─────────
  Widget _buildResetSent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_unread_outlined,
            size: 44, color: context.palette.primary),
        const SizedBox(height: 20),
        Text(
          'Check your email',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w300,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a password reset link to $_resetSentTo.\n'
          'Open it to choose a new password.',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: () => setState(() {
              _resetSentTo = null;
              _showForgotPassword = false;
            }),
            child: Text(
              'Back to sign in',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  // ── "Forgot password" mini-form ───────────────────────────────────────────
  Widget _buildForgotPasswordForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reset your password',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w300,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Enter your email and we'll send you a reset link",
          style: GoogleFonts.inter(
            fontSize: 14,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofocus: true,
          onSubmitted: (_) => _isSendingReset ? null : _sendPasswordReset(),
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
            onPressed: _isSendingReset ? null : _sendPasswordReset,
            child: _isSendingReset
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Send reset link',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _isSendingReset
                ? null
                : () => setState(() {
                      _showForgotPassword = false;
                      _fieldError = null;
                    }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Back to sign in',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Login / Sign-up form ──────────────────────────────────────────────────
  Widget _buildForm() {
    if (_awaitingConfirmationFor != null) return _buildAwaitingConfirmation();
    if (_resetSentTo != null) return _buildResetSent();
    if (_showForgotPassword) return _buildForgotPasswordForm();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.justConfirmed) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.palette.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: context.palette.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Email confirmed. Sign in to continue.',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: context.palette.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (widget.recoveryLinkExpired) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.palette.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 18, color: context.palette.danger),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'That reset link is invalid or has expired.',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: context.palette.textPrimary),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _showForgotPassword = true),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Send a new one',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.palette.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          _isLogin ? 'Welcome back' : 'Create your account',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w300,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isLogin
              ? 'Sign in to manage your properties'
              : 'Start giving yourself time back',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        // Email
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofocus: true,
        ),
        const SizedBox(height: 16),
        // Password
        TextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          onChanged: (_) {
            if (_fieldError != null) setState(() => _fieldError = null);
          },
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: _isLogin
                ? null
                : 'At least 8 characters, with upper- and lower-case and a number',
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
          textInputAction:
              _isLogin ? TextInputAction.done : TextInputAction.next,
          onSubmitted: (_) => _isLoading ? null : _submit(),
        ),
        if (_isLogin) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                        _showForgotPassword = true;
                        _fieldError = null;
                      }),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot password?',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.primary,
                ),
              ),
            ),
          ),
        ],
        // Confirm password — sign-up only. A typo here otherwise locks the host
        // out of an account they can no longer guess the password to.
        if (!_isLogin) ...[
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
        ],
        if (_fieldError != null) ...[
          const SizedBox(height: 12),
          Text(
            _fieldError!,
            style: GoogleFonts.inter(
                fontSize: 13, color: context.palette.danger),
          ),
        ],
        const SizedBox(height: 24),
        // Primary action
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
                    _isLogin ? 'Sign In' : 'Sign Up',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        // Toggle login/signup
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isLogin
                  ? "Don't have an account?"
                  : 'Already have an account?',
              style: GoogleFonts.inter(
                  fontSize: 13, color: context.palette.textSecondary),
            ),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                        _isLogin = !_isLogin;
                        _fieldError = null;
                        _confirmController.clear();
                      }),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _isLogin ? 'Sign up' : 'Sign in',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Subtle dot-grid background for brand panel ────────────────────────────
class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    const radius = 1.5;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
