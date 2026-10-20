import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/models/loot_models.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';

void main() {
  group('Cold Iron Birdcage Pass 7.2 R2: a timestamp without a value is an error', () {
    const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'n1');

    test('1. CampaignProfile.copyWith: nameTimestamp without name throws ArgumentError', () {
      final profile = CampaignProfile.initial(id: 'c1', name: 'Original', nodeId: 'n1');
      expect(() => profile.copyWith(nameTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = profile.copyWith(name: 'Updated', nameTimestamp: ts);
      expect(withVal.name, equals('Updated'));
      // passing register works
      final withReg = profile.copyWith(nameRegister: const CrdtLwwRegister(value: 'Reg', timestamp: ts));
      expect(withReg.name, equals('Reg'));
    });

    test('2. CampaignProfile.copyWith: notesTimestamp without notesMarkdown throws ArgumentError', () {
      final profile = CampaignProfile.initial(id: 'c1', name: 'Original', nodeId: 'n1');
      expect(() => profile.copyWith(notesTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = profile.copyWith(notesMarkdown: 'Updated notes', notesTimestamp: ts);
      expect(withVal.notesMarkdown, equals('Updated notes'));
      // passing register works
      final withReg = profile.copyWith(notesRegister: const CrdtLwwRegister(value: 'Reg notes', timestamp: ts));
      expect(withReg.notesMarkdown, equals('Reg notes'));
    });

    test('3. LootContainer.copyWith: nameTimestamp without name throws ArgumentError', () {
      final container = LootContainer(containerId: 'cnt1', name: 'Chest');
      expect(() => container.copyWith(nameTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = container.copyWith(name: 'Gold Chest', nameTimestamp: ts);
      expect(withVal.name, equals('Gold Chest'));
      // passing register works
      final withReg = container.copyWith(nameRegister: const CrdtLwwRegister(value: 'Reg Chest', timestamp: ts));
      expect(withReg.name, equals('Reg Chest'));
    });

    test('4. EntityInstance.copyWith: displayNameTimestamp without displayName throws ArgumentError', () {
      final instance = EntityInstance(instanceId: 'inst1', displayName: 'Goblin');
      expect(() => instance.copyWith(displayNameTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = instance.copyWith(displayName: 'Hobgoblin', displayNameTimestamp: ts);
      expect(withVal.displayName, equals('Hobgoblin'));
      // passing register works
      final withReg = instance.copyWith(displayNameRegister: const CrdtLwwRegister(value: 'Reg Goblin', timestamp: ts));
      expect(withReg.displayName, equals('Reg Goblin'));
    });

    test('5. RoomEntityLink.copyWith: displayNameTimestamp without displayName throws ArgumentError', () {
      final link = RoomEntityLink(entityId: 'e1', displayName: 'Door');
      expect(() => link.copyWith(displayNameTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = link.copyWith(displayName: 'Oak Door', displayNameTimestamp: ts);
      expect(withVal.displayName, equals('Oak Door'));
      // passing register works
      final withReg = link.copyWith(displayNameRegister: const CrdtLwwRegister(value: 'Reg Door', timestamp: ts));
      expect(withReg.displayName, equals('Reg Door'));
    });

    test('6. RoomEntityLink.copyWith: notesTimestamp without notes or clearNotes throws ArgumentError', () {
      final link = RoomEntityLink(entityId: 'e1', displayName: 'Door', notes: 'Initial note');
      expect(() => link.copyWith(notesTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = link.copyWith(notes: 'Updated note', notesTimestamp: ts);
      expect(withVal.notes, equals('Updated note'));
      // passing with clearNotes: true works
      final withClear = link.copyWith(clearNotes: true, notesTimestamp: ts);
      expect(withClear.notes, isNull);
      // passing with notes: null works
      final withNull = link.copyWith(notes: null, notesTimestamp: ts);
      expect(withNull.notes, isNull);
      // passing register works
      final withReg = link.copyWith(notesRegister: const CrdtLwwRegister(value: 'Reg note', timestamp: ts));
      expect(withReg.notes, equals('Reg note'));
    });

    test('7. RoomNodeState.copyWith: titleTimestamp without title throws ArgumentError', () {
      final room = RoomNodeState(roomId: 'r1', roomCode: 'ROOM1', title: 'Great Hall');
      expect(() => room.copyWith(titleTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = room.copyWith(title: 'Grand Hall', titleTimestamp: ts);
      expect(withVal.title, equals('Grand Hall'));
      // passing register works
      final withReg = room.copyWith(titleRegister: const CrdtLwwRegister(value: 'Reg Hall', timestamp: ts));
      expect(withReg.title, equals('Reg Hall'));
    });

    test('8. RoomNodeState.copyWith: descriptionTimestamp without description throws ArgumentError', () {
      final room = RoomNodeState(roomId: 'r1', roomCode: 'ROOM1', description: 'Dark hall');
      expect(() => room.copyWith(descriptionTimestamp: ts), throwsA(isA<ArgumentError>()));
      // passing with value works
      final withVal = room.copyWith(description: 'Bright hall', descriptionTimestamp: ts);
      expect(withVal.description, equals('Bright hall'));
      // passing register works
      final withReg = room.copyWith(descriptionRegister: const CrdtLwwRegister(value: 'Reg desc', timestamp: ts));
      expect(withReg.description, equals('Reg desc'));
    });
  });
}
