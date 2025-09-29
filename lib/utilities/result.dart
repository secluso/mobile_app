//! SPDX-License-Identifier: GPL-3.0-or-later

class Result<T> {
  const Result._({this.value, this.error});

  final T? value;
  final Object? error;

  bool get isSuccess => error == null;
  bool get isFailure => !isSuccess;

  factory Result.success([T? value]) => Result._(value: value);
  factory Result.failure(Object error) => Result._(error: error);

  R fold<R>(R Function(T value) onSuccess, R Function(Object error) onFailure) {
    return isSuccess ? onSuccess(value as T) : onFailure(error!);
  }

  Result<U> map<U>(U Function(T value) transform) {
    if (isSuccess) {
      return Result.success(transform(value as T));
    } else {
      return Result.failure(error!);
    }
  }

  Result<U> flatMap<U>(Result<U> Function(T value) transform) {
    if (isSuccess) {
      return transform(value as T);
    } else {
      return Result.failure(error!);
    }
  }

  @override
  String toString() {
    return isSuccess ? 'Result.success($value)' : 'Result.failure($error)';
  }
}
