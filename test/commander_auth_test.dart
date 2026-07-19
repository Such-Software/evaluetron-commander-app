import 'dart:convert';

import 'package:evaluetron_commander_app/src/security/commander_auth.dart';
import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strictly parses the versioned Commander enrollment URI', () {
    final enrollment = CommanderEnrollment.parse(
      Uri.parse(
        'evaluetron-commander://pair?v=1&brain=https%3A%2F%2Fbrain.example.com&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    );

    expect(enrollment.brainOrigin, Uri.parse('https://brain.example.com'));
    expect(enrollment.token, startsWith('evc_'));
    expect(
      () => CommanderEnrollment.parse(
        Uri.parse(
          'evaluetron-commander://pair?v=1&brain=http%3A%2F%2Fbrain.example.com&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => CommanderEnrollment.parse(
        Uri.parse(
          'evaluetron-commander://pair?v=1&brain=https%3A%2F%2Fbrain.example.com&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&extra=1',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => CommanderEnrollment.parse(
        Uri.parse(
          'evaluetron-commander://pair?v=1&brain=https%3A%2F%2Fbrain.example.com&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      throwsFormatException,
    );
  });

  test('matches the Brain Ed25519 cross-runtime vector', () async {
    final credential = DeviceCredential(
      brainOrigin: Uri(scheme: 'https', host: 'brain.example.com'),
      deviceId: '12345678-1234-4123-8123-123456789abc',
      deviceLabel: 'Test Commander',
      privateSeed: 'nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A',
      publicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
      scopes: {'jobs:create'},
    );
    final body = utf8.encode(
      '{"generator":"tts","params":{"text":"hi"},"requestId":"AQIDBAUGBwgJCgsMDQ4PEA"}',
    );
    final signer = CommanderDeviceSigner();

    final canonical = await CommanderDeviceSigner.canonicalRequest(
      timestamp: '1750000000',
      nonce: 'ERITFBUWFxgZGhscHR4fIA',
      method: 'POST',
      path: '/api/commander/v1/jobs',
      body: body,
    );
    final headers = await signer.signedHeaders(
      credential: credential,
      method: 'POST',
      path: '/api/commander/v1/jobs',
      body: body,
      now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000, isUtc: true),
      nonce: List<int>.generate(16, (index) => 0x11 + index),
    );

    expect(
      canonical,
      endsWith(
        '27b799fec573aa7572fb9fce95c1b2121e9d666771c870d6330ed9158af49a89',
      ),
    );
    expect(headers['X-Evaluetron-Nonce'], 'ERITFBUWFxgZGhscHR4fIA');
    expect(
      headers['X-Evaluetron-Signature'],
      'KRzdckWQ8sENTQSYdcJAC1sUughTCHTMt3jrmnWkMFF2Z5LyL0t3YfWGErheVMFZrDl3dfH462Q64DxlismGAQ',
    );
  });
}
