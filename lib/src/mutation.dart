import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'state.dart';
import 'options.dart';

/// A mutation (side effect) whose state is stored in a [Signal].
///
/// Mutations are typically created via [createMutation] to get a stable instance
/// that can be used across rebuilds.
class Mutation<TData, TError, TVariables> {
  /// Current options (may be replaced when the mutation factory is called again).
  MutationOptions<TData, TError, TVariables> options;

  /// Reactive state for this mutation.
  final Signal<MutationState<TData, TError, TVariables>> state;

  /// Latest data.
  TData? get data => state.value.data;

  /// Latest error.
  TError? get error => state.value.error;

  /// True when a mutation is in progress.
  bool get isLoading => state.value.status == MutationStatus.loading;

  /// True when the mutation is in the error state.
  bool get isError => state.value.status == MutationStatus.error;

  /// True when the mutation is in the success state.
  bool get isSuccess => state.value.status == MutationStatus.success;

  Mutation({required this.options})
    : state = signal(
        MutationState<TData, TError, TVariables>(status: MutationStatus.idle),
      );

  /// Execute the mutation with [variables] and update [state].
  ///
  /// Returns the resolved data on success, or `null` on error.
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

/// Creates a typed mutation factory function.
///
/// The returned function caches a single [Mutation] instance and updates its
/// [Mutation.options] on subsequent calls.
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
