import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';

void main() {
  group('CrdtLwwRegister Tests', () {
    test('set() returns new instance with updated value and timestamp', () {
      const t0 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const t1 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');

      const reg0 = CrdtLwwRegister<int>(value: 50, timestamp: t0);
      final reg1 = reg0.set(45, t1);

      expect(reg0.value, equals(50));
      expect(reg0.timestamp, equals(t0));

      expect(reg1.value, equals(45));
      expect(reg1.timestamp, equals(t1));
    });

    test('merge() adopts remote value when remote timestamp is strictly newer',
        () {
      const t0 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const t1 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeB');

      const local = CrdtLwwRegister<String>(value: 'Local', timestamp: t0);
      const remote = CrdtLwwRegister<String>(value: 'Remote', timestamp: t1);

      final merged = local.merge(remote);
      expect(merged.value, equals('Remote'));
      expect(merged.timestamp, equals(t1));
    });

    test('merge() retains local value when remote timestamp is older', () {
      const t0 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeB');

      const local = CrdtLwwRegister<String>(value: 'Local', timestamp: t0);
      const remote = CrdtLwwRegister<String>(value: 'Remote', timestamp: t1);

      final merged = local.merge(remote);
      expect(merged.value, equals('Local'));
      expect(merged.timestamp, equals(t0));
    });

    test(
        'merge() uses lexicographical tie-breaking for equal physical & logical clocks',
        () {
      const tA = HybridLogicalClock(
          physicalTime: 1500, logicalCounter: 1, nodeId: 'nodeA');
      const tB = HybridLogicalClock(
          physicalTime: 1500, logicalCounter: 1, nodeId: 'nodeB');

      const regA = CrdtLwwRegister<String>(value: 'A', timestamp: tA);
      const regB = CrdtLwwRegister<String>(value: 'B', timestamp: tB);

      // tB.isAfter(tA) is true because 'nodeB' > 'nodeA'
      expect(regA.merge(regB).value, equals('B'));
      expect(regB.merge(regA).value, equals('B'));
    });

    test('Value equality and hash code', () {
      const t = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const reg1 = CrdtLwwRegister<int>(value: 10, timestamp: t);
      const reg2 = CrdtLwwRegister<int>(value: 10, timestamp: t);
      const reg3 = CrdtLwwRegister<int>(value: 20, timestamp: t);

      expect(reg1, equals(reg2));
      expect(reg1.hashCode, equals(reg2.hashCode));
      expect(reg1, isNot(equals(reg3)));
    });
  });
}
