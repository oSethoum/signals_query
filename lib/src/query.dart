import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'state.dart';
import 'options.dart';
import 'client.dart';

/// A cached async query whose state is stored in a [Signal].
///
/// Instances are created and cached by [QueryClient] using [QueryOptions.queryKey].
/// Most apps should create typed factory functions via [createQuery] and call
/// them from widgets.
class Query<TData, TError> {
  /// Cache key for this query.
  final List<dynamic> queryKey;

  /// Stable hash derived from [queryKey].
  final String queryHash;

  /// Reactive state for this query.
  Signal<QueryState<TData, TError>> state;

  /// Current options (may be replaced when the query factory is called again).
  QueryOptions<TData> options;
  Timer? _gcTimer;
  int _observersCount = 0;
  bool _isDisposed = false;

  Query({
    required this.queryKey,
    required this.queryHash,
    required this.options,
  }) : state = signal(
         QueryState<TData, TError>(
           data: options.initialData,
           status: options.initialData != null
               ? QueryStatus.success
               : QueryStatus.idle,
           dataUpdatedAt: options.initialDataUpdatedAt != null
               ? DateTime.now().subtract(options.initialDataUpdatedAt!)
               : (options.initialData != null ? DateTime.now() : null),
         ),
       );

  /// Register an observer to delay garbage collection.
  void addObserver() {
    _observersCount++;
    _clearGcTimer();
  }

  /// Unregister an observer and schedule garbage collection when unused.
  void removeObserver() {
    _observersCount--;
    if (_observersCount <= 0) {
      _scheduleGc();
    }
  }

  /// Whether this query should be considered stale.
  bool get isStale {
    if (state.peek().dataUpdatedAt == null) return true;
    final staleTime = options.staleTime;
    final difference = DateTime.now().difference(state.peek().dataUpdatedAt!);
    return difference >= staleTime;
  }

  /// Fetch the latest data and update [state].
  ///
  /// If already fetching, subsequent calls are ignored.
  Future<void> fetch() async {
    if (state.peek().fetchStatus == FetchStatus.fetching) return;

    state.value = state.peek().copyWith(
      fetchStatus: FetchStatus.fetching,
      status: state.peek().status == QueryStatus.idle
          ? QueryStatus.loading
          : state.peek().status,
      forceClearError: true,
    );

    int attempts = 0;
    while (attempts <= options.retry) {
      try {
        final data = await options.queryFn();
        if (_isDisposed) return;
        state.value = state.peek().copyWith(
          data: data,
          dataUpdatedAt: DateTime.now(),
          status: QueryStatus.success,
          fetchStatus: FetchStatus.idle,
          forceClearError: true,
        );
        return;
      } catch (error) {
        if (_isDisposed) return;
        attempts++;
        if (attempts > options.retry) {
          state.value = state.peek().copyWith(
            error: error as TError,
            errorUpdatedAt: DateTime.now(),
            status: QueryStatus.error,
            fetchStatus: FetchStatus.idle,
          );
          return;
        } else {
          // Wait before retry
          await Future.delayed(options.retryDelay);
        }
      }
    }
  }

  void _scheduleGc() {
    _clearGcTimer();
    _gcTimer = Timer(options.gcTime, () {
      if (_observersCount <= 0) {
        dispose();
      }
    });
  }

  void _clearGcTimer() {
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  /// Dispose the query and invoke [onDispose] (used by [QueryClient] to evict).
  void dispose() {
    _isDisposed = true;
    _clearGcTimer();
    onDispose?.call();
  }

  /// Called when this query is disposed (used internally by the cache).
  void Function()? onDispose;

  /// Latest data.
  TData? get data => state.value.data;

  /// Latest error.
  TError? get error => state.value.error;

  /// True when the query is in the loading state.
  bool get isLoading => state.value.isLoading;

  /// True when the query is in the error state.
  bool get isError => state.value.isError;

  /// True when the query is in the success state.
  bool get isSuccess => state.value.isSuccess;

  /// True when a fetch is in progress.
  bool get isFetching => state.value.isFetching;
}

/// Creates a typed query factory function.
///
/// The returned function:
/// - Builds [QueryOptions] from your `variables`
/// - Returns a cached [Query] instance keyed by [QueryOptions.queryKey]
/// - Optionally triggers an async fetch when `enabled && stale`
///
/// Typical usage is to define the factory at the top-level:
///
/// ```dart
/// final useUserQuery = createQuery<User, String>((id) => QueryOptions(
///   queryKey: ['user', id],
///   queryFn: () => api.fetchUser(id),
/// ));
/// ```
Query<TData, dynamic> Function(TVariables) createQuery<TData, TVariables>(
  QueryOptions<TData> Function(TVariables) optionsBuilder, {
  QueryClient? client,
}) {
  return (TVariables variables) {
    final activeClient = client ?? queryClient;
    final options = optionsBuilder(variables);
    final query = activeClient.createQuery<TData>(options);

    if (options.enabled && query.isStale) {
      Future.microtask(() => query.fetch());
    }

    return query;
  };
}
