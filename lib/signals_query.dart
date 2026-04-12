/// A lightweight, Signals-powered data-fetching library for Flutter.
///
/// It provides an asynchronous state management and data-fetching solution 
/// inspired by React Query, bypassing complicated widgets, contexts, 
/// hooks, and builders, replacing them with a sleek reactive API!
library signals_query;

import 'dart:async';
import 'dart:convert';

import 'package:signals/signals.dart';

/// Represents an entry in the cache.
class CacheEntry<T> {
  /// The stored data.
  final T data;

  /// The timestamp when the data was last updated.
  final DateTime updatedAt;

  /// The time-to-live duration for this entry.
  final Duration? ttl;

  /// Creates a new cache entry.
  CacheEntry({required this.data, required this.updatedAt, this.ttl});

  /// Returns true if the cache entry has expired according to its `ttl`.
  bool get isStale {
    if (ttl == null) return false;
    return DateTime.now().difference(updatedAt) > ttl!;
  }
}

/// Abstract base class for a cache store.
abstract class Cache {
  /// Retrieves a value from the cache by its [key].
  CacheEntry<T>? get<T>(String key);

  /// Stores a [data] value in the cache with the given [key] and optional [ttl].
  void set<T>(String key, T data, {Duration? ttl});

  /// Deletes an entry from the cache by its [key].
  void delete(String key);

  /// Deletes entries from the cache that match the given [predicate].
  void deleteWhere(bool Function(String key) predicate);

  /// Clears all entries from the cache.
  void clear();

  /// Retrieves an iterable of all keys currently in the cache.
  Iterable<String> get keys;
}

/// An in-memory implementation of the [Cache].
class MemoryCache implements Cache {
  final Map<String, CacheEntry<dynamic>> _store = {};

  @override
  CacheEntry<T>? get<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    return entry as CacheEntry<T>;
  }

  @override
  void set<T>(String key, T data, {Duration? ttl}) {
    _store[key] = CacheEntry<T>(
      data: data,
      updatedAt: DateTime.now(),
      ttl: ttl,
    );
  }

  @override
  void delete(String key) => _store.remove(key);

  @override
  void deleteWhere(bool Function(String key) predicate) {
    _store.removeWhere((k, _) => predicate(k));
  }

  @override
  void clear() => _store.clear();

  @override
  Iterable<String> get keys => _store.keys;
}

/// Serializes a list of dynamic values into a string key for caching.
///
/// Maps are sorted by key to ensure robust and consistent matching.
String serializeKey(List<dynamic> key) {
  String encode(dynamic value) {
    if (value is Map) {
      final sorted = Map.fromEntries(
        value.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString())),
      );
      return jsonEncode(sorted);
    }
    return jsonEncode(value);
  }

  return key.map(encode).join('|');
}

/// Represents the current status of a query.
enum QueryStatus { 
  /// The query is currently idle (e.g., initial state).
  idle, 
  
  /// The query is actively fetching data for the first time.
  loading, 
  
  /// The query has successfully fetched data.
  success, 
  
  /// The query has encountered an error.
  error 
}

/// The state of a particular query holding its status, data, and metadata.
class QueryState<T> {
  /// The fetched data, if any.
  final T? data;

  /// The error object if the query failed.
  final Object? error;

  /// The stack trace if the query failed.
  final StackTrace? stackTrace;

  /// The overarching status of the query.
  final QueryStatus status;

  /// Indicates if the query is currently actively fetching data, including refetches.
  final bool isFetching;

  /// The timestamp when the query was last successfully updated.
  final DateTime? updatedAt;

  /// Creates a new query state.
  const QueryState({
    this.data,
    this.error,
    this.stackTrace,
    this.status = QueryStatus.idle,
    this.isFetching = false,
    this.updatedAt,
  });

  /// Quick accessor to check if the query is in the `loading` status.
  bool get isLoading => status == QueryStatus.loading;

  /// Quick accessor to check if the query is in the `success` status.
  bool get isSuccess => status == QueryStatus.success;

  /// Quick accessor to check if the query is in the `error` status.
  bool get isError => status == QueryStatus.error;

