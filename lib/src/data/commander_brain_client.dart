import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/brain_client.dart';
import '../security/commander_auth.dart';
import '../security/local_auth_gate.dart';
import '../security/secure_credential_vault.dart';
import 'fixture_brain_client.dart';

final class CommanderTransportException implements Exception {
  const CommanderTransportException(
    this.message, {
    this.authorizationRejected = false,
  });
  final String message;
  final bool authorizationRejected;

  @override
  String toString() => message;
}

final class CommanderBrainClient implements BrainClient {
  CommanderBrainClient({
    required SecureCredentialVault vault,
    required LocalAuthGate localAuth,
    FixtureBrainClient? fixture,
    CommanderDeviceSigner? signer,
    HttpClient? httpClient,
  }) : _vault = vault,
       _localAuth = localAuth,
       _fixture = fixture ?? FixtureBrainClient(),
       _signer = signer ?? CommanderDeviceSigner(),
       _http =
           httpClient ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  static const _requestTimeout = Duration(seconds: 20);
  static const _maxResponseBytes = 1024 * 1024;

  final SecureCredentialVault _vault;
  final LocalAuthGate _localAuth;
  final FixtureBrainClient _fixture;
  final CommanderDeviceSigner _signer;
  final HttpClient _http;
  Future<DeviceCredential?>? _credentialFuture;
  List<ModelCapability> _catalog = const [];

  /// Reads the stored credential and activates it for this process only after
  /// the operator proves presence to the operating system.
  ///
  /// The prompt is deliberately not raised when no credential is stored:
  /// fixture mode carries no operator authority, so there is nothing to gate.
  Future<DeviceCredential?> _initialCredential() async {
    if (await _vault.protection() != VaultProtection.operatingSystem) {
      return null;
    }
    final credential = await _vault.readActive();
    if (credential == null) return null;
    final outcome = await _localAuth.authenticate(
      PrivilegedAction.unlockSession,
    );
    if (outcome != LocalAuthOutcome.authenticated) {
      throw localAuthRefusal(PrivilegedAction.unlockSession, outcome);
    }
    return credential;
  }

  /// Resolved lazily so the unlock prompt is raised on first data access —
  /// after the Flutter view exists — rather than during construction.
  Future<DeviceCredential?> _credential() {
    return _credentialFuture ??= _initialCredential().onError((error, stack) {
      // Let a refused or failed unlock be retried instead of poisoning the
      // client for the rest of the process lifetime.
      _credentialFuture = null;
      Error.throwWithStackTrace(error!, stack);
    });
  }

