class Result<T> {
  const Result._({this.value, this.error});

  /// Payload on success
  final T? value;

  /// Exception / error on failure.
  final Object? error;

  bool get isSuccess => error == null;
  bool get isFailure => !isSuccess;

  factory Result.success([T? value]) => Result._(value: value);
  factory Result.failure(Object error) => Result._(error: error);
}
