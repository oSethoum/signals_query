import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'state.dart';
import 'options.dart';

class Query<TData, TError> {
  final List<dynamic> queryKey;
  final String queryHash;

  Signal<QueryState<TData, TError>> state;

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

  void dispose() {
    _isDisposed = true;
    _clearGcTimer();
    onDispose?.call();
  }

  void Function()? onDispose;

  TData? get data => state.value.data;
  TError? get error => state.value.error;
  bool get isLoading => state.value.isLoading;
  bool get isError => state.value.isError;
  bool get isSuccess => state.value.isSuccess;
  bool get isFetching => state.value.isFetching;
}
