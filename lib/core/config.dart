import 'dart:convert';
import 'package:flutter/services.dart';
import 'models.dart';

class Organisation {
  final Record values;
  Organisation(this.values);
  static Future<Organisation> load() async => Organisation(Record.from(jsonDecode(await rootBundle.loadString('assets/organisation.json'))));
  String get name => values['name'] ?? 'Community centre';
  String get shortName => values['shortName'] ?? name;
  String get website => values['website'];
  String get timeZone => values['timeZone'] ?? 'Europe/London';
  String get radio => values['radio'];
  String get location => values['location'] ?? '';
  String get email => values['email'] ?? '';
  String get phone => values['phone'] ?? '';
  String? resolveImage(dynamic value) {
    if (value is! String) return null;
    if (value.startsWith('assets/')) return value;
    if (value.startsWith('/') && !value.startsWith('//') && !value.contains('\\')) return Uri.parse(website).resolve(value).toString();
    return safeWebUrl(value) ? value : null;
  }
}
const backendUrl = String.fromEnvironment('SUPABASE_URL');
const backendKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const extensionsEnabled = bool.fromEnvironment('ENABLE_EXTENSIONS');
const pushEnabled = bool.fromEnvironment('ENABLE_PUSH');
