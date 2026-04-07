import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'state.dart';
import 'client.dart';

/// Function used by an [InfiniteQueryOptions] to fetch a page.
typedef InfiniteQueryFn<TData, TPageParam> =
    Future<TData> Function(TPageParam? pageParam);

/// Configuration for an infinite (paginated) query.
///
/// Pages are fetched using [queryFn] and appended via [InfiniteQuery.fetchNextPage].
/// Pagination is controlled by [getNextPageParam] (and optionally [getPreviousPageParam]).
class InfiniteQueryOptions<TData, TPageParam> {
  /// Cache key for this query.
  final List<dynamic> queryKey;

  /// Async function that returns a page. Receives the current page param.
  final InfiniteQueryFn<TData, TPageParam> queryFn;

  /// Page param for the initial fetch.
  final TPageParam? initialPageParam;

  /// Returns the next page param, or `null` when there are no more pages.
  final TPageParam? Function(TData lastPage, List<TData> allPages)
  getNextPageParam;

  /// Returns the previous page param, or `null` when there are no previous pages.
  final TPageParam? Function(TData firstPage, List<TData> allPages)?
  getPreviousPageParam;

  /// Duration after which cached data is considered stale.
  final Duration staleTime;

  /// Garbage collection time once there are no observers.
  final Duration gcTime;

  /// When false, the query will not auto-fetch.
  final bool enabled;

  /// Whether to refetch when the app is resumed.
  final bool refetchOnWindowFocus;

  /// Number of retry attempts when [queryFn] throws (initial fetch only).
  final int retry;

  /// Delay between retry attempts.
  final Duration retryDelay;

  const InfiniteQueryOptions({
    required this.queryKey,
    required this.queryFn,
    this.initialPageParam,
    required this.getNextPageParam,
    this.getPreviousPageParam,
    this.staleTime = Duration.zero,
    this.gcTime = const Duration(minutes: 5),
    this.enabled = true,
    this.refetchOnWindowFocus = true,
    this.retry = 3,
    this.retryDelay = const Duration(seconds: 1),
  });
}

/// Serializable state container for [InfiniteQuery].
class InfiniteQueryState<TData, TError, TPageParam> {
  /// Loaded pages in order.
  final List<TData>? pages;

  /// Page params corresponding to [pages].
  final List<TPageParam?>? pageParams;

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

  /// True while fetching the next page.
  final bool isFetchingNextPage;

  /// True while fetching the previous page.
  final bool isFetchingPreviousPage;

  /// Whether [InfiniteQuery.fetchNextPage] should be allowed.
  final bool hasNextPage;

  /// Whether a previous page is available (reserved for future support).
  final bool hasPreviousPage;

  const InfiniteQueryState({
    this.pages,
    this.pageParams,
    this.error,
    this.dataUpdatedAt,
    this.errorUpdatedAt,
    this.status = QueryStatus.idle,
    this.fetchStatus = FetchStatus.idle,
    this.isFetchingNextPage = false,
    this.isFetchingPreviousPage = false,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
  });

  bool get isLoading => status == QueryStatus.loading;
  bool get isError => status == QueryStatus.error;
  bool get isSuccess => status == QueryStatus.success;
  bool get isFetching => fetchStatus == FetchStatus.fetching;

  /// Returns a new state with updated fields.
  InfiniteQueryState<TData, TError, TPageParam> copyWith({
    List<TData>? pages,
    List<TPageParam?>? pageParams,
    TError? error,
    DateTime? dataUpdatedAt,
    DateTime? errorUpdatedAt,
    QueryStatus? status,
    FetchStatus? fetchStatus,
    bool? isFetchingNextPage,
    bool? isFetchingPreviousPage,
    bool? hasNextPage,
    bool? hasPreviousPage,
    bool forceClearError = false,
  }) {
    return InfiniteQueryState(
      pages: pages ?? this.pages,
      pageParams: pageParams ?? this.pageParams,
      error: forceClearError ? null : (error ?? this.error),
      dataUpdatedAt: dataUpdatedAt ?? this.dataUpdatedAt,
      errorUpdatedAt: errorUpdatedAt ?? this.errorUpdatedAt,
      status: status ?? this.status,
      fetchStatus: fetchStatus ?? this.fetchStatus,
      isFetchingNextPage: isFetchingNextPage ?? this.isFetchingNextPage,
      isFetchingPreviousPage:
          isFetchingPreviousPage ?? this.isFetchingPreviousPage,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      hasPreviousPage: hasPreviousPage ?? this.hasPreviousPage,
    );
  }
}

/// A cached paginated query whose state is stored in a [Signal].
///
/// Instances are created and cached by [QueryClient] using [InfiniteQueryOptions.queryKey].
class InfiniteQuery<TData, TError, TPageParam> {
  /// Cache key for this query.
  final List<dynamic> queryKey;

