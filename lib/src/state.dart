/// High-level lifecycle status of a query.
enum QueryStatus { idle, loading, error, success }

/// Network/IO status for a fetch operation.
enum FetchStatus { idle, fetching, paused }

/// Serializable state container for [Query].
class QueryState<TData, TError> {
  /// Latest successfully resolved data.
  final TData? data;

  /// Latest error thrown by a fetch attempt.
  final TError? error;

  /// Timestamp for the last successful data update.
  final DateTime? dataUpdatedAt;

  /// Timestamp for the last error update.
  final DateTime? errorUpdatedAt;

  /// High-level status of the query.
  final QueryStatus status;

  /// Fetch status (e.g. currently fetching).
  final FetchStatus fetchStatus;

  const QueryState({
    this.data,
    this.error,
    this.dataUpdatedAt,
    this.errorUpdatedAt,
    this.status = QueryStatus.idle,
    this.fetchStatus = FetchStatus.idle,
  });

  /// True when [status] is [QueryStatus.loading].
  bool get isLoading => status == QueryStatus.loading;

  /// True when [status] is [QueryStatus.error].
  bool get isError => status == QueryStatus.error;

  /// True when [status] is [QueryStatus.success].
  bool get isSuccess => status == QueryStatus.success;

  /// True when [fetchStatus] is [FetchStatus.fetching].
  bool get isFetching => fetchStatus == FetchStatus.fetching;

  /// Returns a new state with updated fields.
  QueryState<TData, TError> copyWith({
    TData? data,
    TError? error,
    DateTime? dataUpdatedAt,
    DateTime? errorUpdatedAt,
    QueryStatus? status,
    FetchStatus? fetchStatus,
    bool forceClearError = false,
  }) {
    return QueryState(
      data: data ?? this.data,
      error: forceClearError ? null : (error ?? this.error),
      dataUpdatedAt: dataUpdatedAt ?? this.dataUpdatedAt,
      errorUpdatedAt: errorUpdatedAt ?? this.errorUpdatedAt,
      status: status ?? this.status,
      fetchStatus: fetchStatus ?? this.fetchStatus,
    );
  }
}

/// High-level lifecycle status of a mutation.
enum MutationStatus { idle, loading, error, success }

/// Serializable state container for [Mutation].
class MutationState<TData, TError, TVariables> {
  /// Latest successfully resolved data.
  final TData? data;

  /// Latest error thrown by a mutation attempt.
  final TError? error;

  /// Variables passed to the most recent mutation attempt.
  final TVariables? variables;

  /// High-level status of the mutation.
  final MutationStatus status;

  const MutationState({
    this.data,
    this.error,
    this.variables,
    this.status = MutationStatus.idle,
  });

  /// True when [status] is [MutationStatus.idle].
  bool get isIdle => status == MutationStatus.idle;

  /// True when [status] is [MutationStatus.loading].
  bool get isLoading => status == MutationStatus.loading;

  /// True when [status] is [MutationStatus.error].
  bool get isError => status == MutationStatus.error;

  /// True when [status] is [MutationStatus.success].
  bool get isSuccess => status == MutationStatus.success;

  /// Returns a new state with updated fields.
  MutationState<TData, TError, TVariables> copyWith({
    TData? data,
    TError? error,
    TVariables? variables,
    MutationStatus? status,
    bool forceClearError = false,
  }) {
    return MutationState(
      data: data ?? this.data,
      error: forceClearError ? null : (error ?? this.error),
      variables: variables ?? this.variables,
      status: status ?? this.status,
    );
  }
}
