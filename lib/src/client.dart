import 'package:flutter/widgets.dart';
import 'query.dart';
import 'options.dart';
import 'state.dart';
import 'infinite_query.dart';

/// Global default [QueryClient] used by the factory functions when no client is
/// provided.
final queryClient = QueryClient();

/// Computes a stable hash string for a [QueryOptions.queryKey].
String hashQueryKey(List<dynamic> key) {
  return key.map((e) => e.toString()).join('\$\$\$');
}

/// Returns true when [partialKey] matches the start of [targetKey].
bool matchQueryKey(List<dynamic> targetKey, List<dynamic> partialKey) {
  if (partialKey.length > targetKey.length) return false;
  for (int i = 0; i < partialKey.length; i++) {
    if (partialKey[i] != targetKey[i]) return false;
  }
  return true;
}

/// Central cache and lifecycle manager for queries and infinite queries.
///
/// - Caches queries by their key hash.
/// - Provides invalidation helpers.
/// - Optionally refetches stale queries when the app resumes.
class QueryClient extends WidgetsBindingObserver {
  final Map<String, Query> _queries = {};
  final Map<String, InfiniteQuery> _infiniteQueries = {};

  /// Creates a client and registers a lifecycle observer.
  QueryClient() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Disposes cached queries and unregisters the lifecycle observer.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Disposing queries can synchronously remove themselves from the cache via
    // `onDispose`, so iterate over a snapshot to avoid concurrent modification.
    for (final query in _queries.values.toList()) {
      query.dispose();
    }
    _queries.clear();
    for (final query in _infiniteQueries.values.toList()) {
      query.dispose();
    }
    _infiniteQueries.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final query in _queries.values) {
        if (query.options.refetchOnWindowFocus &&
            query.isStale &&
            query.options.enabled) {
          query.fetch();
        }
      }
      for (final query in _infiniteQueries.values) {
        if (query.options.refetchOnWindowFocus &&
            query.isStale &&
            query.options.enabled) {
          query.fetch();
        }
      }
    }
  }

  /// Returns a cached [Query] for [QueryOptions.queryKey], creating it if needed.
  Query<TData, dynamic> createQuery<TData>(QueryOptions<TData> options) {
    final hash = hashQueryKey(options.queryKey);
    var query = _queries[hash] as Query<TData, dynamic>?;
    if (query == null) {
      query = Query<TData, dynamic>(
        queryKey: options.queryKey,
        queryHash: hash,
        options: options,
      );
      query.onDispose = () {
        _queries.remove(hash);
      };
      _queries[hash] = query;
    } else {
      query.options = options;
    }
    return query;
  }

  /// Returns a cached [InfiniteQuery] for [InfiniteQueryOptions.queryKey], creating it if needed.
  InfiniteQuery<TData, dynamic, TPageParam> createInfiniteQuery<
    TData,
    TPageParam
  >(InfiniteQueryOptions<TData, TPageParam> options) {
    final hash = hashQueryKey(options.queryKey);
    var query =
        _infiniteQueries[hash] as InfiniteQuery<TData, dynamic, TPageParam>?;
    if (query == null) {
      query = InfiniteQuery<TData, dynamic, TPageParam>(
        queryKey: options.queryKey,
        queryHash: hash,
        options: options,
      );
      query.onDispose = () {
        _infiniteQueries.remove(hash);
      };
      _infiniteQueries[hash] = query;
    } else {
      query.options = options;
    }
    return query;
  }

  /// Refetches all cached queries that match [queryKey].
  ///
  /// When [exact] is false (default), [queryKey] is treated as a prefix.
  void invalidateQueries(List<dynamic> queryKey, {bool exact = false}) {
    for (final query in _queries.values) {
      if (exact) {
        if (hashQueryKey(query.queryKey) == hashQueryKey(queryKey)) {
          query.fetch();
        }
      } else {
        if (matchQueryKey(query.queryKey, queryKey)) {
          query.fetch();
        }
      }
    }
    for (final query in _infiniteQueries.values) {
      if (exact) {
        if (hashQueryKey(query.queryKey) == hashQueryKey(queryKey)) {
          query.fetch();
        }
      } else {
        if (matchQueryKey(query.queryKey, queryKey)) {
          query.fetch();
        }
      }
    }
  }

  /// Refetches all cached queries for which [match] returns true.
  void invalidateQueryMatch(bool Function(List<dynamic> key) match) {
    for (final query in _queries.values) {
      if (match(query.queryKey)) {
        query.fetch();
      }
    }
    for (final query in _infiniteQueries.values) {
      if (match(query.queryKey)) {
        query.fetch();
      }
    }
  }

  /// Overwrites the cached data for an existing query.
  void setQueryData<TData>(List<dynamic> queryKey, TData data) {
    final hash = hashQueryKey(queryKey);
    final query = _queries[hash] as Query<TData, dynamic>?;
    if (query != null) {
      query.state.value = query.state.peek().copyWith(
        data: data,
        dataUpdatedAt: DateTime.now(),
        status: QueryStatus.success,
      );
    }
  }

  /// Returns cached data for [queryKey], or `null` if missing.
  TData? getQueryData<TData>(List<dynamic> queryKey) {
    final hash = hashQueryKey(queryKey);
    final query = _queries[hash] as Query<TData, dynamic>?;
    return query?.state.peek().data;
  }
}

/// Provides a [QueryClient] to a widget subtree.
///
/// Note: the current factory helpers default to the global [queryClient]. Use
/// this widget when you want to pass a custom [QueryClient] through the widget
/// tree for your own integration code.
class QueryClientProvider extends InheritedWidget {
  final QueryClient client;

  const QueryClientProvider({
    super.key,
    required this.client,
    required super.child,
  });

  /// Returns the nearest [QueryClientProvider] in the widget tree.
  static QueryClient of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<QueryClientProvider>();
    assert(provider != null, 'No QueryClientProvider found in context.');
    return provider!.client;
  }

  @override
  bool updateShouldNotify(QueryClientProvider oldWidget) {
    return client != oldWidget.client;
  }
}
