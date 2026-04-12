## 1.2.1

* Fix: Resolved major signal GC memory leaks within sibling query invalidations.
* Fix: Query & InfiniteQuery now natively serialize their states back from cached history upon boot.
* Feature: Extended MemoryCache logic to self-destruct stale elements upon getter access dynamically.
* Feature: Added `.dispose()` method securely to Mutations.

## 1.2.0

* Documentation: Added `infinite_scroll_pagination` usage with `createInfiniteQuery` back into README.md.
* Feature: Re-added `createInfiniteQuery` functional API for endless scrolling.

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
