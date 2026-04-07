import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'state.dart';
import 'options.dart';

class Mutation<TData, TError, TVariables> {
  MutationOptions<TData, TError, TVariables> options;
  final Signal<MutationState<TData, TError, TVariables>> state;

  TData? get data => state.value.data;
  TError? get error => state.value.error;
  bool get isLoading => state.value.status == MutationStatus.loading;
  bool get isError => state.value.status == MutationStatus.error;
  bool get isSuccess => state.value.status == MutationStatus.success;

  Mutation({required this.options})
    : state = signal(
        MutationState<TData, TError, TVariables>(status: MutationStatus.idle),
      );

  Future<TData?> mutate(TVariables variables) async {
    state.value = state.peek().copyWith(
      status: MutationStatus.loading,
      variables: variables,
      forceClearError: true,
    );

    options.onMutate?.call(variables);

    try {
      final data = await options.mutationFn(variables);
      state.value = state.peek().copyWith(
        data: data,
        status: MutationStatus.success,
        forceClearError: true,
      );
      options.onSuccess?.call(data, variables);
      options.onSettled?.call(data, null, variables);
      return data;
    } catch (e) {
      final error = e as TError;
      state.value = state.peek().copyWith(
        error: error,
        status: MutationStatus.error,
      );
      options.onError?.call(error, variables);
      options.onSettled?.call(null, error, variables);
      return null;
    }
  }
}

Mutation<TData, TError, TVariables> Function() createMutation<TData, TError, TVariables>(
  MutationOptions<TData, TError, TVariables> Function() options,
) {
  Mutation<TData, TError, TVariables>? cache;
  return () {
    if (cache == null) {
      cache = Mutation<TData, TError, TVariables>(options: options());
    } else {
      cache!.options = options();
    }
    return cache!;
  };
}
