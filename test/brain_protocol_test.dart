import 'dart:convert';

import 'package:evaluetron_commander_app/src/data/brain_tls_transport.dart';
import 'package:evaluetron_commander_app/src/data/commander_brain_client.dart';
import 'package:evaluetron_commander_app/src/domain/brain_client.dart';
import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_brain_tls_transport.dart';
import 'support/fake_local_auth_gate.dart';
import 'support/memory_pin_store.dart';
import 'support/memory_secure_storage.dart';

const _deviceId = '12345678-1234-4123-8123-123456789abc';
const _enrollment =
    'evaluetron-commander://pair?v=1&brain=https%3A%2F%2Fbrain.example.com'
    '&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

BrainResponse _ok(String path) => switch (path) {
  '/api/commander/v1/pair' => jsonResponse({
    'ok': true,
    'apiVersion': 1,
    'device': {
      'id': _deviceId,
      'label': 'Test Commander',
      'scopes': ['brain:read', 'jobs:create'],
    },
  }),
  '/api/commander/v1/profile' => jsonResponse({
    'ok': true,
    'apiVersion': 1,
    'brain': {'name': 'Test Brain'},
    'device': {
      'id': _deviceId,
      'scopes': ['brain:read', 'jobs:create'],
    },
  }),
  '/api/commander/v1/catalog' => jsonResponse({
    'ok': true,
    'catalog': {
      'generators': [
        {
          'id': 'llm-grounded',
          'label': 'Grounded Answer',
          'output': 'text',
          'lede': 'A bounded answer',
          'estimatedCost': 3,
          'fields': [
            {'name': 'text', 'label': 'Question', 'placeholder': 'Ask'},
          ],
          'models': ['m1'],
        },
      ],
    },
  }),
  '/api/commander/v1/jobs' => jsonResponse({
    'ok': true,
    'job': {
      'id': 'job_1',
      'generator': 'llm-grounded',
      'status': 'queued',
      'createdAt': '2026-01-01T00:00:00Z',
      'owner': 'Operator',
    },
  }),
  _ => jsonResponse({'ok': false}, statusCode: 404),
};

Future<({CommanderBrainClient client, FakeBrainTlsTransport transport})>
_paired() async {
  final transport = FakeBrainTlsTransport(
    peer: await fakeCertificate(name: 'first'),
    respond: (method, path, body) => _ok(path),
  );
  final client = CommanderBrainClient(
    vault: PlatformSecureCredentialVault(MemorySecureStorage()),
    localAuth: FakeLocalAuthGate(),
    pins: MemoryBrainCertificatePinStore(),
    transport: transport,
  );
  await client.pair(PairingRequest(enrollmentUri: Uri.parse(_enrollment)));
  return (client: client, transport: transport);
}

List<String> _requestIds(FakeBrainTlsTransport transport) => [
  for (final call in transport.delivered)
    if (call.path == '/api/commander/v1/jobs' && call.body.isNotEmpty)
      (jsonDecode(utf8.decode(call.body)) as Map<String, dynamic>)['requestId']
          as String,
];

