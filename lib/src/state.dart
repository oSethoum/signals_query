enum QueryStatus { idle, loading, error, success }

enum FetchStatus { idle, fetching, paused }

class QueryState<TData, TError> {
  final TData? data;
  final TError? error;
  final DateTime? dataUpdatedAt;
  final DateTime? errorUpdatedAt;
  final QueryStatus status;
  final FetchStatus fetchStatus;

  const QueryState({
    this.data,
    this.error,
    this.dataUpdatedAt,
    this.errorUpdatedAt,
    this.status = QueryStatus.idle,
    this.fetchStatus = FetchStatus.idle,
  });

  bool get isLoading => status == QueryStatus.loading;
  bool get isError => status == QueryStatus.error;
  bool get isSuccess => status == QueryStatus.success;
  bool get isFetching => fetchStatus == FetchStatus.fetching;

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

enum MutationStatus { idle, loading, error, success }

class MutationState<TData, TError, TVariables> {
  final TData? data;
  final TError? error;
  final TVariables? variables;
  final MutationStatus status;

  const MutationState({
    this.data,
    this.error,
    this.variables,
    this.status = MutationStatus.idle,
  });

  bool get isIdle => status == MutationStatus.idle;
  bool get isLoading => status == MutationStatus.loading;
  bool get isError => status == MutationStatus.error;
  bool get isSuccess => status == MutationStatus.success;

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
