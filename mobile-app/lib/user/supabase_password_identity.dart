import 'package:supabase_flutter/supabase_flutter.dart';

/// True when the signed-in Auth user has an email/password identity.
/// OAuth-only accounts typically have google/facebook identities and no email provider.
bool supabaseUserHasPasswordIdentity(User? user) {
  if (user == null) {
    return true;
  }

  final fromIdentities = user.identities
          ?.map((identity) => identity.provider.toLowerCase())
          .toList(growable: false) ??
      const <String>[];

  final providers = <String>{...fromIdentities};

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

  if (providers.isEmpty) {
    return true;
  }

  return providers.contains('email');
}
