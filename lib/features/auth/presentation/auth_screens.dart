import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/firebase_services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!FirebaseAuthService.instance.isReady) {
      _showMessage(
          'Firebase is not configured yet. See the setup steps in README.md.');
      return;
    }
    setState(() => _loading = true);
    try {
      await action();
      if (mounted) context.go('/');
    } on FirebaseAuthException catch (error) {
      _showMessage(_authError(error));
    } catch (_) {
      _showMessage(
          'Could not connect. Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _AuthBackground(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.fromLTRB(24, 28, 24, 30),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/skinai_logo.png',
                      width: 116,
                      height: 116,
                      fit: BoxFit.contain,
                      semanticLabel: 'SkinAI Assist',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xff123b58),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue your skin health journey.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  _AuthCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType:
                                TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.email
                            ],
                            textInputAction:
                                TextInputAction.next,
                            decoration:
                                const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon:
                                  Icon(Icons.mail_outline),
                            ),
                            validator: (value) => value ==
                                        null ||
                                    !value
                                        .trim()
                                        .contains('@')
                                ? 'Enter a valid email address'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: const [
                              AutofillHints.password
                            ],
                            textInputAction:
                                TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                  Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                    () => _obscurePassword =
                                        !_obscurePassword),
                                icon: Icon(_obscurePassword
                                    ? Icons
                                        .visibility_outlined
                                    : Icons
                                        .visibility_off_outlined),
                              ),
                            ),
                            validator: (value) =>
                                value == null ||
                                        value.isEmpty
                                    ? 'Enter your password'
                                    : null,
                          ),
                          Align(
                            alignment:
                                Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : _resetPassword,
                              child: const Text(
                                  'Forgot password?'),
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed:
                                _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sign in'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => _run(
                                      FirebaseAuthService
                                          .instance
                                          .signInDemo,
                                    ),
                            icon: const Icon(
                                Icons.science_outlined),
                            label: const Text(
                                'Try demo account'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Prototype demo: demo@skinai.app · SkinAI123!',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: colors
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => context.push('/signup'),
                    child: const Text(
                        'New to SkinAI Assist? Create an account'),
                  ),
                  if (!FirebaseAuthService.instance.isReady)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Firebase setup is required to sign in. Add your Firebase settings, then restart the app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _run(() => FirebaseAuthService.instance.signIn(
          _emailController.text,
          _passwordController.text,
        ));
  }

  Future<void> _resetPassword() async {
    if (!_emailController.text.trim().contains('@')) {
      _showMessage('Enter your email address first.');
      return;
    }
    try {
      await FirebaseAuthService.instance
          .sendPasswordReset(_emailController.text);
      _showMessage(
          'Password reset email sent. Check your inbox.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_authError(error));
    } catch (_) {
      _showMessage(
          'Could not send the reset email. Try again.');
    }
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!FirebaseAuthService.instance.isReady) {
      _message(
          'Firebase is not configured yet. See the setup steps in README.md.');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuthService.instance.signUp(
        _nameController.text,
        _emailController.text,
        _passwordController.text,
      );
      if (mounted) context.go('/');
    } on FirebaseAuthException catch (error) {
      _message(_authError(error));
    } catch (_) {
      _message(
          'Could not create the account. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return _AuthBackground(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.fromLTRB(24, 28, 24, 30),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(
                      tooltip: 'Back to sign in',
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  Center(
                    child: Image.asset(
                      'assets/images/skinai_logo.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create your account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xff123b58),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your account keeps your profile and screening history together.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _AuthCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            textCapitalization:
                                TextCapitalization.words,
                            textInputAction:
                                TextInputAction.next,
                            decoration:
                                const InputDecoration(
                              labelText: 'Name',
                              prefixIcon: Icon(
                                  Icons.person_outline),
                            ),
                            validator: (value) =>
                                value == null ||
                                        value.trim().isEmpty
                                    ? 'Enter your name'
                                    : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailController,
                            keyboardType:
                                TextInputType.emailAddress,
                            textInputAction:
                                TextInputAction.next,
                            decoration:
                                const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon:
                                  Icon(Icons.mail_outline),
                            ),
                            validator: (value) => value ==
                                        null ||
                                    !value
                                        .trim()
                                        .contains('@')
                                ? 'Enter a valid email address'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction:
                                TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              helperText:
                                  'Use at least 6 characters',
                              prefixIcon: const Icon(
                                  Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                    () => _obscurePassword =
                                        !_obscurePassword),
                                icon: Icon(_obscurePassword
                                    ? Icons
                                        .visibility_outlined
                                    : Icons
                                        .visibility_off_outlined),
                              ),
                            ),
                            validator: (value) => value ==
                                        null ||
                                    value.length < 6
                                ? 'Password must be at least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed:
                                _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Create account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text(
                        'Already have an account? Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xffedf9f7),
              Theme.of(context).colorScheme.surface,
              const Color(0xfff2f8fc),
            ],
          ),
        ),
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surface
          .withValues(alpha: .94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(
          color:
              Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: child,
      ),
    );
  }
}

String _authError(FirebaseAuthException error) =>
    switch (error.code) {
      'invalid-email' => 'That email address is not valid.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Email or password is incorrect.',
      'email-already-in-use' =>
        'An account already uses that email.',
      'weak-password' =>
        'Choose a stronger password with at least 6 characters.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      'too-many-requests' =>
        'Too many attempts. Please wait and try again.',
      'firebase-not-configured' =>
        'Firebase is not configured yet. See the setup steps in README.md.',
      _ => error.message ??
          'Authentication failed. Please try again.',
    };