  /// Creates a copy of the query state with updated properties.
  QueryState<T> copyWith({
    T? data,
    Object? error,
    StackTrace? stackTrace,
    QueryStatus? status,
    bool? isFetching,
    DateTime? updatedAt,
    bool clearError = false,
  }) {
    return QueryState<T>(
      data: data ?? this.data,
      error: clearError ? null : (error ?? this.error),
      stackTrace: clearError ? null : (stackTrace ?? this.stackTrace),
      status: status ?? this.status,
      isFetching: isFetching ?? this.isFetching,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// The client that manages queries, caching, and invalidation.
class QueryClient {
  /// The cache implementation used by the client.
  final Cache cache;

  /// The default time-to-live for cache entries.
  final Duration? defaultTtl;

  /// The default duration before cached data is considered stale.
  final Duration defaultStaleTime;

  final Map<String, Signal<int>> _invalidations = {};
  final Map<String, dynamic> _active = {};

  /// Creates a query client.
  QueryClient({
    required this.cache,
    this.defaultTtl,
    this.defaultStaleTime = Duration.zero,
  });

  /// Returns an invalidation signal for a given [key].
  ///
  /// The query relies on the invalidation signal's value to trigger refetches.
  Signal<int> invalidationSignalFor(String key) {
    return _invalidations.putIfAbsent(key, () => signal(0));
  }

  /// Invalidates queries matching the given [key].
  ///
  /// This bumps the invalidation signal, triggering registered queries to refetch.
  void invalidateQuery(List<dynamic> key) {
    final k = serializeKey(key);
    _invalidations[k]?.value++;
  }

  /// Internal method to register an active query.
  /// @nodoc
  void register(String key, dynamic q) => _active[key] = q;

  /// Internal method to unregister a query when disposed.
  /// @nodoc
  void unregister(String key) {
    _active.remove(key);
    _invalidations.remove(key)?.dispose();
  }
}

/// A proactive query instance that manages the fetching and caching of data.
class Query<T> {
  /// The overarching query client.
  final QueryClient client;

  /// The function that generates the unique cache key for this query.
  final List<dynamic> Function() keyFn;

  /// The asynchronous operation that fetches the data.
  final Future<T> Function() fn;

  /// Indicates whether the previous data should be kept while fetching new data.
  final bool keepPreviousData;

  /// The number of times to automatically retry the query on failure.
  final int retryCount;

  /// The delay between retries.
  final Duration retryDelay;

  late final Signal<QueryState<T>> _state;
  late final Signal<T?> _previous;

  late final EffectCleanup _effect;

  bool _disposed = false;
  bool _fetching = false;

  Query._({
    required this.client,
    required this.keyFn,
    required this.fn,
    this.keepPreviousData = false,
    this.retryCount = 0,
    this.retryDelay = const Duration(milliseconds: 500),
  }) {
    final key = serializeKey(keyFn());

    _state = signal(QueryState<T>());
    _previous = signal<T?>(null);

    final invalidation = client.invalidationSignalFor(key);

    Future<void> runFetch() async {
      if (_disposed || _fetching) return;

      _fetching = true;

      _state.value = _state.value.copyWith(
        status: QueryStatus.loading,
        isFetching: true,
        clearError: true,
      );

      Object? lastError;
      StackTrace? lastStack;

      for (int i = 0; i <= retryCount; i++) {
        try {
          if (i > 0) {
            await Future.delayed(retryDelay * i);
          }

          final result = await fn();

          if (_disposed) return;

          _previous.value = result;

          client.cache.set<T>(key, result, ttl: client.defaultTtl);

          _state.value = QueryState<T>(
            data: result,
            status: QueryStatus.success,
            isFetching: false,
            updatedAt: DateTime.now(),
          );

          _fetching = false;
          return;
        } catch (e, st) {
          lastError = e;
          lastStack = st;
        }
      }

      if (_disposed) return;

      _state.value = _state.value.copyWith(
        error: lastError,
        stackTrace: lastStack,
        status: QueryStatus.error,
        isFetching: false,
      );

      _fetching = false;
    }

    _effect = effect(() {
      // dependency tracking ONLY
      invalidation.value;
      keyFn();

      Future.microtask(runFetch);
    });

    client.register(key, this);
  }

  /// A readonly signal providing the current state of the query.
  ReadonlySignal<QueryState<T>> get state => _state;

  /// The current data of the query (if any).
  T? get data => _state.value.data;

  /// True if the query is currently loading.
  bool get isLoading => _state.value.isLoading;

  /// Triggers a manual refetch of the data.
  void refetch() {
    client.invalidateQuery(keyFn());
  }

  /// Cleans up resources, disposing signals and unregistering from the client.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _effect();
    _state.dispose();
    _previous.dispose();
    client.unregister(serializeKey(keyFn()));
  }
}

/// A proactive mutation instance that encapsulates state for side-effects.
class Mutation<T, P> {
  /// The overarching query client.
  final QueryClient client;

  /// The mutation function that performs the side effect with parameters [P].
  final Future<T> Function(P params) fn;

  late final Signal<bool> _loading = signal(false);
  late final Signal<T?> _data = signal(null);
  late final Signal<Object?> _error = signal(null);

  Mutation._({required this.client, required this.fn});

  /// Exposes safely whether the mutation is currently executing.
  ReadonlySignal<bool> get isLoading => _loading;

  /// Exposes the resultant data of a successful mutation.
  ReadonlySignal<T?> get data => _data;

  /// Exposes the error if a mutation fails.
  ReadonlySignal<Object?> get error => _error;

  /// Executes the mutation with the given [params].
  Future<T?> mutate(P params) async {
    _loading.value = true;
    _error.value = null;

    try {
      final res = await fn(params);
      _data.value = res;
      return res;
    } catch (e) {
      _error.value = e;
      return null;
    } finally {
      _loading.value = false;
    }
  }
}

/// Factory helper to create a new [Query].
///
/// Uses the provided [client] to manage caching and the query lifecycle. 
/// The [key] function generates a unique identifier used to cache the result, 
/// and [fn] is the asynchronous operation that actually fetches the data. 
/// 
/// Set [keepPreviousData] to true to avoid nullifying data while fetching anew.
/// You can configure automatic retries on failure using [retryCount] and [retryDelay].
Query<T> createQuery<T>({
  required QueryClient client,
  required List<dynamic> Function() key,
  required Future<T> Function() fn,
  bool keepPreviousData = false,
  int retryCount = 0,
  Duration retryDelay = const Duration(milliseconds: 500),
}) {
  return Query<T>._(
    client: client,
    keyFn: key,
    fn: fn,
    keepPreviousData: keepPreviousData,
    retryCount: retryCount,
    retryDelay: retryDelay,
  );
}

/// Factory helper to create a new [Mutation].
///
/// Uses the provided [client] for integrating with the query ecosystem. 
/// The [fn] handles the underlying asynchronous side-effect.
Mutation<T, P> createMutation<T, P>({
  required QueryClient client,
  required Future<T> Function(P params) fn,
}) {
  return Mutation<T, P>._(
    client: client,
    fn: fn,
  );
}

/// The state of a paginated/infinite query.
class InfiniteQueryState<TData, TPageParam> {
  /// The accumulated pages of data.
  final List<TData> pages;
  /// The parameter strings/ints corresponding to each fetched page.
  final List<TPageParam> pageParams;
  /// Current error if one occurred.
  final Object? error;
  /// Global query status.
  final QueryStatus status;
  /// Whether it is fetching right now (initial, next page, or refetch).
  final bool isFetching;
  /// Specifically whether the next page is currently being fetched.
  final bool isFetchingNextPage;
  /// Flag to determine if more pages exist.
  final bool hasNextPage;

  /// Creates a new infinite query state.
  const InfiniteQueryState({
    this.pages = const [],
    this.pageParams = const [],
    this.error,
    this.status = QueryStatus.idle,
    this.isFetching = false,
    this.isFetchingNextPage = false,
    this.hasNextPage = false,
  });

  /// Quick accessor to check if the query is in the `loading` status.
  bool get isLoading => status == QueryStatus.loading;

  /// Quick accessor to check if the query is in the `success` status.
  bool get isSuccess => status == QueryStatus.success;

  /// Quick accessor to check if the query is in the `error` status.
  bool get isError => status == QueryStatus.error;

  /// Copies the state with optionally newly assigned values.
  InfiniteQueryState<TData, TPageParam> copyWith({
    List<TData>? pages,
    List<TPageParam>? pageParams,
    Object? error,
    QueryStatus? status,
    bool? isFetching,
    bool? isFetchingNextPage,
    bool? hasNextPage,
    bool clearError = false,
  }) {
    return InfiniteQueryState<TData, TPageParam>(
      pages: pages ?? this.pages,
      pageParams: pageParams ?? this.pageParams,
      error: clearError ? null : (error ?? this.error),
      status: status ?? this.status,
      isFetching: isFetching ?? this.isFetching,
      isFetchingNextPage: isFetchingNextPage ?? this.isFetchingNextPage,
      hasNextPage: hasNextPage ?? this.hasNextPage,
    );
  }
}

/// A sequential query that fetches pages of data seamlessly.
class InfiniteQuery<TData, TPageParam> {
  /// The overarching query client.
  final QueryClient client;
  
  /// Generates the base cache key for the query series.
  final List<dynamic> Function() keyFn;

  /// The async operation that fetches the individual page depending on [pageParam].
  final Future<TData> Function(TPageParam? pageParam) fn;

  /// Optional initial pagination variable/cursor.
  final TPageParam? initialPageParam;

  /// Given the current cursor and all pages, determine the cursor for the next page.
  final TPageParam? Function(TData lastPage, List<TData> allPages) getNextPageParam;

  late final Signal<InfiniteQueryState<TData, TPageParam>> _state;
  late final EffectCleanup _effect;
  bool _disposed = false;
  bool _fetching = false;

  InfiniteQuery._({
    required this.client,
    required this.keyFn,
    required this.fn,
    this.initialPageParam,
    required this.getNextPageParam,
  }) {
    final key = serializeKey(keyFn());
    _state = signal(InfiniteQueryState<TData, TPageParam>());
    final invalidation = client.invalidationSignalFor(key);

    Future<void> runFetch() async {
      if (_disposed || _fetching) return;
      _fetching = true;

      _state.value = _state.value.copyWith(
        status: QueryStatus.loading,
        isFetching: true,
        clearError: true,
      );

      try {
        final result = await fn(initialPageParam);
        if (_disposed) return;

        final nextParam = getNextPageParam(result, [result]);

        _state.value = InfiniteQueryState<TData, TPageParam>(
          pages: [result],
          pageParams: [if (initialPageParam != null) initialPageParam as TPageParam],
          status: QueryStatus.success,
          isFetching: false,
          isFetchingNextPage: false,
          hasNextPage: nextParam != null,
        );
      } catch (e) {
        if (_disposed) return;
        _state.value = _state.value.copyWith(
          status: QueryStatus.error,
          error: e,
          isFetching: false,
        );
      }
      _fetching = false;
    }

    _effect = effect(() {
      invalidation.value;
      keyFn();
      Future.microtask(runFetch);
    });

    client.register(key, this);
  }

  /// Exposes the paginated query's state block.
  ReadonlySignal<InfiniteQueryState<TData, TPageParam>> get state => _state;
  
  /// Whether the absolute first load is processing.
  bool get isLoading => _state.value.isLoading;
  
  /// Whether it is fetching a subsequent page specifically.
  bool get isFetchingNextPage => _state.value.isFetchingNextPage;
  
  /// Simple flag dictating whether another page supposedly exists.
  bool get hasNextPage => _state.value.hasNextPage;
  
  /// The raw pages of data.
  List<TData> get pages => _state.value.pages;

  /// Fetches the next sequential page via [getNextPageParam].
  Future<void> fetchNextPage() async {
    if (_disposed || _fetching || !hasNextPage) return;
    _fetching = true;

    _state.value = _state.value.copyWith(isFetchingNextPage: true);

    try {
      final nextParam = getNextPageParam(_state.value.pages.last, _state.value.pages);
      final result = await fn(nextParam);

      if (_disposed) return;

      final newPages = [..._state.value.pages, result];
      final newPageParams = [..._state.value.pageParams, if (nextParam != null) nextParam as TPageParam];
      final newNextParam = getNextPageParam(result, newPages);

      _state.value = _state.value.copyWith(
        pages: newPages,
        pageParams: newPageParams,
        isFetchingNextPage: false,
        hasNextPage: newNextParam != null,
      );
    } catch (e) {
      if (_disposed) return;
      _state.value = _state.value.copyWith(
        isFetchingNextPage: false,
      );
    }
    _fetching = false;
  }

  /// Triggers a hard refetch from the beginning.
  void refetch() {
    client.invalidateQuery(keyFn());
  }

  /// Disposes internal signal loops and cached dependencies.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _effect();
    _state.dispose();
    client.unregister(serializeKey(keyFn()));
  }
}

/// Factory helper to create a new [InfiniteQuery].
///
/// Uses the provided [client] to manage caching and lifecycle. The [key] function
/// generates a unique base identifier, and [fn] handles fetching individual pages.
/// The [getNextPageParam] callback determines how pagination moves forward utilizing
/// the last page.
InfiniteQuery<TData, TPageParam> createInfiniteQuery<TData, TPageParam>({
  required QueryClient client,
  required List<dynamic> Function() key,
  required Future<TData> Function(TPageParam? pageParam) fn,
  TPageParam? initialPageParam,
  required TPageParam? Function(TData lastPage, List<TData> allPages) getNextPageParam,
}) {
  return InfiniteQuery<TData, TPageParam>._(
    client: client,
    keyFn: key,
    fn: fn,
    initialPageParam: initialPageParam,
    getNextPageParam: getNextPageParam,
  );
}
