import 'dart:async';

import 'package:dietry/services/serial_day_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Water writes used to be fired off independently, one per tap. Two taps
/// 200 ms apart sent an upsert of 200 ml and one of 400 ml, and nothing keeps
/// two in-flight requests in order — when the 200 landed last, the day fell
/// back to 200 ml on the next refresh after having shown 400 ml.
void main() {
  final day = DateTime(2026, 9, 2);
  final otherDay = DateTime(2026, 9, 3);

  group('SerialDayWriter', () {
    test('never runs two writes for the same day at once', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final gates = <Completer<void>>[];

      final writer = SerialDayWriter(
        write: (_, __) async {
          inFlight++;
          maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          inFlight--;
          return true;
        },
        onFailure: (_, __) => fail('write succeeded'),
      );

      final first = writer.submit(day, 200, baseline: 0);
      final second = writer.submit(day, 400, baseline: 200);
      expect(maxInFlight, 1);

      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      gates[1].complete();
      await Future.wait([first, second]);
      expect(maxInFlight, 1);
    });

    test('the last submitted value is the one that lands', () async {
      final written = <int>[];
      final gates = <Completer<void>>[];
      final writer = SerialDayWriter(
        write: (_, value) async {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          written.add(value);
          return true;
        },
        onFailure: (_, __) => fail('write succeeded'),
      );

      // A burst of four taps while the first write is still on its way.
      final pending = [
        writer.submit(day, 200, baseline: 0),
        writer.submit(day, 400, baseline: 200),
        writer.submit(day, 600, baseline: 400),
        writer.submit(day, 800, baseline: 600),
      ];
      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      gates[1].complete();
      await Future.wait(pending);

      // Two requests, not four — and the value the user last saw is stored.
      expect(written, [200, 800]);
    });

    test('reports a day as pending until its write is acknowledged', () async {
      final gate = Completer<void>();
      final writer = SerialDayWriter(
        write: (_, __) async {
          await gate.future;
          return true;
        },
        onFailure: (_, __) => fail('write succeeded'),
      );

      final pending = writer.submit(day, 200, baseline: 0);
      expect(writer.hasPending(day), isTrue);
      // Same calendar day, different time of day — still the same entry.
      expect(writer.hasPending(DateTime(2026, 9, 2, 18, 30)), isTrue);
      expect(writer.hasPending(otherDay), isFalse);

      gate.complete();
      await pending;
      expect(writer.hasPending(day), isFalse);
    });

    test('queues another day instead of coalescing it away', () async {
      final written = <(DateTime, int)>[];
      final writer = SerialDayWriter(
        write: (date, value) async {
          written.add((date, value));
          return true;
        },
        onFailure: (_, __) => fail('write succeeded'),
      );

      await Future.wait([
        writer.submit(day, 200, baseline: 0),
        writer.submit(otherDay, 500, baseline: 0),
      ]);

      expect(written, [(day, 200), (otherDay, 500)]);
    });

    test('reverts to where the burst started when a write fails', () async {
      final reverted = <(DateTime, int)>[];
      final writer = SerialDayWriter(
        write: (_, __) async => false,
        onFailure: (date, baseline) => reverted.add((date, baseline)),
      );

      // Both taps of the burst fail; the undo goes back to the pre-burst value,
      // not to the intermediate one the second tap started from.
      await Future.wait([
        writer.submit(day, 200, baseline: 0),
        writer.submit(day, 400, baseline: 200),
      ]);

      expect(reverted, [(day, 0)]);
    });

    test('clear() drops queued writes without reverting', () async {
      final gate = Completer<void>();
      final writer = SerialDayWriter(
        write: (_, __) async {
          await gate.future;
          return false;
        },
        onFailure: (_, __) => fail('a cleared write must not revert'),
      );

      final pending = writer.submit(day, 200, baseline: 0);
      writer.clear();
      gate.complete();
      await pending;
      expect(writer.hasPending(day), isFalse);
    });
  });
}
