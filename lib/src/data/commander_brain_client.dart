import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/brain_client.dart';
import '../security/brain_certificate_pin.dart';
import '../security/commander_auth.dart';
import '../security/local_auth_gate.dart';
import '../security/secure_credential_vault.dart';
import 'brain_tls_transport.dart';
import 'fixture_brain_client.dart';

final class CommanderTransportException implements Exception {
  const CommanderTransportException(
    this.message, {
    this.authorizationRejected = false,
    this.certificateChanged = false,
    this.statusCode,
    this.retryAfter,
  });
  final String message;
  final bool authorizationRejected;

  /// The Brain's TLS identity no longer matches what was pinned at pairing.
  /// Callers must not react by deleting the credential.
  final bool certificateChanged;

  /// HTTP status, when the Brain actually answered.
  final int? statusCode;

  /// How long the Brain asked Commander to wait, from `Retry-After`.
  final Duration? retryAfter;

  /// Whether the Brain gave a verdict that retrying the identical request
  /// cannot change. Used to release a held idempotency key.
  bool get isDefinitiveRejection => switch (statusCode) {
    null => false,
    408 || 429 => false,
    final status => status >= 400 && status < 500,
  };

  @override
  String toString() => message;
}

final class CommanderBrainClient implements BrainClient {
  CommanderBrainClient({
    required SecureCredentialVault vault,
    required LocalAuthGate localAuth,
    required BrainCertificatePinStore pins,
    FixtureBrainClient? fixture,
    CommanderDeviceSigner? signer,
    BrainTlsTransport? transport,
  }) : _vault = vault,
       _localAuth = localAuth,
       _pins = pins,
       _fixture = fixture ?? FixtureBrainClient(),
       _signer = signer ?? CommanderDeviceSigner(),
       _transport = transport ?? PlatformBrainTlsTransport();

  final SecureCredentialVault _vault;
  final LocalAuthGate _localAuth;
  final BrainCertificatePinStore _pins;
  final FixtureBrainClient _fixture;
  final CommanderDeviceSigner _signer;
  final BrainTlsTransport _transport;
  Future<DeviceCredential?>? _credentialFuture;
  List<ModelCapability> _catalog = const [];

  /// Idempotency keys for submissions whose outcome is not yet known, by
  /// request payload. Insertion-ordered so the oldest is evicted first.
  ///
  /// In memory only: this survives a retry within a session, which is the
  /// case that duplicates jobs today. It does **not** survive the process
  /// being killed between the timeout and the retry.
  final _inFlight = <String, String>{};
  static const _maxInFlight = 32;

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
    if (!localAuthPermits(outcome)) {
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

  /// Sends a request under the trust anchors pinned for [origin] at pairing.
  ///
  /// A failed pinned handshake is not fatal on its own — a Brain certificate
  /// legitimately changes at every renewal. The rotation path re-establishes
  /// the peer's identity over a handshake that carries no application data,
  /// and only then re-sends. A signed request, and any job payload inside it,
  /// is therefore never handed to a peer whose identity was not checked first.
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
    final pin = await _pins.read(origin);
    try {
      return await _send(
        origin: origin,
        method: method,
        path: path,
        body: body,
        credential: credential,
        enrollmentToken: enrollmentToken,
        trustBundle: pin?.trustBundle,
      );
    } on BrainHandshakeException catch (error) {
      if (pin == null) {
        // Nothing pinned yet: this is an ordinary public-CA validation
        // failure, reported as such.
        throw CommanderTransportException(
          'The Brain\'s TLS certificate could not be validated. $error',
        );
      }
      final rotated = await _rotatePin(origin, pin);
      try {
        return await _send(
          origin: origin,
          method: method,
          path: path,
          body: body,
          credential: credential,
          enrollmentToken: enrollmentToken,
          trustBundle: rotated.trustBundle,
        );
      } on BrainHandshakeException {
        throw _certificateChanged(origin, pin, null);
      }
    }
  }

