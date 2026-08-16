import 'package:evaluetron_commander_app/src/security/brain_certificate_pin.dart';

final class MemoryBrainCertificatePinStore implements BrainCertificatePinStore {
  final pins = <String, BrainCertificatePin>{};

  @override
  Future<BrainCertificatePin?> read(Uri origin) async =>
      pins[origin.toString()];

  @override
  Future<void> write(Uri origin, BrainCertificatePin pin) async =>
      pins[origin.toString()] = pin;

  @override
  Future<void> remove(Uri origin) async => pins.remove(origin.toString());
}
