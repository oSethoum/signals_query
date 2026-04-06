# signals_query

A Flutter package that mirrors TanStack Query (React Query) features, powered by [Signals](https://pub.dev/packages/signals).

It provides an asynchronous state management and data-fetching solution for Flutter applications, exclusively focused on robust integrations with standard **StatefulWidgets** and **StatelessWidgets**, without any dependency on hooks.

## Features

- **Query & Mutation**: Fetch and mutate data seamlessly.
- **Infinite Queries**: Paginated and infinite scroll APIs natively supported.
- **Cache Management**: Garbage collection and cache invalidation using TanStack style array keys.
- **Data Persistence**: `keepPreviousData`, `initialData`, and `placeholderData` options to prevent loading flashes.
- **Hooks-Free Controllers**: Create manageable query controllers directly connected to your native widget builders!
- **Signals Powered**: Reactive and performant UI rebuilding.

## Initialization

Wrap your app with `QueryClientProvider` containing a `QueryClient`:

```dart
import 'package:flutter/material.dart';
import 'package:signals_query/signals_query.dart';

final queryClient = QueryClient();

void main() {
  runApp(
    QueryClientProvider(
      client: queryClient,
      child: const MyApp(),
    )
  );
}
```

## Basic Usage

### Using the standard `QueryBuilder`

`QueryBuilder` automatically manages the entire query lifecycle, observing caches, cleaning up memory, and allowing you to just respond to state changes declaratively.

```dart
import 'package:flutter/material.dart';
import 'package:signals_query/signals_query.dart';

class BuilderExample extends StatelessWidget {
  const BuilderExample({super.key});

  @override
  Widget build(BuildContext context) {
    return QueryBuilder<String>(
      options: QueryOptions<String>(
        queryKey: ['hello_world'],
        queryFn: () async {
          await Future.delayed(const Duration(seconds: 2));
          return 'Hello from signals_query!';
        },
      ),
      builder: (context, state, refetch) {
        if (state.isLoading) return const CircularProgressIndicator();
        if (state.isError) return Text('Error: \${state.error}');

        return Column(
          children: [
            Text('Data: \${state.data}'),
            ElevatedButton(onPressed: refetch, child: const Text('Refresh'))
          ],
        );
      },
    );
  }
}
```

### The "Controller" API (Refetching outside of Builder bounds)

Usually, triggering a `refetch()` is scoped to the inside of the `builder` function. If you need to manipulate the query (like refetching) from outside of the builder scope blindly, instead of dealing with manual Cache Observers and GC lifecycles, you can instantiate a `QueryController` natively:

```dart
import 'package:flutter/material.dart';
import 'package:signals_query/signals_query.dart';

class ControllerExample extends StatelessWidget {
  // 1. Create a native Controller!
  final queryController = QueryController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 2. Pass the controller directly to the Builder!
        QueryBuilder<String>(
          controller: queryController,
          options: QueryOptions(
             queryKey: ['users'], 
             queryFn: () async => "Loaded user data",
          ),
          builder: (context, state, _) {
             if (state.isLoading) return CircularProgressIndicator();
             return Text(state.data ?? '');
          }
        ),

        // 3. Trigger a refetch flawlessly from a FloatingActionButton safely!
        FloatingActionButton(
           onPressed: () => queryController.refetch(),
           child: Icon(Icons.refresh),
        ),
      ]
    );
  }
}
```

### `MutationBuilder`

The `MutationBuilder` works essentially the same way to expose state and execution context for side-effects, and optionally supports `MutationController` too!

```dart
import 'package:flutter/material.dart';
import 'package:signals_query/signals_query.dart';

class MutationBuilderExample extends StatelessWidget {
  const MutationBuilderExample({super.key});

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);

    return MutationBuilder<String, Exception, String>(
      options: MutationOptions(
        mutationFn: (variables) async {
          await Future.delayed(const Duration(seconds: 1));
          return "Saved $variables";
        },
        onSuccess: (data, variables) {
          // Automatic cache invalidation matching specific arrays
          client.invalidateQueries(['hello_world']);
        },
      ),
      builder: (context, state, mutate) {
        return ElevatedButton(
          onPressed: () => mutate('New Data'),
          child: state.isLoading
              ? const CircularProgressIndicator()
              : const Text('Save Data safely without Hooks'),
        );
      },
    );
  }
}
```
