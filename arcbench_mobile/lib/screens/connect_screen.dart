import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';
import 'package:arcbench_mobile/screens/home_shell.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  bool _obscure = true;
  bool _isRegister = false;
  final _scrollController = ScrollController();

  late AnimationController _pulseCtl;

  @override
  void initState() {
    super.initState();
    _pulseCtl = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtl.dispose();
    _scrollController.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final conn = context.read<ConnectionProvider>();
    final email = _emailCtl.text.trim();
    final pass = _passCtl.text;

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    bool ok;
    if (_isRegister) {
      final name = _nameCtl.text.trim();
      ok = await conn.register(email, pass, displayName: name.isNotEmpty ? name : null);
    } else {
      ok = await conn.login(email, pass);
    }

    if (ok && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }

    final conn = context.read<ConnectionProvider>();
    final sent = await conn.resetPassword(email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Password reset email sent to $email'
                : conn.error ?? 'Failed to send reset email',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _pulseCtl,
          builder: (_, child) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(
                    const Color(0xFF0D1117),
                    const Color(0xFF0F1923),
                    _pulseCtl.value,
                  )!,
                  ArcBenchTheme.surface,
                ],
              ),
            ),
            child: child,
          ),
          child: SafeArea(
            child: Consumer<ConnectionProvider>(
              builder: (context, conn, _) {
                if (bottom > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  });
                }
                return ListView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(28, 0, 28, bottom + 40),
                children: [
                  const SizedBox(height: 56),

                  // ── Logo mark ──
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1E3A5F),
                            Color(0xFF0F1D30),
                          ],
                        ),
                        border: Border.all(
                          color: ArcBenchTheme.arcBlue.withAlpha(50),
                        ),
                      ),
                      child: const Icon(
                        Icons.terminal_rounded,
                        size: 34,
                        color: ArcBenchTheme.arcBlue,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Center(
                    child: Text(
                      'ArcBench',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontSize: 26,
                                letterSpacing: -0.5,
                              ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      _isRegister
                          ? 'Create a new account'
                          : 'Sign in to continue',
                      style: const TextStyle(
                        color: ArcBenchTheme.textMuted,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  const SizedBox(height: 44),

                  // ── Display name (register only) ──
                  if (_isRegister) ...[
                    _StyledField(
                      controller: _nameCtl,
                      label: 'Display name',
                      hint: 'Your name (optional)',
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Email ──
                  _StyledField(
                    controller: _emailCtl,
                    label: 'Email',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofocus: false,
                  ),

                  const SizedBox(height: 16),

                  // ── Password ──
                  _StyledField(
                    controller: _passCtl,
                    label: 'Password',
                    hint: _isRegister
                        ? 'Choose a password (6+ chars)'
                        : 'Enter your password',
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    suffix: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                        color: ArcBenchTheme.textMuted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),

                  // ── Forgot password ──
                  if (!_isRegister)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: ArcBenchTheme.arcBlue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                        ),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── Submit ──
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: conn.isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ArcBenchTheme.arcBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            ArcBenchTheme.arcBlue.withAlpha(80),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: conn.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isRegister ? 'Create Account' : 'Sign In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),

                  // ── Error ──
                  if (conn.error != null && conn.error!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ArcBenchTheme.error.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ArcBenchTheme.error.withAlpha(50),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: ArcBenchTheme.error, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                conn.error!,
                                style: const TextStyle(
                                  color: ArcBenchTheme.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ── Toggle sign in / register ──
                  Center(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _isRegister = !_isRegister),
                      child: Text.rich(
                        TextSpan(
                          text: _isRegister
                              ? 'Already have an account? '
                              : "Don't have an account? ",
                          style: const TextStyle(
                            color: ArcBenchTheme.textMuted,
                            fontSize: 14,
                          ),
                          children: [
                            TextSpan(
                              text: _isRegister ? 'Sign In' : 'Create one',
                              style: const TextStyle(
                                color: ArcBenchTheme.arcBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal labeled text field with floating label above.
class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;

  const _StyledField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.suffix,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: ArcBenchTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofocus: autofocus,
          autocorrect: false,
          textCapitalization: textCapitalization,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            color: ArcBenchTheme.textPrimary,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: ArcBenchTheme.textMuted,
              fontSize: 15,
            ),
            filled: true,
            fillColor: const Color(0xFF1A1A24),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withAlpha(15), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withAlpha(15), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: ArcBenchTheme.arcBlue, width: 1.5),
            ),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
