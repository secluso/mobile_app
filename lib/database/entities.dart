import 'package:objectbox/objectbox.dart';

// Camera entity just storing name for now. Allows for expandability to things like per-camera settings
@Entity()
class Camera {
  int id;

  @Index()
  String name;

  bool unreadMessages;

  Camera(this.name, {this.unreadMessages = false, this.id = 0});
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

// Entity that stores the current daatbase version. Used to let us know if we need to apply any database patches in the migration runner.
@Entity()
class Meta {
  int id = 0;
  int dbVersion;

  Meta({this.dbVersion = 0});
}
