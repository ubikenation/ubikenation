import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Picks a document photo and uploads it to the private `rider-documents`
/// bucket at `<uid>/<docKey>.jpg`. Returns the stored object path, or null
/// if the user cancelled.
class StorageService {
  static const String bucket = 'rider-documents';
  final _picker = ImagePicker();

  Future<String?> pickAndUploadDoc(String docKey) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not signed in');

    final path = '$uid/$docKey.jpg';
    final bytes = await picked.readAsBytes();
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  /// Returns, for the given doc keys, the stored object paths that already exist for
  /// this user — so a rider who exits mid-registration and returns doesn't have to
  /// re-upload photos they already provided.
  Future<Map<String, String>> existingDocs(List<String> keys) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return {};
    try {
      final files = await client.storage.from(bucket).list(path: uid);
      final names = files.map((f) => f.name).toSet();
      final out = <String, String>{};
      for (final k in keys) {
        if (names.contains('$k.jpg')) out[k] = '$uid/$k.jpg';
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
