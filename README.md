# signals_query

A Flutter package that mirrors TanStack Query (React Query) features, powered by [Signals](https://pub.dev/packages/signals).

It provides an asynchronous state management and data-fetching solution for Flutter applications. We bypass complicated widgets, contexts, hooks, and builders, replacing them with a sleek reactive API!

## Features

- **Query & Mutation**: Fetch and mutate data seamlessly.
- **Cache Management**: Cache data manually or let `QueryClient` manage it.
- **Signals Powered**: Reactive and performant UI rebuilding utilizing pure Signals! No hook-builders!

## Initialization

First, initialize a `QueryClient` that utilizes a `Cache` implementation (e.g., `MemoryCache`):

```dart
import 'package:signals_query/signals_query.dart';

final queryClient = QueryClient(cache: MemoryCache());
```

## Basic Usage

### `createQuery`

Define your query elegantly and natively `Watch` it:

```dart
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:signals_query/signals_query.dart';

// Assuming you have a globally defined queryClient
// final queryClient = QueryClient(cache: MemoryCache());

class QueryExample extends StatefulWidget {
  const QueryExample({super.key});

  @override
  State<QueryExample> createState() => _QueryExampleState();
}

class _QueryExampleState extends State<QueryExample> {
  late final Query<String> userQuery;

  @override
  void initState() {
    super.initState();
    // 1. Create your Query instance
    userQuery = createQuery<String>(
      client: queryClient,
      key: () => ['user', 'u_123'],
      fn: () async {
        await Future.delayed(const Duration(seconds: 2));
        return 'Loaded User: u_123';
      },
    );
  }

  @override
  void dispose() {
    userQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2. Watch the state perfectly without boilerplate!
    return Watch((context) {
      if (userQuery.isLoading) return const CircularProgressIndicator();
      if (userQuery.state.value.isError) return Text('Error: ${userQuery.state.value.error}');

      return Column(
         children: [
           Text('Data: ${userQuery.data}'),
           ElevatedButton(
             onPressed: () => userQuery.refetch(),
             child: const Text('Refresh'),
           ),
         ],
      );
    });
  }
}
```

### `createMutation`

The `createMutation` offers a typed functional API for side effects. Mutations do not run immediately, but instead trigger when you call `.mutate()`:

```dart
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:signals_query/signals_query.dart';

class MutationExample extends StatefulWidget {
  const MutationExample({super.key});

  @override
  State<MutationExample> createState() => _MutationExampleState();
}

class _MutationExampleState extends State<MutationExample> {
  late final Mutation<String, String> saveMutation;

  @override
  void initState() {
    super.initState();
    // 1. Create your mutation
    saveMutation = createMutation<String, String>(
      client: queryClient,
      fn: (variables) async {
        await Future.delayed(const Duration(seconds: 1));
        return "Saved $variables!";
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final result = await saveMutation.mutate('New Data');
              if (result != null) {
                // You can access the global queryClient or invalidate your keys directly
                queryClient.invalidateQuery(['user', 'u_123']);
              }
            },
            child: saveMutation.isLoading.value
                ? const CircularProgressIndicator()
                : const Text('Save Data'),
          ),
          if (saveMutation.data.value != null)
            Text('Result: ${saveMutation.data.value}'),
        ],
      );
    });
  }
}
```

## Usage with `infinite_scroll_pagination`

`signals_query` seamlessly blends with `infinite_scroll_pagination`. Additionally, by incorporating a `Signal` inside your `key` array, your entire infinite query setup can reactively reset and refetch from the beginning automatically whenever that parameter/signal changes!

```dart
import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:signals_query/signals_query.dart';

// Assuming you have a global client
// final queryClient = QueryClient(cache: MemoryCache());

class UsersPage {
  final List<String> items;
  final String? nextCursor;
  const UsersPage({required this.items, this.nextCursor});
}

class UsersPagedList extends StatefulWidget {
  const UsersPagedList({super.key});

  @override
  State<UsersPagedList> createState() => _UsersPagedListState();
}

class _UsersPagedListState extends State<UsersPagedList> {
  final _pagingController = PagingController<String?, String>(firstPageKey: null);
  late final InfiniteQuery<UsersPage, String> usersQuery;
  
  // Example of a reactive dependency: a Signal inside your key function
  final filterSignal = signal<String>('active');

  @override
  void initState() {
    super.initState();
    
    // 1. Create the infinite query. Notice the signal in the key array!
    usersQuery = createInfiniteQuery<UsersPage, String>(
      client: queryClient,
      key: () => ['users', filterSignal.value],
      initialPageParam: null,
      fn: (cursor) async {
        await Future.delayed(const Duration(milliseconds: 300));
        
        final start = cursor == null ? 0 : int.parse(cursor);
        final items = List.generate(20, (i) => 'User ${start + i} (${filterSignal.value})');
        final next = (start + items.length) >= 100 ? null : '${start + items.length}';
        
        return UsersPage(items: items, nextCursor: next);
      },
      getNextPageParam: (lastPage, allPages) => lastPage.nextCursor,
    );

    // 2. Bind the PagingController
    _pagingController.addPageRequestListener((pageKey) async {
      try {
        if (pageKey != _pagingController.firstPageKey) {
          await usersQuery.fetchNextPage();
        }

        final pages = usersQuery.pages;
        if (pages.isEmpty) return; // Still running initial fetch
        
        final lastPage = pages.last;
        final newItems = lastPage.items;
        final nextKey = lastPage.nextCursor;

        if (nextKey == null) {
          _pagingController.appendLastPage(newItems);
        } else {
          _pagingController.appendPage(newItems, nextKey);
        }
      } catch (e) {
        _pagingController.error = e;
      }
    });
    
    // 3. Reactively reset the pagination visually when the query fundamentally resets due to a dependency changing
    effect(() {
        // Read the state so the effect subscribes
        final state = usersQuery.state.value;
        if (state.isLoading && state.pages.isEmpty) {
           _pagingController.refresh();
        }
    });
  }

  @override
  void dispose() {
    _pagingController.dispose();
    usersQuery.dispose();
    filterSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
       return Scaffold(
         appBar: AppBar(
           title: const Text('Infinite Users'),
           actions: [
             IconButton(
               icon: const Icon(Icons.change_circle),
               // Changing this signal triggers the QueryClient to automatically
               // invalidate, dispose of the old stream, and re-run initial fetch! 
               onPressed: () => filterSignal.value = filterSignal.value == 'active' ? 'archived' : 'active', 
             )
           ]
         ),
         body: PagedListView<String?, String>(
           pagingController: _pagingController,
           builderDelegate: PagedChildBuilderDelegate<String>(
             itemBuilder: (context, item, index) => ListTile(title: Text(item)),
             firstPageProgressIndicatorBuilder: (_) =>
                 usersQuery.isLoading ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
             newPageProgressIndicatorBuilder: (_) =>
                 usersQuery.isFetchingNextPage ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
           ),
         ),
       );
    });
  }
}
```