  /// Re-checks who is answering for [origin] after a pinned handshake failed.
  ///
  /// The probe uses ordinary public-CA validation, so a renewal is only
  /// adopted when it is both publicly valid *and* continuous with the
  /// certificate recorded at pairing.
  Future<BrainCertificatePin> _rotatePin(
    Uri origin,
    BrainCertificatePin pin,
  ) async {
    final ObservedCertificate observed;
    try {
      observed = await _transport.peerCertificate(origin);
    } on BrainHandshakeException {
      throw _certificateChanged(origin, pin, null);
    }
    if (pin.contains(observed.fingerprint) || !pin.allowsRotationTo(observed)) {
      throw _certificateChanged(origin, pin, observed);
    }
    final rotated = pin.rotatedWith(observed);
    await _pins.write(origin, rotated);
    return rotated;
  }

  /// Fail-closed refusal. Deliberately does not clear the pin or the
  /// credential: an operator who is being attacked must not have their own
  /// access destroyed as a side effect.
  CommanderTransportException _certificateChanged(
    Uri origin,
    BrainCertificatePin pin,
    ObservedCertificate? observed,
  ) {
    if (observed != null && pin.contains(observed.fingerprint)) {
      return CommanderTransportException(
        'The pinned TLS certificate for ${origin.host} is no longer usable — '
        'it expired on ${observed.notAfter.toUtc()}. Renew the Brain\'s '
        'certificate, then pair Commander again from the operator console.',
        certificateChanged: true,
      );
    }
    final seen = observed == null
        ? 'Its identity could not be re-established.'
        : 'It is now issued by "${observed.issuer}" for "${observed.subject}", '
              'not by "${pin.issuer}" for "${pin.subject}".';
    return CommanderTransportException(
      'The TLS certificate for ${origin.host} changed and Commander refused '
      'to connect. $seen This is what an intercepting proxy looks like. '
      'Your pairing has been kept. If the Brain\'s certificate authority '
      'really did change, pair Commander again from the protected operator '
      'console to trust the new certificate.',
      certificateChanged: true,
    );
  }

