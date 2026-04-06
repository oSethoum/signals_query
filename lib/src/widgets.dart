import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'client.dart';
import 'options.dart';
import 'query.dart';
import 'state.dart';
import 'mutation.dart';
import 'infinite_query.dart';

class QueryController {
  Future<void> Function()? _refetch;

  Future<void> refetch() async {
    await _refetch?.call();
  }
}

class MutationController<TVariables, TData> {
  Future<TData?> Function(TVariables)? _mutate;

  Future<TData?> mutate(TVariables variables) async {
    return await _mutate?.call(variables);
  }
}

class InfiniteQueryController {
  Future<void> Function()? _fetchNextPage;
  Future<void> Function()? _refetch;

  Future<void> fetchNextPage() async {
    await _fetchNextPage?.call();
  }

  Future<void> refetch() async {
    await _refetch?.call();
  }
}

class QueryBuilder<TData> extends StatefulWidget {
  final QueryOptions<TData> options;
  final QueryController? controller;
  final Widget Function(
    BuildContext context,
    QueryState<TData, dynamic> state,
    Future<void> Function() refetch,
  )
  builder;

  const QueryBuilder({
    super.key,
    required this.options,
    this.controller,
    required this.builder,
  });

  @override
  State<QueryBuilder<TData>> createState() => _QueryBuilderState<TData>();
}

class _QueryBuilderState<TData> extends State<QueryBuilder<TData>> {
  late Query<TData, dynamic> _query;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final client = QueryClientProvider.of(context);
      _query = client.createQuery<TData>(widget.options);
      _query.addObserver();

      if (widget.options.enabled && _query.isStale) {
        _query.fetch();
      }

      widget.controller?._refetch = _query.fetch;
      _initialized = true;
    }
  }

  @override
  void didUpdateWidget(QueryBuilder<TData> oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller?._refetch = _query.fetch;
    if (hashQueryKey(widget.options.queryKey) !=
        hashQueryKey(oldWidget.options.queryKey)) {
      _query.removeObserver();

      final client = QueryClientProvider.of(context);
      _query = client.createQuery<TData>(widget.options);
      _query.addObserver();

      if (widget.options.enabled && _query.isStale) {
        _query.fetch();
      }
    } else {
      _query.options = widget.options;
    }
  }

  @override
  void dispose() {
    _query.removeObserver();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final state = _query.state.value;
      return widget.builder(context, state, _query.fetch);
    });
  }
}

class MutationBuilder<TData, TError, TVariables> extends StatefulWidget {
  final MutationOptions<TData, TError, TVariables> options;
  final MutationController<TVariables, TData>? controller;
  final Widget Function(
    BuildContext context,
    MutationState<TData, TError, TVariables> state,
    Future<TData?> Function(TVariables variables) mutate,
  )
  builder;

  const MutationBuilder({
    super.key,
    required this.options,
    this.controller,
    required this.builder,
  });

  @override
  State<MutationBuilder<TData, TError, TVariables>> createState() =>
      _MutationBuilderState<TData, TError, TVariables>();
}

class _MutationBuilderState<TData, TError, TVariables>
    extends State<MutationBuilder<TData, TError, TVariables>> {
  late Mutation<TData, TError, TVariables> _mutation;

  @override
  void initState() {
    super.initState();
    _mutation = Mutation<TData, TError, TVariables>(options: widget.options);
    widget.controller?._mutate = _mutation.mutate;
  }

  @override
  void didUpdateWidget(MutationBuilder<TData, TError, TVariables> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _mutation.options = widget.options;
    widget.controller?._mutate = _mutation.mutate;
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final state = _mutation.state.value;
      return widget.builder(context, state, _mutation.mutate);
    });
  }
}

class InfiniteQueryBuilder<TData, TPageParam> extends StatefulWidget {
  final InfiniteQueryOptions<TData, TPageParam> options;
  final InfiniteQueryController? controller;
  final Widget Function(
    BuildContext context,
    InfiniteQueryState<TData, dynamic, TPageParam> state,
    Future<void> Function() fetchNextPage,
    Future<void> Function() refetch,
  )
  builder;

  const InfiniteQueryBuilder({
    super.key,
    required this.options,
    this.controller,
    required this.builder,
  });

  @override
  State<InfiniteQueryBuilder<TData, TPageParam>> createState() =>
      _InfiniteQueryBuilderState<TData, TPageParam>();
}

class _InfiniteQueryBuilderState<TData, TPageParam>
    extends State<InfiniteQueryBuilder<TData, TPageParam>> {
  late InfiniteQuery<TData, dynamic, TPageParam> _query;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final client = QueryClientProvider.of(context);
      _query = client.createInfiniteQuery<TData, TPageParam>(widget.options);
      _query.addObserver();

      if (widget.options.enabled && _query.isStale) {
        _query.fetch();
      }

      widget.controller?._fetchNextPage = _query.fetchNextPage;
      widget.controller?._refetch = _query.fetch;
      _initialized = true;
    }
  }

  @override
  void didUpdateWidget(InfiniteQueryBuilder<TData, TPageParam> oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller?._fetchNextPage = _query.fetchNextPage;
    widget.controller?._refetch = _query.fetch;
    if (hashQueryKey(widget.options.queryKey) !=
        hashQueryKey(oldWidget.options.queryKey)) {
      _query.removeObserver();

      final client = QueryClientProvider.of(context);
      _query = client.createInfiniteQuery<TData, TPageParam>(widget.options);
      _query.addObserver();

      if (widget.options.enabled && _query.isStale) {
        _query.fetch();
      }
    } else {
      _query.options = widget.options;
    }
  }

  @override
  void dispose() {
    _query.removeObserver();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final state = _query.state.value;
      return widget.builder(context, state, _query.fetchNextPage, _query.fetch);
    });
  }
}
