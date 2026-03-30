//! SPDX-License-Identifier: GPL-3.0-or-later

class SeclusoPreviewAssets {
  const SeclusoPreviewAssets._();

  static const bool _fdroidBuild = bool.fromEnvironment('SECLUSO_FDROID_BUILD');

  static const String designFrontDoor = 'assets/design/design_front_door.png';
  static const String designLivingRoom = 'assets/design/design_living_room.png';
  static const String designBackyard = 'assets/design/design_backyard.png';
  static const String livingRoomHero = 'assets/design/living_room_hero.png';
  static const String hallwayEvent = 'assets/design/hallway_event.png';
  static const String foyerEvent = 'assets/design/foyer_event.png';
  static const String deliveryNookEvent =
      'assets/design/delivery_nook_event.png';
  static const String? reviewFrontDoorClip =
      _fdroidBuild ? null : 'assets/design/review_front_door_preview.mp4';
  static const String homeOfficeFeed = 'assets/design/home_office_feed.png';
  static const String storageFeed = 'assets/design/storage_feed.png';
  static const String corridorFeed = 'assets/design/corridor_feed.png';
  static const String loungeEvent = 'assets/design/lounge_event.png';
  static const String relayDevice = pairingCard;
  static const String pairingCard = 'assets/design/pairing_card.png';
  static const String tabletopCamera = designLivingRoom;
  static const String lensMacro = 'assets/design/lens_macro.png';
  static const String previewFrontDoor = designFrontDoor;
  static const String previewLivingRoom = designLivingRoom;
  static const String previewBackyard = designBackyard;
}
