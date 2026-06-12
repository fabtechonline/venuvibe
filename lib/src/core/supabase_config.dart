import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://tlzhxzhrhuxqmtsuaaiz.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6'
      'InRsemh4emhyaHV4cW10c3VhYWl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyNTg3'
      'MzYsImV4cCI6MjA4NjgzNDczNn0.OCtkUnUzvksYS43fziutx7h496VDWmVgOPsdOBIschE';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
