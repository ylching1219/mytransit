import 'profile_image_service_io.dart'
    if (dart.library.html) 'profile_image_service_web.dart';

abstract class ProfileImageService {
  Future<String?> pickAndPersist();
}

ProfileImageService createProfileImageService() =>
    createPlatformProfileImageService();
