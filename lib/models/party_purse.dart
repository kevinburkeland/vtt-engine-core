import 'dart:convert';
import 'package:meta/meta.dart';
import '../crdt/pn_counter.dart';

/// Represents a ruleset-agnostic party currency ledger backed by CvRDT PN-Counter vectors
/// for conflict-free distributed convergence across any denomination key.
@immutable
class PartyPurse {
  final Map<String, PnCounter> denominationCounters;
  final int _legacyCp;
  final int _legacySp;
  final int _legacyEp;
  final int _legacyGp;
  final int _legacyPp;
  final PnCounter _cpCounter;
  final PnCounter _spCounter;
  final PnCounter _epCounter;
  final PnCounter _gpCounter;
  final PnCounter _ppCounter;

  PartyPurse({
    Map<String, PnCounter> denominationCounters = const {},
    int cp = 0,
    int sp = 0,
    int ep = 0,
    int gp = 0,
    int pp = 0,
    PnCounter cpCounter = const PnCounter.empty(),
    PnCounter spCounter = const PnCounter.empty(),
    PnCounter epCounter = const PnCounter.empty(),
    PnCounter gpCounter = const PnCounter.empty(),
    PnCounter ppCounter = const PnCounter.empty(),
    Map<String, PnCounter> customCounters = const {},
  })  : denominationCounters = Map.unmodifiable(
          Map<String, PnCounter>.from(
            denominationCounters.isNotEmpty
                ? denominationCounters
                : customCounters,
          ),
        ),
        _legacyCp = cp,
        _legacySp = sp,
        _legacyEp = ep,
        _legacyGp = gp,
        _legacyPp = pp,
        _cpCounter = cpCounter,
        _spCounter = spCounter,
        _epCounter = epCounter,
        _gpCounter = gpCounter,
        _ppCounter = ppCounter;

  const PartyPurse.empty()
      : denominationCounters = const {},
        _legacyCp = 0,
        _legacySp = 0,
        _legacyEp = 0,
        _legacyGp = 0,
        _legacyPp = 0,
        _cpCounter = const PnCounter.empty(),
        _spCounter = const PnCounter.empty(),
        _epCounter = const PnCounter.empty(),
        _gpCounter = const PnCounter.empty(),
        _ppCounter = const PnCounter.empty();

  PartyPurse.fromCounters(Map<String, PnCounter> counters)
      : denominationCounters =
            Map.unmodifiable(Map<String, PnCounter>.from(counters)),
        _legacyCp = 0,
        _legacySp = 0,
        _legacyEp = 0,
        _legacyGp = 0,
        _legacyPp = 0,
        _cpCounter = const PnCounter.empty(),
        _spCounter = const PnCounter.empty(),
        _epCounter = const PnCounter.empty(),
        _gpCounter = const PnCounter.empty(),
        _ppCounter = const PnCounter.empty();

  /// Retrieves the PN-counter for [denominationId].
  PnCounter getCounter(String denominationId) {
    final clean = denominationId.trim().toLowerCase();
    final direct = denominationCounters[clean];
    if (direct != null) return direct;
    switch (clean) {
      case 'cp':
        if (_cpCounter.positive.isNotEmpty || _cpCounter.negative.isNotEmpty)
          return _cpCounter;
        return _legacyCp > 0
            ? PnCounter.withInitialValue(_legacyCp, nodeId: 'init')
            : const PnCounter.empty();
      case 'sp':
        if (_spCounter.positive.isNotEmpty || _spCounter.negative.isNotEmpty)
          return _spCounter;
        return _legacySp > 0
            ? PnCounter.withInitialValue(_legacySp, nodeId: 'init')
            : const PnCounter.empty();
      case 'ep':
        if (_epCounter.positive.isNotEmpty || _epCounter.negative.isNotEmpty)
          return _epCounter;
        return _legacyEp > 0
            ? PnCounter.withInitialValue(_legacyEp, nodeId: 'init')
            : const PnCounter.empty();
      case 'gp':
        if (_gpCounter.positive.isNotEmpty || _gpCounter.negative.isNotEmpty)
          return _gpCounter;
        return _legacyGp > 0
            ? PnCounter.withInitialValue(_legacyGp, nodeId: 'init')
            : const PnCounter.empty();
      case 'pp':
        if (_ppCounter.positive.isNotEmpty || _ppCounter.negative.isNotEmpty)
          return _ppCounter;
        return _legacyPp > 0
            ? PnCounter.withInitialValue(_legacyPp, nodeId: 'init')
            : const PnCounter.empty();
      default:
        return const PnCounter.empty();
    }
  }

