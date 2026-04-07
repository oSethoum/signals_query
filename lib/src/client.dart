import 'package:flutter/widgets.dart';
import 'query.dart';
import 'options.dart';
import 'state.dart';
import 'infinite_query.dart';

final queryClient = QueryClient();

String hashQueryKey(List<dynamic> key) {
  return key.map((e) => e.toString()).join('\$\$\$');
}

bool matchQueryKey(List<dynamic> targetKey, List<dynamic> partialKey) {
  if (partialKey.length > targetKey.length) return false;
  for (int i = 0; i < partialKey.length; i++) {
    if (partialKey[i] != targetKey[i]) return false;
  }
  return true;
}

class QueryClient extends WidgetsBindingObserver {
  final Map<String, Query> _queries = {};
  final Map<String, InfiniteQuery> _infiniteQueries = {};

  QueryClient() {
    WidgetsBinding.instance.addObserver(this);
  }

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

  TData? getQueryData<TData>(List<dynamic> queryKey) {
    final hash = hashQueryKey(queryKey);
    final query = _queries[hash] as Query<TData, dynamic>?;
    return query?.state.peek().data;
  }
}

class QueryClientProvider extends InheritedWidget {
  final QueryClient client;

  const QueryClientProvider({
    super.key,
    required this.client,
    required super.child,
  });

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
