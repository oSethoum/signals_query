import 'dart:async';

typedef QueryFn<TData> = Future<TData> Function();
typedef MutationFn<TData, TVariables> =
    Future<TData> Function(TVariables variables);

class QueryOptions<TData> {
  final List<dynamic> queryKey;
  final QueryFn<TData> queryFn;
  final Duration staleTime;
  final Duration gcTime;
  final bool enabled;
  final TData? initialData;
  final Duration? initialDataUpdatedAt;
  final TData? placeholderData;
  final bool keepPreviousData;
  final bool refetchOnWindowFocus;
  final int retry;
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

class MutationOptions<TData, TError, TVariables> {
  final List<dynamic>? mutationKey;
  final MutationFn<TData, TVariables> mutationFn;
  final void Function(TData data, TVariables variables)? onSuccess;
  final void Function(TError error, TVariables variables)? onError;
  final void Function(TVariables variables)? onMutate;
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
