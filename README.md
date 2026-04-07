# signals_query

A Flutter package that mirrors TanStack Query (React Query) features, powered by [Signals](https://pub.dev/packages/signals).

It provides an asynchronous state management and data-fetching solution for Flutter applications. We bypass complicated widgets, contexts, hooks, and builders, replacing them with a sleek functional API!

## Features

- **Query & Mutation**: Fetch and mutate data seamlessly via globally typed functions.
- **Infinite Queries**: Paginated and infinite scroll APIs natively supported.
- **Cache Management**: Garbage collection and cache invalidation using TanStack style array keys.
- **Data Persistence**: `keepPreviousData`, `initialData`, and `placeholderData` options to prevent loading flashes.
- **Signals Powered**: Reactive and performant UI rebuilding utilizing pure Signals! No hook-builders!

## Initialization

By default, an integrated global `queryClient` exists so you don't actually *need* to initialize anything. However, if you'd like to provide a custom client to the functions instead, that works too!

## Basic Usage

### `createQuery` functional factories

Define your queries elegantly outside your widget hierarchy, generating a declarative "factory" function. When you need the query data in a widget, just call the function and natively `Watch` it:

```dart
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:signals_query/signals_query.dart';

// 1. Define your Query factory:
final useUserQuery = createQuery<String, String>((userId) => QueryOptions(
  queryKey: ['user', userId],
  queryFn: () async {
    await Future.delayed(const Duration(seconds: 2));
    return 'Loaded User: \$userId';
  },
));

class QueryExample extends StatelessWidget {
  const QueryExample({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. Call the query factory with your variables
    final query = useUserQuery('u_123');

    // 3. Watch the state perfectly without boilerplate!
    return Watch((context) {
      if (query.isLoading) return const CircularProgressIndicator();
      if (query.isError) return Text('Error: \${query.error}');

      return Column(
         children: [
           Text('Data: \${query.data}'),
           ElevatedButton(
             onPressed: () => query.fetch(),
             child: const Text('Refresh'),
           ),
         ],
      );
    });
  }
}
```

### `createMutation`

The `createMutation` approach is essentially the same, offering a typed functional API for side effects:

```dart
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:signals_query/signals_query.dart';

// 1. Create your mutation globally
final useSaveMutation = createMutation<String, Exception, String>(() => MutationOptions(
  mutationFn: (variables) async {
    await Future.delayed(const Duration(seconds: 1));
    return "Saved \$variables!";
  },
  onSuccess: (data, variables) {
    // You can access the global queryClient or invalidate your keys directly
    queryClient.invalidateQueries(['user']);
  },
));

class MutationExample extends StatelessWidget {
  const MutationExample({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. Access the mutation instance
    final mutation = useSaveMutation();

    return Watch((context) {
      return ElevatedButton(
        onPressed: () => mutation.mutate('New Data'),
        child: mutation.isLoading
            ? const CircularProgressIndicator()
            : const Text('Save Data safely without classes/hooks'),
      );
    });
  }
}
```

## Usage with `infinite_scroll_pagination`

`signals_query` infinite queries map nicely to [`infinite_scroll_pagination`](https://pub.dev/packages/infinite_scroll_pagination): you let the `PagingController` request a page key, then call `query.fetch()` (first page) / `query.fetchNextPage()` (next pages), and finally `appendPage` / `appendLastPage`.

```dart
import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:signals_query/signals_query.dart';

class User {
  final String id;
  final String name;
  const User({required this.id, required this.name});
}

class UsersPage {
  final List<User> items;
  final String? nextCursor;
  const UsersPage({required this.items, required this.nextCursor});
}

// Define the infinite query factory globally.
final useUsersInfiniteQuery = createInfiniteQuery<UsersPage, Null, String>(
  (_) => InfiniteQueryOptions<UsersPage, String>(
    queryKey: const ['users'],
    initialPageParam: null, // first page has no cursor
    queryFn: (cursor) async {
      // Fetch your page here. `cursor` is null for the first page.
      // Return a page object that includes both items and next cursor.
      await Future.delayed(const Duration(milliseconds: 300));
      final start = cursor == null ? 0 : int.parse(cursor);
      final items = List.generate(
        20,
        (i) => User(id: 'u_${start + i}', name: 'User ${start + i}'),
      );
      final next = (start + items.length) >= 100 ? null : '${start + items.length}';
      return UsersPage(items: items, nextCursor: next);
    },
    getNextPageParam: (lastPage, allPages) => lastPage.nextCursor,
  ),
);

class UsersPagedList extends StatefulWidget {
  const UsersPagedList({super.key});

  @override
  State<UsersPagedList> createState() => _UsersPagedListState();
}

class _UsersPagedListState extends State<UsersPagedList> {
  final _pagingController = PagingController<String?, User>(firstPageKey: null);

  @override
  void initState() {
    super.initState();
    _pagingController.addPageRequestListener((pageKey) async {
      try {
        final query = useUsersInfiniteQuery(null);

        if (pageKey == _pagingController.firstPageKey) {
          await query.fetch();
        } else {
          await query.fetchNextPage();
        }

        final lastPage = query.pages?.isNotEmpty == true ? query.pages!.last : null;
        if (lastPage == null) return;

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
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the query so error/loading state stays reactive.
    final query = useUsersInfiniteQuery(null);

    return Watch((context) {
      return RefreshIndicator(
        onRefresh: () async {
          queryClient.invalidateQueries(const ['users']);
          _pagingController.refresh();
        },
        child: PagedListView<String?, User>(
          pagingController: _pagingController,
          builderDelegate: PagedChildBuilderDelegate<User>(
            itemBuilder: (context, item, index) => ListTile(
              title: Text(item.name),
              subtitle: Text(item.id),
            ),
            firstPageProgressIndicatorBuilder: (_) =>
                query.isLoading ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
            newPageProgressIndicatorBuilder: (_) =>
                query.isFetchingNextPage ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
          ),
        ),
      );
    });
  }
}
```
