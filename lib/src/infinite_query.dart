import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'state.dart';
import 'client.dart';

typedef InfiniteQueryFn<TData, TPageParam> =
    Future<TData> Function(TPageParam? pageParam);

class InfiniteQueryOptions<TData, TPageParam> {
  final List<dynamic> queryKey;
  final InfiniteQueryFn<TData, TPageParam> queryFn;
  final TPageParam? initialPageParam;
  final TPageParam? Function(TData lastPage, List<TData> allPages)
  getNextPageParam;
  final TPageParam? Function(TData firstPage, List<TData> allPages)?
  getPreviousPageParam;
  final Duration staleTime;
  final Duration gcTime;
  final bool enabled;
  final bool refetchOnWindowFocus;
  final int retry;
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

class InfiniteQueryState<TData, TError, TPageParam> {
  final List<TData>? pages;
  final List<TPageParam?>? pageParams;
  final TError? error;
  final DateTime? dataUpdatedAt;
  final DateTime? errorUpdatedAt;
  final QueryStatus status;
  final FetchStatus fetchStatus;
  final bool isFetchingNextPage;
  final bool isFetchingPreviousPage;
  final bool hasNextPage;
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

class InfiniteQuery<TData, TError, TPageParam> {
  final List<dynamic> queryKey;
  final String queryHash;
  InfiniteQueryOptions<TData, TPageParam> options;

  final Signal<InfiniteQueryState<TData, TError, TPageParam>> state;

  List<TData>? get pages => state.value.pages;
  List<TPageParam?>? get pageParams => state.value.pageParams;
  TError? get error => state.value.error;
  bool get isLoading => state.value.isLoading;
  bool get isError => state.value.isError;
  bool get isSuccess => state.value.isSuccess;
  bool get isFetching => state.value.isFetching;
  bool get isFetchingNextPage => state.value.isFetchingNextPage;
  bool get hasNextPage => state.value.hasNextPage;

  Timer? _gcTimer;
  int _observersCount = 0;
  bool _isDisposed = false;

  InfiniteQuery({
    required this.queryKey,
    required this.queryHash,
    required this.options,
  }) : state = signal(InfiniteQueryState<TData, TError, TPageParam>());

  void addObserver() {
    _observersCount++;
    _clearGcTimer();
  }

  void removeObserver() {
    _observersCount--;
    if (_observersCount <= 0) {
      _scheduleGc();
    }
  }

  bool get isStale {
    if (state.peek().dataUpdatedAt == null) return true;
    final staleTime = options.staleTime;
    final difference = DateTime.now().difference(state.peek().dataUpdatedAt!);
    return difference >= staleTime;
  }

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

  void Function()? onDispose;
}

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
