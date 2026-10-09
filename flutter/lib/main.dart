import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Copy these from the CloudFormation stack Outputs. Do NOT embed AWS keys.
// For production, supply with --dart-define.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const cognitoIssuer = String.fromEnvironment('COGNITO_ISSUER');
const cognitoClientId = String.fromEnvironment('COGNITO_CLIENT_ID');
const redirectUri = 'brazilexit://oauth';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BrazilExitApp());
}

class BrazilExitApp extends StatelessWidget {
  const BrazilExitApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Brazil Exit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal, brightness: Brightness.dark),
            useMaterial3: true),
        home: const PowerScreen(),
      );
}

class PowerScreen extends StatefulWidget {
  const PowerScreen({super.key});
  @override
  State<PowerScreen> createState() => _PowerScreenState();
}

class _PowerScreenState extends State<PowerScreen> {
  final _auth = FlutterAppAuth();
  final _storage = const FlutterSecureStorage();
  final _http = http.Client();
  Timer? _poll;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String _state = 'unknown';
  String _message = 'Sign in once to control the EC2 instance.';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restore();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_busy && _refreshToken != null) _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _http.close();
    super.dispose();
  }

  Future<void> _restore() async {
    String? refresh;
    try {
      refresh = await _storage.read(key: 'refresh_token');
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'Cannot read secure sign-in storage. Please sign in.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _refreshToken = refresh);
    if (refresh != null) await _refresh();
  }

  Future<void> _login() async {
    if (apiBaseUrl.isEmpty ||
        cognitoIssuer.isEmpty ||
        cognitoClientId.isEmpty) {
      setState(
          () => _message = 'Build-time configuration missing; see README.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Opening secure sign-in...';
    });
    try {
      final result = await _auth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          cognitoClientId,
          redirectUri,
          issuer: cognitoIssuer,
          scopes: const ['openid', 'email', 'profile'],
          promptValues: const ['login'],
        ),
      );
      if (result.accessToken == null) {
        throw Exception('No access token returned');
      }
      await _saveTokens(result.accessToken!, result.refreshToken,
          result.accessTokenExpirationDateTime);
      await _loadState();
    } on FlutterAppAuthUserCancelledException {
      if (mounted) setState(() => _message = 'Sign-in cancelled');
    } catch (e) {
      if (mounted) setState(() => _message = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTokens(
      String access, String? refresh, DateTime? expiry) async {
    _accessToken = access;
    _refreshToken = refresh ?? _refreshToken;
    _expiresAt = expiry;
    if (_refreshToken != null) {
      await _storage.write(key: 'refresh_token', value: _refreshToken);
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureAccessToken() async {
    if (_accessToken != null &&
        (_expiresAt == null ||
            _expiresAt!
                .isAfter(DateTime.now().add(const Duration(minutes: 2))))) {
      return;
    }
    if (_refreshToken == null) throw StateError('Not signed in');
    final response = await _auth.token(TokenRequest(
      cognitoClientId,
      redirectUri,
      issuer: cognitoIssuer,
      refreshToken: _refreshToken,
      scopes: const ['openid', 'email', 'profile'],
    ));
    if (response.accessToken == null) throw StateError('Please sign in again');
    await _saveTokens(response.accessToken!, response.refreshToken,
        response.accessTokenExpirationDateTime);
  }

  Future<http.Response> _request(String path,
      {Map<String, String>? body}) async {
    await _ensureAccessToken();
    final url = Uri.parse('${apiBaseUrl.replaceAll(RegExp(r"/+$"), "")}$path');
    final headers = {
      'Authorization': 'Bearer $_accessToken',
      'Content-Type': 'application/json'
    };
    final res = body == null
        ? await _http
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 15))
        : await _http
            .post(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return res;
  }

  Future<void> _loadState() async {
    final res = await _request('/state');
    final state =
        (jsonDecode(res.body) as Map<String, dynamic>)['state']?.toString() ??
            'unknown';
    if (mounted) {
      setState(() {
        _state = state;
        _message = 'EC2 is $state. This does not verify Tailscale readiness.';
      });
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _loadState();
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'Cannot reach AWS control API: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _power() async {
    if (_busy) return;
    final action =
        _state == 'stopped' ? 'on' : (_state == 'running' ? 'off' : null);
    if (action == null) return;
    if (action == 'off') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop Brazil exit node?'),
          content: const Text(
              'First select None in Tailscale on phones and other manually managed devices. Devices still using Brazil may lose Internet.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Stop EC2')),
          ],
        ),
      );
      if (confirmed != true || !mounted || _busy) return;
    }
    setState(() {
      _busy = true;
      _message = '${action == 'on' ? 'Starting' : 'Stopping'} EC2...';
    });
    try {
      await _request('/power', body: {'action': action});
      await _loadState();
    } catch (e) {
      if (mounted) setState(() => _message = 'Power command failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await _storage.delete(key: 'refresh_token');
    if (mounted) {
      setState(() {
        _accessToken = null;
        _refreshToken = null;
        _expiresAt = null;
        _state = 'unknown';
        _message = 'Signed out of the controller.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authenticated = _refreshToken != null;
    final on = _state == 'running';
    final off = _state == 'stopped';
    final canToggle = !_busy && (on || off) && authenticated;
    return Scaffold(
      appBar: AppBar(title: const Text('Brazil Exit'), actions: [
        if (authenticated)
          IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _busy ? null : _signOut),
      ]),
      body: SafeArea(
          child: Center(
              child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('SÃO PAULO • AWS',
              style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 2)),
          const SizedBox(height: 35),
          if (!authenticated)
            FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: const Icon(Icons.lock_open),
                label: const Text('Sign in'))
          else
            GestureDetector(
              onTap: canToggle ? _power : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 215,
                height: 215,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on
                      ? Colors.green.shade700
                      : (off ? Colors.blueGrey.shade700 : Colors.grey.shade800),
                  boxShadow: [
                    BoxShadow(
                        color: on
                            ? Colors.green.withValues(alpha: 0.24)
                            : Colors.black26,
                        blurRadius: 28,
                        spreadRadius: 5)
                  ],
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy)
                        const CircularProgressIndicator(color: Colors.white)
                      else
                        const Icon(Icons.power_settings_new,
                            color: Colors.white, size: 76),
                      const SizedBox(height: 6),
                      Text(
                          on
                              ? 'TURN OFF'
                              : (off ? 'TURN ON' : _state.toUpperCase()),
                          style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ]),
              ),
            ),
          const SizedBox(height: 26),
          Text(_message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          if (authenticated)
            TextButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status')),
          const SizedBox(height: 10),
          const Text(
              'Controls EC2 power only. Tailscale exit-node selection is a separate client setting.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12)),
        ]),
      ))),
    );
  }
}
