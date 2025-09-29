//! SPDX-License-Identifier: GPL-3.0-or-later
// JSON for serialization structure matching the server

// Used in bulk check to contain the group name and epochs for each in the list.
class MotionPair {
  String groupName;
  int epochToCheck;

  MotionPair(this.groupName, this.epochToCheck);

  Map<String, dynamic> toJson() => {
    'group_name': groupName,
    'epoch_to_check': epochToCheck,
  };
}

// Used in bulk check to contain a list of MotionPair (see above)
class MotionPairs {
  List<MotionPair> groupNames;

  MotionPairs(this.groupNames);

  Map<String, dynamic> toJson() => {'group_names': groupNames};
}

// Used in our /pair request to ensure atomically that both sides have paired correctly
class PairingRequest {
  final String pairingToken;
  final String role;

  PairingRequest(this.pairingToken, this.role);

  Map<String, dynamic> toJson() => {
    'pairing_token': pairingToken,
    'role': role,
  };
}

// TODO: Expand on this to store / retrieve settings from the server.
class ClientSettingsMessage {
  String sender;
  String type;
  String status;
  int endTime;

  ClientSettingsMessage({
    required this.sender,
    required this.type,
    required this.status,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'sender': sender,
    'type': type,
    'status': status,
    'endTime': endTime,
  };
}