  /// Retrieves balance for any denomination key (e.g. 'gp', 'sp', 'credits', 'eb').
  int getBalance(String denominationId) {
    final clean = denominationId.trim().toLowerCase();
    final direct = denominationCounters[clean];
    if (direct != null) return direct.value;
    switch (clean) {
      case 'cp':
        return _legacyCp != 0 ? _legacyCp : _cpCounter.value;
      case 'sp':
        return _legacySp != 0 ? _legacySp : _spCounter.value;
      case 'ep':
        return _legacyEp != 0 ? _legacyEp : _epCounter.value;
      case 'gp':
        return _legacyGp != 0 ? _legacyGp : _gpCounter.value;
      case 'pp':
        return _legacyPp != 0 ? _legacyPp : _ppCounter.value;
      default:
        return 0;
    }
  }

  /// Map of all denomination balances across all tracked currencies.
  Map<String, int> get balances {
    final map = <String, int>{};
    denominationCounters.forEach((k, v) => map[k] = v.value);
    final cpBal = _legacyCp != 0 ? _legacyCp : _cpCounter.value;
    final spBal = _legacySp != 0 ? _legacySp : _spCounter.value;
    final epBal = _legacyEp != 0 ? _legacyEp : _epCounter.value;
    final gpBal = _legacyGp != 0 ? _legacyGp : _gpCounter.value;
    final ppBal = _legacyPp != 0 ? _legacyPp : _ppCounter.value;
    if (cpBal > 0 && !map.containsKey('cp')) map['cp'] = cpBal;
    if (spBal > 0 && !map.containsKey('sp')) map['sp'] = spBal;
    if (epBal > 0 && !map.containsKey('ep')) map['ep'] = epBal;
    if (gpBal > 0 && !map.containsKey('gp')) map['gp'] = gpBal;
    if (ppBal > 0 && !map.containsKey('pp')) map['pp'] = ppBal;
    return map;
  }

  /// Total units across all denominations.
  int get totalCoins => balances.values.fold(0, (sum, val) => sum + val);
  int get totalUnits => totalCoins;

  /// Whether all denomination balances are zero or no denominations exist.
  bool get isEmpty => balances.values.every((val) => val == 0);

  Map<String, PnCounter> get allCounters {
    final map = <String, PnCounter>{};
    for (final k in ['cp', 'sp', 'ep', 'gp', 'pp']) {
      final c = getCounter(k);
      if (c.positive.isNotEmpty || c.negative.isNotEmpty) {
        map[k] = c;
      }
    }
    denominationCounters.forEach((k, v) => map[k] = v);
    return Map.unmodifiable(map);
  }

