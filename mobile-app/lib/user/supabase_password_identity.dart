import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_config.dart';

/// True when the signed-in Auth user has an email/password credential.
///
/// OAuth JWTs often omit the email identity even after a password was set.
/// Prefer a fresh [User] from Auth `getUser()`, then the PHP checkEmailExists
/// boolean (derived server-side from Auth Admin identities/metadata).
bool supabaseUserHasPasswordIdentity(User? user) {
  return hasEmailPasswordCredential(user);
}

/// Authoritative client-side read of whether this Auth user has an
/// email/password credential. Does not read password hashes.
bool hasEmailPasswordCredential(User? user) {
  if (user == null) {
    return false;
  }

  final providers = _providersOf(user);
  if (providers.contains('email')) {
    return true;
  }

  final metadata = user.userMetadata ?? const <String, dynamic>{};
  final flagged = metadata['has_email_password'];
  if (flagged == true || flagged == 'true' || flagged == 1) {
    return true;
  }

  if (providers.isEmpty) {
    return true;
  }

  return false;
}

Set<String> _providersOf(User user) {
  final providers = <String>{};
  final identities = user.identities;
  if (identities != null) {
    for (final identity in identities) {
      providers.add(identity.provider.toLowerCase());
    }
  }

  final metaProviders = user.appMetadata['providers'];
  if (metaProviders is List) {
    for (final item in metaProviders) {
      providers.add(item.toString().toLowerCase());
    }
  }
  final metaProvider = user.appMetadata['provider']?.toString().toLowerCase();
  if (metaProvider != null && metaProvider.isNotEmpty) {
    providers.add(metaProvider);
  }
  return providers;
}

Future<bool> resolveHasPasswordIdentity({String? email}) async {
  return hasEmailPasswordCredentialRemote(email: email);
}

Future<bool> hasEmailPasswordCredentialRemote({String? email}) async {
  User? user = Supabase.instance.client.auth.currentUser;
  try {
    final response = await Supabase.instance.client.auth.getUser();
    user = response.user ?? user;
  } catch (_) {}

  if (hasEmailPasswordCredential(user)) {
    return true;
  }

  final lookupEmail =
      (email ?? user?.email ?? '').trim();
  if (lookupEmail.isEmpty) {
    return false;
  }

  try {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'checkEmailExists',
        'email': lookupEmail,
      }),
    );
    if (response.statusCode != 200 || response.body.isEmpty) {
      return false;
    }
    final data = jsonDecode(response.body);
    if (data is Map && data['hasPassword'] == true) {
      return true;
    }
  } catch (_) {}

  return false;
}

/// Persists password-capable state in Auth user_metadata after a successful
/// email/password sign-in or password update. Safe no-op if already set.
Future<void> confirmEmailPasswordCredential() async {
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }
    if (hasEmailPasswordCredential(user)) {
      return;
    }
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(data: const {'has_email_password': true}),
    );
  } catch (_) {}
}

Map<String, dynamic>? decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    final pad = payload.length % 4;
    if (pad > 0) {
      payload += '=' * (4 - pad);
    }
    final decoded = utf8.decode(base64Decode(payload));
    final jsonMap = jsonDecode(decoded);
    return jsonMap is Map<String, dynamic>
        ? jsonMap
        : jsonMap is Map
            ? Map<String, dynamic>.from(jsonMap)
            : null;
  } catch (_) {
    return null;
  }
}

/// Recovery email links mint a session whose JWT AMR includes `recovery`.
bool sessionLooksLikePasswordRecovery(Session? session) {
  if (session == null) {
    return false;
  }
  final payload = decodeJwtPayload(session.accessToken);
  if (payload == null) {
    return false;
  }
  final amr = payload['amr'];
  if (amr is List) {
    for (final item in amr) {
      if (item is Map && '${item['method']}'.toLowerCase() == 'recovery') {
        return true;
      }
      if (item is String && item.toLowerCase() == 'recovery') {
        return true;
      }
    }
  }
  return false;
}
