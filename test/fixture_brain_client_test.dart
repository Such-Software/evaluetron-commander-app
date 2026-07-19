import 'package:evaluetron_commander_app/src/data/fixture_brain_client.dart';
import 'package:evaluetron_commander_app/src/domain/brain_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FixtureBrainClient', () {
    test('labels itself as a non-live fixture', () async {
      final profile = await FixtureBrainClient().getProfile();

      expect(profile.mode, ConnectionMode.fixture);
      expect(profile.endpoint.host, 'fixture.invalid');
    });

    test('submits deterministic local jobs', () async {
      final client = FixtureBrainClient();

      final job = await client.submitJob(
        const JobRequest(
          capabilityId: 'llm-grounded',
          input: 'A bounded request',
        ),
      );

      expect(job.id, 'fixture_0004');
      expect(job.state, JobState.queued);
      expect((await client.getJobs()).first.id, job.id);
    });

    test('never pretends to pair', () {
      final client = FixtureBrainClient();

      expect(
        () => client.pair(
          PairingRequest(
            endpoint: Uri.parse('https://brain.example.com'),
            deviceLabel: 'Test Commander',
            pairingCode: 'ABCD-1234',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
