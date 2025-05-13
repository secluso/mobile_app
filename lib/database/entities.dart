import 'package:objectbox/objectbox.dart';

// Camera entity just storing name for now. Allows for expandability to things like per-camera settings
@Entity()
class Camera {
  int id;

  @Index()
  String name;

  Camera(this.name, {this.id = 0});
}

// Video entity storing camera association, video file name, received status, and if there was motion (could be a livestream).
@Entity()
class Video {
  int id;

  String camera;
  @Index()
  String video;
  bool received;
  bool motion;

  Video(this.camera, this.video, this.received, this.motion, {this.id = 0});
}