void main() {
  group('the Brain\'s own error text reaches the operator', () {
    test('a rejected enrollment says why', () async {
      final setup = await _paired();
      setup.transport.respond = (method, path, body) => jsonResponse({
        'ok': false,
        'error': 'invalid or expired Commander enrollment',
      }, statusCode: 401);

      await expectLater(
        setup.client.getOverview(),
        throwsA(
          isA<CommanderTransportException>()
              .having(
                (e) => e.message,
                'message',
                contains('invalid or expired Commander enrollment'),
              )
              .having((e) => e.authorizationRejected, 'rejected', isTrue),
        ),
      );
    });

    test(
      'an already-paired conflict is no longer a bare status code',
      () async {
        final setup = await _paired();
        setup.transport.respond = (method, path, body) => jsonResponse({
          'ok': false,
          'error': 'already paired',
        }, statusCode: 409);

        await expectLater(
          setup.client.getOverview(),
          throwsA(
            isA<CommanderTransportException>()
                .having((e) => e.message, 'message', contains('already paired'))
                .having((e) => e.statusCode, 'statusCode', 409),
          ),
        );
      },
    );

    test('rate limiting reports the wait from Retry-After', () async {
      final setup = await _paired();
      setup.transport.respond = (method, path, body) => (
        statusCode: 429,
        contentType: 'application/json',
        retryAfter: '30',
        body: utf8.encode(
          jsonEncode({'ok': false, 'error': 'too many requests'}),
        ),
      );

      await expectLater(
        setup.client.getOverview(),
        throwsA(
          isA<CommanderTransportException>()
              .having(
                (e) => e.message,
                'message',
                contains('too many requests'),
              )
              .having((e) => e.message, 'message', contains('30 seconds'))
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 30),
              ),
        ),
      );
    });

    test('an HTTP-date Retry-After is understood', () async {
      final setup = await _paired();
      final when = DateTime.now().toUtc().add(const Duration(minutes: 5));
      setup.transport.respond = (method, path, body) => (
        statusCode: 503,
        contentType: 'application/json',
        retryAfter: HttpDateFormat.format(when),
        body: utf8.encode(jsonEncode({'ok': false, 'error': 'maintenance'})),
      );

      await expectLater(
        setup.client.getOverview(),
        throwsA(
          isA<CommanderTransportException>().having(
            (e) => e.retryAfter!.inSeconds,
            'retryAfter',
            closeTo(300, 5),
          ),
        ),
      );
    });

    test('an absurd or unparsable Retry-After is ignored', () async {
      final setup = await _paired();
      setup.transport.respond = (method, path, body) => (
        statusCode: 429,
        contentType: 'application/json',
        retryAfter: '99999999',
        body: utf8.encode(jsonEncode({'ok': false})),
      );

      await expectLater(
        setup.client.getOverview(),
        throwsA(
          isA<CommanderTransportException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            isNull,
          ),
        ),
      );
    });

    test('server text is bounded and stripped of control characters', () async {
      final setup = await _paired();
      setup.transport.respond = (method, path, body) => jsonResponse({
        'ok': false,
        'error': 'line one\nline\x00two ${'x' * 500}',
      }, statusCode: 400);

      await expectLater(
        setup.client.getOverview(),
        throwsA(
          isA<CommanderTransportException>()
              .having((e) => e.message, 'message', isNot(contains('\n')))
              .having((e) => e.message, 'message', isNot(contains('\x00')))
              .having((e) => e.message.length, 'length', lessThan(260)),
        ),
      );
    });
  });

  group('job submission is idempotent across retries', () {
    test('a retry after an unknown outcome reuses the request id', () async {
      final setup = await _paired();
      const job = JobRequest(capabilityId: 'llm-grounded', input: 'hello');
      await setup.client.getCatalog();

      setup.transport.respond = (method, path, body) => path.endsWith('/jobs')
          ? jsonResponse({
              'ok': false,
              'error': 'upstream down',
            }, statusCode: 503)
          : _ok(path);
      await expectLater(setup.client.submitJob(job), throwsA(isA<Exception>()));

      setup.transport.respond = (method, path, body) => _ok(path);
      await setup.client.submitJob(job);

      final ids = _requestIds(setup.transport);
      expect(ids, hasLength(2));
      expect(ids.first, ids.last, reason: 'the Brain must dedupe the retry');
    });

    test('a definitive refusal releases the key', () async {
      final setup = await _paired();
      const job = JobRequest(capabilityId: 'llm-grounded', input: 'hello');
      await setup.client.getCatalog();

      setup.transport.respond = (method, path, body) => path.endsWith('/jobs')
          ? jsonResponse({
              'ok': false,
              'error': 'input rejected',
            }, statusCode: 400)
          : _ok(path);
      await expectLater(setup.client.submitJob(job), throwsA(isA<Exception>()));

      setup.transport.respond = (method, path, body) => _ok(path);
      await setup.client.submitJob(job);

      final ids = _requestIds(setup.transport);
      expect(ids, hasLength(2));
      expect(ids.first, isNot(ids.last));
    });

    test('a deliberate resubmission after success is a new job', () async {
      final setup = await _paired();
      const job = JobRequest(capabilityId: 'llm-grounded', input: 'hello');
      await setup.client.getCatalog();

      await setup.client.submitJob(job);
      await setup.client.submitJob(job);

      final ids = _requestIds(setup.transport);
      expect(ids, hasLength(2));
      expect(ids.first, isNot(ids.last));
    });

    test('different submissions never share a key', () async {
      final setup = await _paired();
      await setup.client.getCatalog();

      setup.transport.respond = (method, path, body) => path.endsWith('/jobs')
          ? jsonResponse({'ok': false}, statusCode: 503)
          : _ok(path);
      for (final input in const ['one', 'two']) {
        await expectLater(
          setup.client.submitJob(
            JobRequest(capabilityId: 'llm-grounded', input: input),
          ),
          throwsA(isA<Exception>()),
        );
      }

      final ids = _requestIds(setup.transport);
      expect(ids.toSet(), hasLength(2));
    });
  });
}

/// Minimal RFC 1123 formatter so the test does not depend on `dart:io`.
abstract final class HttpDateFormat {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String format(DateTime value) {
    final utc = value.toUtc();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${_days[utc.weekday - 1]}, ${pad(utc.day)} '
        '${_months[utc.month - 1]} ${utc.year} '
        '${pad(utc.hour)}:${pad(utc.minute)}:${pad(utc.second)} GMT';
  }
}
