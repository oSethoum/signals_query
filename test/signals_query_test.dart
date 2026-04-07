import 'package:flutter_test/flutter_test.dart';
import 'package:signals_query/signals_query.dart';

Future<void> _flushMicrotasks() async {
  // `createQuery`/`createInfiniteQuery` schedule fetches via `Future.microtask`.
  // Pumping the event queue twice is usually enough for those microtasks to run
  // and for the async fetch body to start.
  await pumpEventQueue(times: 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Query', () {
    test('caches queries by queryKey within a client', () async {
      final client = QueryClient();
      addTearDown(client.dispose);

      final useGreetingQuery = createQuery<String, String>(
        (name) => QueryOptions(
          queryKey: ['greeting', name],
          queryFn: () async => 'hello $name',
        ),
        client: client,
      );

      final q1 = useGreetingQuery('alice');
      final q2 = useGreetingQuery('alice');
      final q3 = useGreetingQuery('bob');

      expect(identical(q1, q2), isTrue);
      expect(identical(q1, q3), isFalse);
    });

    test('retries then succeeds', () async {
      final client = QueryClient();
      addTearDown(client.dispose);

      var attempts = 0;
      final useRetryQuery = createQuery<String, Null>(
        (_) => QueryOptions<String>(
          queryKey: const ['retry'],
          retry: 1,
          retryDelay: Duration.zero,
          queryFn: () async {
            attempts++;
            if (attempts == 1) throw Exception('fail once');
            return 'ok';
          },
        ),
        client: client,
      );

      final query = useRetryQuery(null);
      await query.fetch();

      expect(query.isSuccess, isTrue);
      expect(query.data, 'ok');
      expect(attempts, 2);
    });
  });

  group('Mutation', () {
    test('mutate updates state and calls callbacks', () async {
      final calls = <String>[];

      final useSaveMutation = createMutation<String, Exception, String>(
        () => MutationOptions<String, Exception, String>(
          mutationFn: (value) async {
            calls.add('fn:$value');
            return 'saved:$value';
          },
          onMutate: (value) => calls.add('mutate:$value'),
          onSuccess: (data, value) => calls.add('success:$data:$value'),
          onSettled: (data, err, value) =>
              calls.add('settled:${data ?? "null"}:${err ?? "null"}:$value'),
        ),
      );

      final mutation = useSaveMutation();
      final result = await mutation.mutate('x');

      expect(result, 'saved:x');
      expect(mutation.isSuccess, isTrue);
      expect(mutation.data, 'saved:x');
      expect(
        calls,
        [
          'mutate:x',
          'fn:x',
          'success:saved:x:x',
          'settled:saved:x:null:x',
        ],
      );
    });

    test('mutate error sets error and calls onError/onSettled', () async {
      final calls = <String>[];

      final useFailMutation = createMutation<String, StateError, int>(
        () => MutationOptions<String, StateError, int>(
          mutationFn: (v) async {
            throw StateError('bad:$v');
          },
          onError: (e, v) => calls.add('error:${e.message}:$v'),
          onSettled: (data, err, v) =>
              calls.add('settled:${data ?? "null"}:${err?.message}:$v'),
        ),
      );

      final mutation = useFailMutation();
      final result = await mutation.mutate(7);

      expect(result, isNull);
      expect(mutation.isError, isTrue);
      expect(mutation.error, isA<StateError>());
      expect(calls, ['error:bad:7:7', 'settled:null:bad:7:7']);
    });
  });

  group('InfiniteQuery', () {
    test('fetch then fetchNextPage accumulates pages and updates hasNextPage',
        () async {
      final client = QueryClient();
      addTearDown(client.dispose);

      final useNumbers = createInfiniteQuery<int, Null, int>(
        (_) => InfiniteQueryOptions<int, int>(
          queryKey: const ['numbers'],
          initialPageParam: 0,
          queryFn: (pageParam) async => pageParam ?? 0,
          getNextPageParam: (lastPage, allPages) =>
              lastPage >= 2 ? null : lastPage + 1,
        ),
        client: client,
      );

      final query = useNumbers(null);

      await query.fetch();
      expect(query.pages, [0]);
      expect(query.hasNextPage, isTrue);

      await query.fetchNextPage();
      expect(query.pages, [0, 1]);
      expect(query.hasNextPage, isTrue);

      await query.fetchNextPage();
      expect(query.pages, [0, 1, 2]);
      expect(query.hasNextPage, isFalse);
    });

    test('factory schedules an initial fetch when enabled and stale', () async {
      final client = QueryClient();
      addTearDown(client.dispose);

      var called = 0;
      final useAuto = createInfiniteQuery<int, Null, int>(
        (_) => InfiniteQueryOptions<int, int>(
          queryKey: const ['auto'],
          initialPageParam: 1,
          queryFn: (pageParam) async {
            called++;
            return pageParam ?? 0;
          },
          getNextPageParam: (lastPage, allPages) => null,
        ),
        client: client,
      );

      final query = useAuto(null);
      await _flushMicrotasks();

      expect(called, 1);
      expect(query.pages, [1]);
      expect(query.isSuccess, isTrue);
    });
  });
}