  Future<Map<String, dynamic>> _send({
    required Uri origin,
    required String method,
    required String path,
    required List<int> body,
    required String? trustBundle,
    DeviceCredential? credential,
    String? enrollmentToken,
  }) async {
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      if (body.isNotEmpty)
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      if (enrollmentToken != null)
        HttpHeaders.authorizationHeader: 'Bearer $enrollmentToken',
    };
    if (credential != null) {
      headers.addAll(
        await _signer.signedHeaders(
          credential: credential,
          method: method,
          path: path,
          body: body,
        ),
      );
    }
    final BrainResponse response;
    try {
      response = await _transport.send(
        method: method,
        url: origin.resolve(path),
        headers: headers,
        body: body,
        trustBundle: trustBundle,
      );
    } on BrainNetworkException catch (error) {
      throw CommanderTransportException('$error');
    }
    if (response.contentType != 'application/json') {
      throw const CommanderTransportException(
        'Brain returned an unexpected content type.',
      );
    }
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(utf8.decode(response.body));
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
      throw _failure(response, _reason(decoded['error']));
    }
    return decoded;
  }

  /// Builds the operator-facing failure, keeping the Brain's own explanation.
  ///
  /// Collapsing "invalid or expired Commander enrollment", "already paired"
  /// and "too many requests" all into `Brain request failed (401)` left the
  /// operator with nothing to act on.
  CommanderTransportException _failure(BrainResponse response, String? reason) {
    final retryAfter = _retryAfter(response.retryAfter);
    final wait = retryAfter == null
        ? ''
        : ' Try again in ${retryAfter.inSeconds} second'
              '${retryAfter.inSeconds == 1 ? '' : 's'}.';
    return switch (response.statusCode) {
      401 => CommanderTransportException(
        reason == null
            ? 'Commander authorization was rejected. Pair again or review '
                  'device scopes.'
            : 'Commander authorization was rejected: $reason. Pair again or '
                  'review device scopes.',
        authorizationRejected: true,
        statusCode: 401,
      ),
      429 => CommanderTransportException(
        '${reason ?? 'The Brain is rate limiting Commander.'}$wait',
        statusCode: 429,
        retryAfter: retryAfter,
      ),
      final status => CommanderTransportException(
        reason == null
            ? 'Brain request failed ($status).'
            : 'Brain request failed ($status): $reason.$wait',
        statusCode: status,
        retryAfter: retryAfter,
      ),
    };
  }

  /// Accepts the Brain's `error` field as a bounded, single-line string.
  ///
  /// The Brain is authenticated by the certificate pin, but its text still
  /// reaches operator-facing UI, so it is length-capped and stripped of
  /// control characters rather than passed through verbatim.
  static String? _reason(Object? value) {
    if (value is! String) return null;
    final cleaned = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    return cleaned.length <= 200 ? cleaned : '${cleaned.substring(0, 199)}…';
  }

  /// Parses `Retry-After` in both permitted forms: delta-seconds and
  /// HTTP-date. Anything absurd is ignored rather than trusted.
  static Duration? _retryAfter(String? value) {
    if (value == null) return null;
    const limit = Duration(hours: 24);
    final seconds = int.tryParse(value.trim());
    if (seconds != null) {
      if (seconds < 0 || seconds > limit.inSeconds) return null;
      return Duration(seconds: seconds);
    }
    try {
      final delta = HttpDate.parse(value).difference(DateTime.now().toUtc());
      if (delta > limit) return null;
      return delta.isNegative ? Duration.zero : delta;
    } on Object {
      return null;
    }
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
    if (await _vault.protection() != VaultProtection.operatingSystem) return;
    final origin = await _vault.activeOrigin();
    if (origin == null) return;
    return removePairedBrain(origin);
  }

  @override
  Future<List<PairedBrain>> pairedBrains() async {
    if (await _vault.protection() != VaultProtection.operatingSystem) {
      return const [];
    }
    final active = await _vault.activeOrigin();
    final brains = <PairedBrain>[];
    for (final origin in await _vault.origins()) {
      final DeviceCredential? credential;
      try {
        credential = await _vault.read(origin);
      } on FormatException {
        // An unreadable record cannot be signed with, switched to, or
        // revoked from here. Hiding it keeps the list honest about what this
        // device can actually command; the Brain's console still shows the
        // device itself.
        continue;
      }
      if (credential == null) continue;
      brains.add(
        PairedBrain(
          origin: origin,
          deviceId: credential.deviceId,
          deviceLabel: credential.deviceLabel,
          active: origin == active,
        ),
      );
    }
    return List.unmodifiable([
      for (final brain in brains)
        if (brain.active) brain,
      for (final brain in brains)
        if (!brain.active) brain,
    ]);
  }

  @override
  Future<BrainProfile> selectPairedBrain(Uri origin) async {
    if (await _vault.protection() != VaultProtection.operatingSystem) {
      throw const CommanderTransportException(
        'Operating-system secure credential storage is unavailable.',
      );
    }
    final credential = await _storedCredential(origin);
    if (credential == null) {
      throw CommanderTransportException(
        'No Commander credential is stored for ${origin.host}.',
      );
    }
    await _vault.activate(origin);
    // The catalog and any held idempotency key belong to the Brain being left.
    _catalog = const [];
    _inFlight.clear();
    _credentialFuture = Future.value(credential);
    return _profileFor(credential);
  }

  @override
  Future<void> removePairedBrain(Uri origin) async {
    final credential = await _storedCredential(origin);
    if (credential != null) {
      try {
        await _revoke(credential);
      } on CommanderTransportException catch (error) {
        // A Brain that rejects us, or one we refuse to talk to because its
        // certificate changed, can never be reached again. Local removal has
        // to stay possible in both cases or the operator is stranded.
        if (!error.authorizationRejected && !error.certificateChanged) rethrow;
      }
    }
    await _forgetLocally(origin);
  }

  Future<Map<String, dynamic>> _revoke(DeviceCredential credential) => _request(
    origin: credential.brainOrigin,
    method: 'POST',
    path: '/api/commander/v1/revoke',
    body: const [],
    credential: credential,
  );

  /// Drops every trace of [origin] from this device.
  ///
  /// The resolved credential is discarded rather than replaced with `null`:
  /// another pairing may still be stored, and activating it has to go back
  /// through the launch gate.
  Future<void> _forgetLocally(Uri origin) async {
    await _vault.remove(origin);
    await _pins.remove(origin);
    _catalog = const [];
    _inFlight.clear();
    _credentialFuture = null;
  }

  /// Reads the credential stored for [origin] behind a proof of user presence.
  ///
  /// Activating the credential at launch is what raises the unlock prompt, so
  /// reaching past it to a *second* Brain's credential must not be a way
  /// around the same check. When nothing is active there is no session unlock
  /// to inherit, and one is demanded here instead.
  Future<DeviceCredential?> _storedCredential(Uri origin) async {
    if (await _vault.protection() != VaultProtection.operatingSystem) {
      return null;
    }
    final active = await _credential();
    if (active != null) {
      return active.brainOrigin == origin ? active : _vault.read(origin);
    }
    if (await _vault.read(origin) == null) return null;
    final outcome = await _localAuth.authenticate(
      PrivilegedAction.unlockSession,
    );
    if (!localAuthPermits(outcome)) {
      throw localAuthRefusal(PrivilegedAction.unlockSession, outcome);
    }
    return _vault.read(origin);
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
    final payload = {'generator': capability.id, 'params': params};
    // The Brain deduplicates on requestId. Minting a fresh one per call
    // defeated that: a submission that timed out after the Brain had already
    // accepted it produced a second job when the operator tried again. The
    // same logical submission therefore keeps its key until the Brain gives a
    // verdict that a retry cannot change.
    final key = jsonEncode(payload);
    final requestId = _inFlight.putIfAbsent(key, _randomId);
    if (_inFlight.length > _maxInFlight) {
      _inFlight.remove(_inFlight.keys.first);
    }
    final body = utf8.encode(jsonEncode({...payload, 'requestId': requestId}));
    final Map<String, dynamic> response;
    try {
      response = await _request(
        origin: credential.brainOrigin,
        method: 'POST',
        path: '/api/commander/v1/jobs',
        body: body,
        credential: credential,
      );
    } on CommanderTransportException catch (error) {
      // A timeout, a network drop, or a 5xx leaves the outcome unknown, so
      // the key is held for the retry. A definitive refusal releases it.
      if (error.isDefinitiveRejection) _inFlight.remove(key);
      rethrow;
    }
    _inFlight.remove(key);
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
    // Record who answers for this origin before the one-time enrollment token
    // is sent, so even the pairing exchange runs over a pinned handshake.
    // Pairing is trust-on-first-use by nature: this can only record whoever
    // answered now. It is also the documented recovery path, so a fresh
    // pairing always replaces any earlier pin for the origin.
    final ObservedCertificate observed;
    try {
      observed = await _transport.peerCertificate(enrollment.brainOrigin);
    } on BrainHandshakeException catch (error) {
      throw CommanderTransportException(
        'The Brain\'s TLS certificate could not be validated. $error',
      );
    } on BrainNetworkException catch (error) {
      throw CommanderTransportException('$error');
    }
    await _pins.write(enrollment.brainOrigin, BrainCertificatePin.of(observed));
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
    // Pairing an origin that is already paired replaces the credential this
    // device holds for it, which strands the device row the old key belonged
    // to. Retire it rather than leaving an active row nobody holds a key for.
    // Best effort only: pairing again is the documented recovery path, and a
    // Brain that will not accept the old credential — the certificate changed,
    // the console already revoked it — must not block the recovery.
    if (await _replacedCredential(enrollment.brainOrigin) case final old?) {
      await _tryRevoke(old);
    }
    await _vault.write(credential);
    _catalog = const [];
    _inFlight.clear();
    _credentialFuture = Future.value(credential);
    return profile;
  }

  /// The credential [origin] currently holds, if it is readable at all.
  Future<DeviceCredential?> _replacedCredential(Uri origin) async {
    try {
      return await _vault.read(origin);
    } on Object {
      return null;
    }
  }

  /// Revokes [credential] on its own Brain, reporting only whether the Brain
  /// confirmed it. Never throws: every caller is cleaning up after something
  /// that has already been decided.
  Future<bool> _tryRevoke(DeviceCredential credential) async {
    try {
      await _revoke(credential);
      return true;
    } on Object {
      return false;
    }
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