  /// Stable hash derived from [queryKey].
  final String queryHash;

  /// Current options (may be replaced when the query factory is called again).
  InfiniteQueryOptions<TData, TPageParam> options;

  /// Reactive state for this infinite query.
  final Signal<InfiniteQueryState<TData, TError, TPageParam>> state;

  /// Convenience access to the loaded pages.
  List<TData>? get pages => state.value.pages;

  /// Convenience access to page params.
  List<TPageParam?>? get pageParams => state.value.pageParams;

  /// Latest error.
  TError? get error => state.value.error;

  /// True when the query is in the loading state.
  bool get isLoading => state.value.isLoading;

  /// True when the query is in the error state.
  bool get isError => state.value.isError;

  /// True when the query is in the success state.
  bool get isSuccess => state.value.isSuccess;

  /// True when any fetch is in progress.
  bool get isFetching => state.value.isFetching;

  /// True when the next page is being fetched.
  bool get isFetchingNextPage => state.value.isFetchingNextPage;

  /// Whether a next page is available.
  bool get hasNextPage => state.value.hasNextPage;

  Timer? _gcTimer;
  int _observersCount = 0;
  bool _isDisposed = false;

  InfiniteQuery({
    required this.queryKey,
    required this.queryHash,
    required this.options,
  }) : state = signal(InfiniteQueryState<TData, TError, TPageParam>());

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

  /// Fetch the first page and reset pages/pageParams.
  Future<void> fetch() async {
    if (state.peek().fetchStatus == FetchStatus.fetching &&
        !state.peek().isFetchingNextPage &&
        !state.peek().isFetchingPreviousPage) {
      return;
    }

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
        final data = await options.queryFn(options.initialPageParam);
        if (_isDisposed) return;

        final pages = [data];
        final pageParams = [options.initialPageParam];

        final hasNextPage = options.getNextPageParam(data, pages) != null;
        final hasPreviousPage =
            options.getPreviousPageParam?.call(data, pages) != null;

        state.value = state.peek().copyWith(
          pages: pages,
          pageParams: pageParams,
          dataUpdatedAt: DateTime.now(),
          status: QueryStatus.success,
          fetchStatus: FetchStatus.idle,
          hasNextPage: hasNextPage,
          hasPreviousPage: hasPreviousPage,
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
          await Future.delayed(options.retryDelay);
        }
      }
    }
  }

  /// Fetch the next page and append it to [pages].
  Future<void> fetchNextPage() async {
    if (state.peek().isFetchingNextPage ||
        !state.peek().hasNextPage ||
        state.peek().status != QueryStatus.success) {
      return;
    }

    final pages = state.peek().pages ?? [];
    final pageParams = state.peek().pageParams ?? [];
    final lastPage = pages.last;

    final nextPageParam = options.getNextPageParam(lastPage, pages);
    if (nextPageParam == null) return;

    state.value = state.peek().copyWith(
      isFetchingNextPage: true,
      fetchStatus: FetchStatus.fetching,
      forceClearError: true,
    );

    try {
      final data = await options.queryFn(nextPageParam);
      if (_isDisposed) return;

      final newPages = [...pages, data];
      final newPageParams = [...pageParams, nextPageParam];

      final hasNextPage = options.getNextPageParam(data, newPages) != null;

      state.value = state.peek().copyWith(
        pages: newPages,
        pageParams: newPageParams,
        dataUpdatedAt: DateTime.now(),
        fetchStatus: FetchStatus.idle,
        isFetchingNextPage: false,
        hasNextPage: hasNextPage,
      );
    } catch (error) {
      if (_isDisposed) return;
      state.value = state.peek().copyWith(
        error: error as TError,
        errorUpdatedAt: DateTime.now(),
        fetchStatus: FetchStatus.idle,
        isFetchingNextPage: false,
      );
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

  void dispose() {
    _isDisposed = true;
    _clearGcTimer();
    onDispose?.call();
  }

  /// Called when this query is disposed (used internally by the cache).
  void Function()? onDispose;
}

/// Creates a typed infinite query factory function.
///
/// The returned function:
/// - Builds [InfiniteQueryOptions] from your `variables`
/// - Returns a cached [InfiniteQuery] instance keyed by [InfiniteQueryOptions.queryKey]
/// - Optionally triggers an async fetch when `enabled && stale`
InfiniteQuery<TData, dynamic, TPageParam> Function(TVariables) createInfiniteQuery<TData, TVariables, TPageParam>(
  InfiniteQueryOptions<TData, TPageParam> Function(TVariables) optionsBuilder, {
  QueryClient? client,
}) {
  return (TVariables variables) {
    final activeClient = client ?? queryClient;
    final options = optionsBuilder(variables);
    final query = activeClient.createInfiniteQuery<TData, TPageParam>(options);

    if (options.enabled && query.isStale) {
      Future.microtask(() => query.fetch());
    }

    return query;
  };
}
