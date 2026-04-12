import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_query/signals_query.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Query', () {
    test('fetches and caches data automatically', () async {
      final client = QueryClient(cache: MemoryCache());

      final query = createQuery<String>(
        client: client,
        key: () => ['greeting', 'alice'],
        fn: () async => 'hello alice',
      );

      // Initially idle
      expect(query.state.value.status, QueryStatus.idle);

      // Let the microtask queue run so it enters loading state
      await Future.microtask(() {});
      expect(query.isLoading, isTrue);

      // Wait for fetch to complete scheduling and execution
      await Future.delayed(const Duration(milliseconds: 50));

      expect(query.isLoading, isFalse);
      expect(query.data, 'hello alice');
      expect(query.state.value.status, QueryStatus.success);

      // Check cache
      final cached = client.cache.get<String>(serializeKey(['greeting', 'alice']));
      expect(cached?.data, 'hello alice');

      query.dispose();
    });

    test('retries then succeeds', () async {
      final client = QueryClient(cache: MemoryCache());

      var attempts = 0;
      
      final query = createQuery<String>(
        client: client,
        key: () => ['retry'],
        retryCount: 1,
        retryDelay: Duration.zero,
        fn: () async {
          attempts++;
          if (attempts == 1) throw Exception('fail once');
          return 'ok';
        },
      );

      // Wait for both attempts (initial + 1 retry).
      await Future.delayed(const Duration(milliseconds: 100));

      expect(query.isLoading, isFalse);
      expect(query.state.value.status, QueryStatus.success);
      expect(query.data, 'ok');
      expect(attempts, 2);

      query.dispose();
    });
  });

  group('Mutation', () {
    test('mutate updates state and returns result', () async {
      final client = QueryClient(cache: MemoryCache());
      final calls = <String>[];

      final mutation = createMutation<String, String>(
        client: client,
        fn: (value) async {
          calls.add('fn:$value');
          return 'saved:$value';
        },
      );

      final result = await mutation.mutate('x');

      expect(result, 'saved:x');
      expect(mutation.isLoading.value, isFalse);
      expect(mutation.data.value, 'saved:x');
      expect(calls, ['fn:x']);
    });

    test('mutate error sets error', () async {
       final client = QueryClient(cache: MemoryCache());

      final mutation = createMutation<String, int>(
        client: client,
        fn: (v) async {
          throw StateError('bad:$v');
        },
      );

      final result = await mutation.mutate(7);

      expect(result, isNull);
      expect(mutation.isLoading.value, isFalse);
      expect(mutation.error.value, isA<StateError>());
    });
  });
}
