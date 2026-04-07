## 1.0.0

* Initial release of signals_query.
* Pure Flutter widget implementation.
* Added support for standard QueryBuilder and MutationBuilder.
* Added support for Paginated fetch via InfiniteQueryBuilder.
* Hooks-free controller patterns available out of the box (QueryController, MutationController).

## 1.1.1

* Documentation: Added dartdoc across the public API (`Query`, `InfiniteQuery`, `Mutation`, options, state, `QueryClient`, factory functions, and library overview). API reference is suitable for pub.dev and local `dart doc` output.

## 1.1.0

* README: Added an example integration with `infinite_scroll_pagination` using `createInfiniteQuery`.
* Tests: Added baseline unit/widget tests for Query, Mutation, and InfiniteQuery behavior.
* Fix: Prevented concurrent modification in `QueryClient.dispose()` by disposing cached queries from a snapshot.
