import 'dart:convert';
import 'dart:math' as math;
import 'package:meta/meta.dart';
import '../crdt/pn_counter.dart';
import '../crdt/replica_id.dart';

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
        if (_cpCounter.positive.isNotEmpty || _cpCounter.negative.isNotEmpty) {
          return _cpCounter;
        }
        return _legacyCp != 0
            ? (_legacyCp > 0
                ? PnCounter(positive: {'init': _legacyCp})
                : PnCounter(negative: {'init': _legacyCp.abs()}))
            : const PnCounter.empty();
      case 'sp':
        if (_spCounter.positive.isNotEmpty || _spCounter.negative.isNotEmpty) {
          return _spCounter;
        }
        return _legacySp != 0
            ? (_legacySp > 0
                ? PnCounter(positive: {'init': _legacySp})
                : PnCounter(negative: {'init': _legacySp.abs()}))
            : const PnCounter.empty();
      case 'ep':
        if (_epCounter.positive.isNotEmpty || _epCounter.negative.isNotEmpty) {
          return _epCounter;
        }
        return _legacyEp != 0
            ? (_legacyEp > 0
                ? PnCounter(positive: {'init': _legacyEp})
                : PnCounter(negative: {'init': _legacyEp.abs()}))
            : const PnCounter.empty();
      case 'gp':
        if (_gpCounter.positive.isNotEmpty || _gpCounter.negative.isNotEmpty) {
          return _gpCounter;
        }
        return _legacyGp != 0
            ? (_legacyGp > 0
                ? PnCounter(positive: {'init': _legacyGp})
                : PnCounter(negative: {'init': _legacyGp.abs()}))
            : const PnCounter.empty();
      case 'pp':
        if (_ppCounter.positive.isNotEmpty || _ppCounter.negative.isNotEmpty) {
          return _ppCounter;
        }
        return _legacyPp != 0
            ? (_legacyPp > 0
                ? PnCounter(positive: {'init': _legacyPp})
                : PnCounter(negative: {'init': _legacyPp.abs()}))
            : const PnCounter.empty();
      default:
        return const PnCounter.empty();
    }
  }

  /// Retrieves balance for any denomination key (e.g. 'gp', 'sp', 'credits', 'eb').
  /// Clamped at zero (>= 0) for presentation/currency semantics.
  int getBalance(String denominationId) {
    final clean = denominationId.trim().toLowerCase();
    final direct = denominationCounters[clean];
    if (direct != null) return math.max(0, direct.value);
    switch (clean) {
      case 'cp':
        return math.max(0, _legacyCp != 0 ? _legacyCp : _cpCounter.value);
      case 'sp':
        return math.max(0, _legacySp != 0 ? _legacySp : _spCounter.value);
      case 'ep':
        return math.max(0, _legacyEp != 0 ? _legacyEp : _epCounter.value);
      case 'gp':
        return math.max(0, _legacyGp != 0 ? _legacyGp : _gpCounter.value);
      case 'pp':
        return math.max(0, _legacyPp != 0 ? _legacyPp : _ppCounter.value);
      default:
        return 0;
    }
  }

  /// Map of all denomination balances across all tracked currencies.
  /// Currency values are guaranteed non-negative (>= 0).
  Map<String, int> get balances {
    final map = <String, int>{};
    denominationCounters.forEach((k, v) => map[k] = math.max(0, v.value));
    final cpBal = math.max(0, _legacyCp != 0 ? _legacyCp : _cpCounter.value);
    final spBal = math.max(0, _legacySp != 0 ? _legacySp : _spCounter.value);
    final epBal = math.max(0, _legacyEp != 0 ? _legacyEp : _epCounter.value);
    final gpBal = math.max(0, _legacyGp != 0 ? _legacyGp : _gpCounter.value);
    final ppBal = math.max(0, _legacyPp != 0 ? _legacyPp : _ppCounter.value);
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
      {required ReplicaId replicaId}) {
    if (delta == 0) return this;
    final clean = denominationId.trim().toLowerCase();
    final current = getCounter(clean);
    final updated = delta > 0
        ? current.increment(delta, replicaId: replicaId)
        : current.decrement(delta.abs(), replicaId: replicaId);
    final newCounters = Map<String, PnCounter>.from(allCounters)
      ..[clean] = updated;
    return PartyPurse.fromCounters(newCounters);
  }

  /// Sets balance for [denominationId] directly while preserving CvRDT PN-counter convergence.
  /// Calculates differential increments or decrements against the counter's underlying
  /// SIGNED mathematical value so that target is achieved even when hidden negative debt exists.
  PartyPurse setDenomination(String denominationId, int targetVal,
      {required ReplicaId replicaId}) {
    final clean = denominationId.trim().toLowerCase();
    final current = getCounter(clean);
    final clampedTarget = targetVal.clamp(0, 9999999);
    final diff = clampedTarget - current.value;
    if (diff == 0) return this;
    final updated = diff > 0
        ? current.increment(diff, replicaId: replicaId)
        : current.decrement(-diff, replicaId: replicaId);
    final newCounters = Map<String, PnCounter>.from(allCounters)
      ..[clean] = updated;
    return PartyPurse.fromCounters(newCounters);
  }

  /// Merges another purse using CvRDT lattice join over PN-counters across all denominations.
  PartyPurse merge(PartyPurse other) {
    final allKeys = {
      ...allCounters.keys,
      ...other.allCounters.keys,
      ...balances.keys,
      ...other.balances.keys,
    };
    final merged = <String, PnCounter>{};
    for (final key in allKeys) {
      final a = getCounter(key);
      final b = other.getCounter(key);
      merged[key] = a.merge(b);
    }
    return PartyPurse.fromCounters(merged);
  }

  /// Adds another purse's denomination amounts to this purse.
  PartyPurse add(PartyPurse other, {required ReplicaId replicaId}) {
    var result = this;
    for (final entry in other.balances.entries) {
      if (entry.value > 0) {
        result =
            result.modifyDenomination(entry.key, entry.value, replicaId: replicaId);
      }
    }
    return result;
  }

  /// Deducts another purse's denomination amounts from this purse.
  PartyPurse deduct(PartyPurse other, {required ReplicaId replicaId}) {
    var result = this;
    for (final entry in other.balances.entries) {
      if (entry.value > 0) {
        result =
            result.modifyDenomination(entry.key, -entry.value, replicaId: replicaId);
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
    for (final entry in allCounters.entries) {
      final key = entry.key;
      final counter = entry.value;
      map[key] = getBalance(key);
      if (counter.positive.isNotEmpty || counter.negative.isNotEmpty) {
        map['${key}Counter'] = counter.toMap();
      }
    }
    for (final entry in balances.entries) {
      if (!map.containsKey(entry.key)) {
        map[entry.key] = entry.value;
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

    // Pass 1: Extract all explicit counter maps first so counter state is authoritative
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
      }
    });

    // Pass 2: Process scalar fields.
    // If a counter already exists for this denomination, THE COUNTER IS AUTHORITATIVE.
    // Redundant scalar values are compatibility/display data and MUST NOT synthesize
    // new 'cloud' repair writes.
    // Only if NO counter exists, migrate the legacy scalar into an initial counter.
    map.forEach((rawKey, value) {
      final key = rawKey.trim().toLowerCase();
      if (key == 'denominationcounters' ||
          key == 'customcounters' ||
          key.endsWith('counter')) {
        return;
      }

      if (value is num) {
        final scalar = value.toInt();
        final existingCounter = parsed[key];
        if (existingCounter == null) {
          if (scalar > 0) {
            parsed[key] = PnCounter(positive: {'init': scalar});
          } else if (scalar < 0) {
            parsed[key] = PnCounter(negative: {'init': scalar.abs()});
          } else {
            parsed[key] = const PnCounter.empty();
          }
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
    final allKeys = {
      ...allCounters.keys,
      ...other.allCounters.keys,
      ...balances.keys,
      ...other.balances.keys,
    };
    for (final key in allKeys) {
      if (getBalance(key) != other.getBalance(key)) return false;
      if (getCounter(key) != other.getCounter(key)) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int hash = 0;
    for (final entry in allCounters.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
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