  /// Modifies balance for an arbitrary denomination key by [delta] (positive or negative),
  /// routing directly through CvRDT [PnCounter] vectors for conflict-free convergence.
  PartyPurse modifyDenomination(String denominationId, int delta,
      {required String nodeId}) {
    if (nodeId.trim().isEmpty) {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'nodeId cannot be empty or whitespace.');
    }
    if (nodeId.trim().toLowerCase() == 'local') {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'CRDT mutations cannot use "local" as replica identity.');
    }
    if (delta == 0) return this;
    final clean = denominationId.trim().toLowerCase();
    final current = getCounter(clean);
    final updated = delta > 0
        ? current.increment(delta, nodeId: nodeId)
        : current.decrement(delta.abs(), nodeId: nodeId);
    final newCounters = Map<String, PnCounter>.from(allCounters)
      ..[clean] = updated;
    return PartyPurse.fromCounters(newCounters);
  }

  /// Sets balance for [denominationId] directly while preserving CvRDT PN-counter convergence.
  /// Applies differential increments or decrements under [nodeId] so that decreases
  /// are recorded as negative counts rather than being lost during lattice joins.
  PartyPurse setDenomination(String denominationId, int targetVal,
      {required String nodeId}) {
    if (nodeId.trim().isEmpty) {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'nodeId cannot be empty or whitespace.');
    }
    if (nodeId.trim().toLowerCase() == 'local') {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'CRDT mutations cannot use "local" as replica identity.');
    }
    final clean = denominationId.trim().toLowerCase();
    final current = getCounter(clean);
    final clampedTarget = targetVal.clamp(0, 9999999);
    final diff = clampedTarget - current.value;
    if (diff == 0) return this;
    final updated = diff > 0
        ? current.increment(diff, nodeId: nodeId)
        : current.decrement(-diff, nodeId: nodeId);
    final newCounters = Map<String, PnCounter>.from(allCounters)
      ..[clean] = updated;
    return PartyPurse.fromCounters(newCounters);
  }

  /// Merges another purse using CvRDT lattice join over PN-counters across all denominations.
  PartyPurse merge(PartyPurse other) {
    final allKeys = balances.keys.toSet().union(other.balances.keys.toSet());
    final merged = <String, PnCounter>{};
    for (final key in allKeys) {
      final a = getCounter(key);
      final b = other.getCounter(key);
      merged[key] = a.merge(b);
    }
    return PartyPurse.fromCounters(merged);
  }

  /// Adds another purse's denomination amounts to this purse.
  PartyPurse add(PartyPurse other, {required String nodeId}) {
    if (nodeId.trim().isEmpty) {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'nodeId cannot be empty or whitespace.');
    }
    if (nodeId.trim().toLowerCase() == 'local') {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'CRDT mutations cannot use "local" as replica identity.');
    }
    var result = this;
    for (final entry in other.balances.entries) {
      if (entry.value > 0) {
        result =
            result.modifyDenomination(entry.key, entry.value, nodeId: nodeId);
      }
    }
    return result;
  }

  /// Deducts another purse's denomination amounts from this purse.
  PartyPurse deduct(PartyPurse other, {required String nodeId}) {
    if (nodeId.trim().isEmpty) {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'nodeId cannot be empty or whitespace.');
    }
    if (nodeId.trim().toLowerCase() == 'local') {
      throw ArgumentError.value(
          nodeId, 'nodeId', 'CRDT mutations cannot use "local" as replica identity.');
    }
    var result = this;
    for (final entry in other.balances.entries) {
      if (entry.value > 0) {
        result =
            result.modifyDenomination(entry.key, -entry.value, nodeId: nodeId);
      }
    }
    return result;
  }

  PartyPurse copyWith({
    Map<String, PnCounter>? denominationCounters,
  }) {
    return PartyPurse.fromCounters(denominationCounters ?? allCounters);
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    for (final entry in balances.entries) {
      final key = entry.key;
      final val = entry.value;
      map[key] = val;
      final counter = getCounter(key);
      if (counter.positive.isNotEmpty || counter.negative.isNotEmpty) {
        map['${key}Counter'] = counter.toMap();
      }
    }
    if (allCounters.isNotEmpty) {
      map['denominationCounters'] =
          allCounters.map((k, v) => MapEntry(k, v.toMap()));
    }
    return map;
  }

  factory PartyPurse.fromMap(Map<String, dynamic> map) {
    final parsed = <String, PnCounter>{};

    void extractFromNested(dynamic nested) {
      if (nested is Map) {
        for (final entry in nested.entries) {
          final k = entry.key.toString().trim().toLowerCase();
          if (entry.value is Map) {
            try {
              parsed[k] = PnCounter.fromMap(
                (entry.value as Map).map((k, v) => MapEntry(k.toString(), v)),
              );
            } catch (_) {}
          }
        }
      }
    }

    extractFromNested(map['denominationCounters']);
    extractFromNested(map['customCounters']);

    map.forEach((rawKey, value) {
      final key = rawKey.trim().toLowerCase();
      if (key == 'denominationcounters' || key == 'customcounters') return;

      if (key.endsWith('counter')) {
        final denomKey = key.substring(0, key.length - 'counter'.length);
        if (value is Map && !parsed.containsKey(denomKey)) {
          try {
            parsed[denomKey] = PnCounter.fromMap(
              value.map((k, v) => MapEntry(k.toString(), v)),
            );
          } catch (_) {}
        }
      } else if (value is num) {
        final scalar = value.toInt();
        final existingCounter = parsed[key];
        if (existingCounter == null) {
          parsed[key] = scalar > 0
              ? PnCounter.withInitialValue(scalar, nodeId: 'init')
              : const PnCounter.empty();
        } else if (scalar != existingCounter.value) {
          final diff = scalar - existingCounter.value;
          parsed[key] = diff > 0
              ? existingCounter.increment(diff, nodeId: 'cloud')
              : existingCounter.decrement(-diff, nodeId: 'cloud');
        }
      }
    });

    return PartyPurse.fromCounters(parsed);
  }

  String toJson() => jsonEncode(toMap());
  factory PartyPurse.fromJson(String source) =>
      PartyPurse.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PartyPurse) return false;
    final allKeys = balances.keys.toSet().union(other.balances.keys.toSet());
    for (final key in allKeys) {
      if (getBalance(key) != other.getBalance(key)) return false;
      if (getCounter(key) != other.getCounter(key)) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int hash = 0;
    for (final entry in balances.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }

  @override
  String toString() {
    final nonZero = balances.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.value} ${e.key}')
        .join(', ');
    return 'PartyPurse(${nonZero.isEmpty ? "empty" : nonZero})';
  }
}
