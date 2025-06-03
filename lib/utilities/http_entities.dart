// JSON for serialization structure matching the server

class MotionPair {
  String groupName;
  int epochToCheck;

  MotionPair(this.groupName, this.epochToCheck);

  Map<String, dynamic> toJson() => {
    'group_name': groupName,
    'epoch_to_check': epochToCheck,
  };
}

class MotionPairs {
  List<MotionPair> groupNames;

  MotionPairs(this.groupNames);

  Map<String, dynamic> toJson() => {'group_names': groupNames};
}