  Future<Map<String, dynamic>> _request({
    required Uri origin,
    required String method,
    required String path,
    required List<int> body,
    DeviceCredential? credential,
    String? enrollmentToken,
  }) async {
    if (origin.scheme != 'https' || origin.host.isEmpty) {
      throw const CommanderTransportException(
        'Commander requires an HTTPS Brain origin.',
      );
    }
    final target = origin.resolve(path);
    final request = await _http
        .openUrl(method, target)
        .timeout(_requestTimeout);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body.isNotEmpty) {
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.contentLength = body.length;
    }
    if (enrollmentToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $enrollmentToken',
      );
    }
    if (credential != null) {
      final headers = await _signer.signedHeaders(
        credential: credential,
        method: method,
        path: path,
        body: body,
      );
      headers.forEach(request.headers.set);
    }
    if (body.isNotEmpty) request.add(body);
    final response = await request.close().timeout(_requestTimeout);
    if (response.isRedirect) {
      await response.drain<void>();
      throw const CommanderTransportException(
        'Brain redirects are not accepted.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(_requestTimeout)) {
      if (bytes.length + chunk.length > _maxResponseBytes) {
        throw const CommanderTransportException(
          'Brain response exceeded the safety limit.',
        );
      }
      bytes.addAll(chunk);
    }
    if (response.headers.contentType?.mimeType != 'application/json') {
      throw const CommanderTransportException(
        'Brain returned an unexpected content type.',
      );
    }
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) throw const FormatException();
      decoded = value;
    } on Object {
      throw const CommanderTransportException(
        'Brain returned an invalid response.',
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] != true) {
      if (response.statusCode == 401) {
        throw const CommanderTransportException(
          'Commander authorization was rejected. Pair again or review device scopes.',
          authorizationRejected: true,
        );
      }
      throw CommanderTransportException(
        'Brain request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _signedGet(
    DeviceCredential credential,
    String path,
  ) => _request(
    origin: credential.brainOrigin,
    method: 'GET',
    path: path,
    body: const [],
    credential: credential,
  );

  @override
  Future<BrainProfile> getProfile() async {
    final credential = await _credential();
    if (credential == null) return _fixture.getProfile();
    return _profileFor(credential);
  }

  Future<BrainProfile> _profileFor(DeviceCredential credential) async {
    final response = await _signedGet(credential, '/api/commander/v1/profile');
    if (response['apiVersion'] != 1) {
      throw const CommanderTransportException(
        'The Brain uses an unsupported Commander API version.',
      );
    }
    final brain = _map(response['brain']);
    final device = _map(response['device']);
    final scopes = _strings(device['scopes']);
    if (device['id'] != credential.deviceId ||
        scopes.toSet().difference(credential.scopes).isNotEmpty) {
      throw const CommanderTransportException(
        'Brain profile did not match the paired identity.',
      );
    }
    return BrainProfile(
      name: _requiredString(brain['name'], 'brain name'),
      endpoint: credential.brainOrigin,
      mode: ConnectionMode.paired,
      identity: credential.deviceId,
      scopes: scopes,
    );
  }

  @override
  Future<BrainOverview> getOverview() async {
    final credential = await _credential();
    if (credential == null) return _fixture.getOverview();
    final response = await _signedGet(credential, '/api/commander/v1/overview');
    final fleet = _map(response['fleet']);
    final jobs = _map(response['jobs']);
    return BrainOverview(
      activeJobs: _integer(jobs['active']),
      readyNodes: _integer(fleet['readyWorkers']),
      billing: 'Operator',
      successRate: jobs['successRate'] is num
          ? (jobs['successRate'] as num).toDouble()
          : null,
    );
  }

  @override
  Future<List<ModelCapability>> getCatalog() async {
    final credential = await _credential();
    if (credential == null) return _fixture.getCatalog();
    final response = await _signedGet(credential, '/api/commander/v1/catalog');
    final catalog = _map(response['catalog']);
    final generators = _maps(catalog['generators']);
    _catalog = generators
        .map((generator) {
          final fields = _maps(generator['fields']);
          final input =
              fields.where((field) => field['name'] != 'model').firstOrNull ??
              const {};
          final models = _strings(generator['models']);
          return ModelCapability(
            id: _requiredString(generator['id'], 'generator id'),
            name: _requiredString(generator['label'], 'generator label'),
            kind: _requiredString(generator['output'], 'generator output'),
            summary: _requiredString(generator['lede'], 'generator summary'),
            creditCost: int.tryParse('${generator['estimatedCost'] ?? 0}') ?? 0,
            inputLabel: _requiredString(input['label'], 'input label'),
            inputHint: input['placeholder'] is String
                ? input['placeholder'] as String
                : '',
            parameterName: _requiredString(input['name'], 'input name'),
            model: models.firstOrNull,
          );
        })
        .toList(growable: false);
    return _catalog;
  }

  @override
  Future<List<CommanderJob>> getJobs() async {
    final credential = await _credential();
    if (credential == null) return _fixture.getJobs();
    final response = await _signedGet(credential, '/api/commander/v1/jobs');
    return _maps(response['jobs']).map(_job).toList(growable: false);
  }

  CommanderJob _job(Map<String, dynamic> job) {
    final generator = _requiredString(job['generator'], 'job generator');
    final model = _catalog.where((item) => item.id == generator).firstOrNull;
    final status = _requiredString(job['status'], 'job status');
    return CommanderJob(
      id: _requiredString(job['id'], 'job id'),
      modelName: model?.name ?? generator,
      state: switch (status) {
        'queued' => JobState.queued,
        'running' => JobState.running,
        'succeeded' => JobState.succeeded,
        _ => JobState.failed,
      },
      createdAt: DateTime.parse(
        _requiredString(job['createdAt'], 'job creation time'),
      ).toUtc(),
      owner: job['owner'] is String ? job['owner'] as String : 'Operator',
      progress: status == 'succeeded' ? 1 : 0,
    );
  }

  @override
  Future<List<FleetNode>> getFleet() async {
    final credential = await _credential();
    if (credential == null) return _fixture.getFleet();
    final response = await _signedGet(credential, '/api/commander/v1/fleet');
    final workers = _maps(response['workers']);
    final workerByNode = {
      for (final worker in workers)
        if (worker['nodeId'] is String) worker['nodeId'] as String: worker,
    };
    final nodes = _maps(response['nodes']).map((node) {
      final id = _requiredString(node['id'], 'node id');
      final worker = workerByNode[id];
      final active = node['status'] == 'active';
      final inFlight = worker == null ? 0 : _integer(worker['inFlight']);
      final capabilities = <String>{
        ..._strings(node['roles']),
        if (worker != null) ..._strings(worker['generators']),
      }.toList()..sort();
      final lastSeen = node['lastSeenAt'] is String
          ? node['lastSeenAt'] as String
          : _requiredString(node['createdAt'], 'node creation time');
      return FleetNode(
        id: id,
        name: _requiredString(node['name'], 'node name'),
        platform: _requiredString(node['kind'], 'node kind'),
        state: !active || worker == null
            ? NodeState.offline
            : (inFlight > 0 ? NodeState.busy : NodeState.ready),
        capabilities: capabilities,
        lastSeen: DateTime.parse(lastSeen).toUtc(),
      );
    }).toList();
    for (final worker in workers.where((item) => item['nodeId'] == null)) {
      nodes.add(
        FleetNode(
          id: _requiredString(worker['workerId'], 'worker id'),
          name: _requiredString(worker['workerId'], 'worker id'),
          platform: '${worker['kind']} · ${worker['klass']}',
          state: _integer(worker['inFlight']) > 0
              ? NodeState.busy
              : NodeState.ready,
          capabilities: _strings(worker['generators']),
          lastSeen: DateTime.now().toUtc(),
        ),
      );
    }
    return nodes;
  }

  @override
  Future<void> forgetPairing() async {
    final credential = await _credential();
    if (credential == null) return;
    try {
      await _request(
        origin: credential.brainOrigin,
        method: 'POST',
        path: '/api/commander/v1/revoke',
        body: const [],
        credential: credential,
      );
    } on CommanderTransportException catch (error) {
      if (!error.authorizationRejected) rethrow;
    }
    await _vault.remove(credential.brainOrigin);
    _catalog = const [];
    _credentialFuture = Future.value(null);
  }

  @override
  Future<List<BrainSetting>> getSettings() async {
    final credential = await _credential();
    if (credential == null) return _fixture.getSettings();
    final response = await _signedGet(credential, '/api/commander/v1/settings');
    final result = <BrainSetting>[];
    _flattenSettings(_map(response['settings']), '', result);
    return result.take(200).toList(growable: false);
  }

  static void _flattenSettings(
    Map<String, dynamic> value,
    String group,
    List<BrainSetting> output,
  ) {
    for (final entry in value.entries) {
      final path = group.isEmpty ? entry.key : '$group.${entry.key}';
      if (entry.value is Map<String, dynamic>) {
        _flattenSettings(entry.value as Map<String, dynamic>, path, output);
      } else {
        output.add(
          BrainSetting(
            group: group.isEmpty ? 'General' : group,
            name: entry.key,
            value: entry.value is String
                ? entry.value as String
                : jsonEncode(entry.value),
            sensitivity: entry.value == '' ? 'Redacted' : 'Read-only',
          ),
        );
      }
    }
  }

  @override
  Future<List<ActivityEvent>> getActivity() async {
    final credential = await _credential();
    if (credential == null) return _fixture.getActivity();
    final response = await _signedGet(credential, '/api/commander/v1/activity');
    return _maps(response['activity'])
        .map((event) {
          return ActivityEvent(
            id: _requiredString(event['id'], 'activity id'),
            action: _requiredString(event['action'], 'activity action'),
            actor: _requiredString(event['actor'], 'activity actor'),
            occurredAt: DateTime.parse(
              _requiredString(event['occurredAt'], 'activity time'),
            ).toUtc(),
            detail: jsonEncode(_map(event['detail'])),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<CommanderJob> submitJob(JobRequest request) async {
    final credential = await _credential();
    if (credential == null) return _fixture.submitJob(request);
    final capability = (_catalog.isEmpty ? await getCatalog() : _catalog)
        .where((item) => item.id == request.capabilityId)
        .firstOrNull;
    if (capability == null) {
      throw const CommanderTransportException(
        'The selected capability is unavailable.',
      );
    }
    final params = <String, dynamic>{capability.parameterName: request.input};
    if (capability.model case final model?) params['model'] = model;
    final requestId = _randomId();
    final body = utf8.encode(
      jsonEncode({
        'generator': capability.id,
        'params': params,
        'requestId': requestId,
      }),
    );
    final response = await _request(
      origin: credential.brainOrigin,
      method: 'POST',
      path: '/api/commander/v1/jobs',
      body: body,
      credential: credential,
    );
    return _job(_map(response['job']));
  }

  @override
  Future<BrainProfile> pair(PairingRequest request) async {
    final enrollment = CommanderEnrollment.parse(request.enrollmentUri);
    if (await _vault.protection() != VaultProtection.operatingSystem) {
      throw const CommanderTransportException(
        'Operating-system secure credential storage is unavailable.',
      );
    }
    final keyPair = await _signer.createKeyPair();
    final body = utf8.encode(jsonEncode({'publicKey': keyPair.publicKey}));
    final response = await _request(
      origin: enrollment.brainOrigin,
      method: 'POST',
      path: '/api/commander/v1/pair',
      body: body,
      enrollmentToken: enrollment.token,
    );
    if (response['apiVersion'] != 1) {
      throw const CommanderTransportException(
        'The Brain uses an unsupported Commander API version.',
      );
    }
    final device = _map(response['device']);
    final credential = DeviceCredential(
      brainOrigin: enrollment.brainOrigin,
      deviceId: _requiredString(device['id'], 'device id'),
      deviceLabel: _requiredString(device['label'], 'device label'),
      privateSeed: keyPair.seed,
      publicKey: keyPair.publicKey,
      scopes: _strings(device['scopes']).toSet(),
    );
    final profile = await _profileFor(credential);
    await _vault.write(credential);
    _credentialFuture = Future.value(credential);
    return profile;
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const CommanderTransportException(
        'Brain response schema was invalid.',
      );
    }
    return value;
  }

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List<dynamic> ||
        value.any((item) => item is! Map<String, dynamic>)) {
      throw const CommanderTransportException(
        'Brain response schema was invalid.',
      );
    }
    return value.cast<Map<String, dynamic>>();
  }

  static List<String> _strings(Object? value) {
    if (value is! List<dynamic> || value.any((item) => item is! String)) {
      throw const CommanderTransportException(
        'Brain response schema was invalid.',
      );
    }
    return value.cast<String>();
  }

  static String _requiredString(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw CommanderTransportException('Brain response omitted $field.');
    }
    return value;
  }

  static int _integer(Object? value) {
    if (value is! num || value < 0 || value > 1 << 31) {
      throw const CommanderTransportException(
        'Brain response schema was invalid.',
      );
    }
    return value.toInt();
  }
}
