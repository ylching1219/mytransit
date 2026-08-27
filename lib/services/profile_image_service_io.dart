import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'profile_image_service.dart';

ProfileImageService createPlatformProfileImageService() =>
    IoProfileImageService();

class IoProfileImageService implements ProfileImageService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> pickAndPersist() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;

    final directory = await getApplicationDocumentsDirectory();
    final pickedExtension = path.extension(picked.path);
    final extension = pickedExtension.isEmpty ? '.jpg' : pickedExtension;
    final destination = path.join(directory.path, 'profile_image$extension');
    await picked.saveTo(destination);
    return destination;
  }
}
