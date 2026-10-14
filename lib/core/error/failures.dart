abstract class Failure {
  final String message;
  final Object? cause;

  const Failure(this.message, [this.cause]);

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' (Cause: $cause)' : ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          cause == other.cause;

  @override
  int get hashCode => Object.hash(runtimeType, message, cause);
}

class PlatformFailure extends Failure {
  const PlatformFailure(super.message, [super.cause]);
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, [super.cause]);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message, [super.cause]);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, [super.cause]);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, [super.cause]);
}
