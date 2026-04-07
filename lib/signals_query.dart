/// `signals_query` is a lightweight, Signals-powered data-fetching library for
/// Flutter inspired by TanStack Query (React Query).
///
/// The public API is intentionally small:
///
/// - Use [createQuery] / [QueryOptions] for standard async fetching.
/// - Use [createInfiniteQuery] / [InfiniteQueryOptions] for pagination.
/// - Use [createMutation] / [MutationOptions] for side effects.
/// - Use [queryClient] / [QueryClient] for caching and invalidation.
///
/// Most usage patterns define query/mutation factories at the top-level and call
/// them from widgets. Returned objects are cached by their keys, so calling a
/// factory in `build()` is typically just a cache lookup.
export 'src/options.dart';
export 'src/state.dart';
export 'src/query.dart';
export 'src/infinite_query.dart';
export 'src/mutation.dart';
export 'src/client.dart';
