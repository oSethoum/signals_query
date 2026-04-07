import 'dart:async';

/// Function used by a [QueryOptions] to fetch data.
typedef QueryFn<TData> = Future<TData> Function();

/// Function used by a [MutationOptions] to perform a side effect.
typedef MutationFn<TData, TVariables> =
    Future<TData> Function(TVariables variables);

/// Configuration for a single cached query.
///
/// Queries are uniquely identified by [queryKey]. The [queryFn] is invoked by
/// [Query.fetch] (and may be invoked automatically when a query is created and
/// considered stale).
class QueryOptions<TData> {
  /// Cache key for this query.
  final List<dynamic> queryKey;

  /// Async function that returns the query data.
  final QueryFn<TData> queryFn;

  /// Duration after which cached data is considered stale.
  final Duration staleTime;

  /// Garbage collection time once there are no observers.
  final Duration gcTime;

  /// When false, the query will not auto-fetch.
  final bool enabled;

  /// Optional initial value for [Query.data].
  final TData? initialData;

  /// Treat [initialData] as if it was updated this long ago.
  final Duration? initialDataUpdatedAt;

  /// Optional placeholder value (for UI) while loading.
  final TData? placeholderData;

  /// Whether to keep the previous data during refetches.
  final bool keepPreviousData;

  /// Whether to refetch when the app is resumed.
  final bool refetchOnWindowFocus;

  /// Number of retry attempts when [queryFn] throws.
  final int retry;

  /// Delay between retry attempts.
  final Duration retryDelay;

  const QueryOptions({
    required this.queryKey,
    required this.queryFn,
    this.staleTime = Duration.zero,
    this.gcTime = const Duration(minutes: 5),
    this.enabled = true,
    this.initialData,
    this.initialDataUpdatedAt,
    this.placeholderData,
    this.keepPreviousData = false,
    this.refetchOnWindowFocus = true,
    this.retry = 3,
    this.retryDelay = const Duration(seconds: 1),
  });
}

/// Configuration for a mutation (side effect).
///
/// Mutations are not cached globally like queries, but can be created via
/// [createMutation] which keeps a single instance per factory.
class MutationOptions<TData, TError, TVariables> {
  /// Optional key used to identify the mutation (not currently used for caching).
  final List<dynamic>? mutationKey;

  /// Async function that performs the mutation.
  final MutationFn<TData, TVariables> mutationFn;

  /// Called when [mutationFn] completes successfully.
  final void Function(TData data, TVariables variables)? onSuccess;

  /// Called when [mutationFn] throws.
  final void Function(TError error, TVariables variables)? onError;

  /// Called before [mutationFn] is executed.
  final void Function(TVariables variables)? onMutate;

  /// Called after completion, whether success or error.
  final void Function(TData? data, TError? error, TVariables variables)?
  onSettled;

  const MutationOptions({
    this.mutationKey,
    required this.mutationFn,
    this.onSuccess,
    this.onError,
    this.onMutate,
    this.onSettled,
  });
}
