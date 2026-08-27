import 'profile_image_service.dart';

ProfileImageService createPlatformProfileImageService() =>
    WebProfileImageService();

class WebProfileImageService implements ProfileImageService {
  @override
  Future<String?> pickAndPersist() async => null;
}
