import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    const MapEquality().equals(a, b);

/// Immutable definition of an individual currency denomination.
@immutable
class CurrencyDenomination {
  final String id;
  final String name;
  final String symbol;
  final double
      conversionRateToBase; // e.g. 100 if base is 1 (like cents to dollar or cp to gp)
  final bool isDecimalStandard;
  final Map<String, dynamic> metadata;

  const CurrencyDenomination({
    required this.id,
    required this.name,
    required this.symbol,
    required this.conversionRateToBase,
    this.isDecimalStandard = true,
    this.metadata = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrencyDenomination &&
          id == other.id &&
          name == other.name &&
          symbol == other.symbol &&
          conversionRateToBase == other.conversionRateToBase &&
          isDecimalStandard == other.isDecimalStandard &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        symbol,
        conversionRateToBase,
        isDecimalStandard,
        const MapEquality<String, dynamic>().hash(metadata),
      );
}

/// Abstract currency system contract decoupled from any specific tabletop ruleset.
abstract interface class ICurrencySystem {
  /// Unique identifier of the currency system (e.g. 'dnd5e_currency', 'scifi_credits', 'fantasy_silver_standard').
  String get systemId;

  /// Human-readable display name of the currency system.
  String get displayName;

  /// Ordered denominations available in this system (usually sorted smallest to largest or highest to lowest).
  List<CurrencyDenomination> get denominations;

  /// The root baseline denomination against which conversion rates are anchored.
  String get baseDenominationId;

  /// Looks up a denomination by its canonical ID or returns null if unrecognized.
  CurrencyDenomination? getDenomination(String id);

  /// Converts an amount from one denomination to another using base conversion rates.
  double convert({
    required double amount,
    required String fromDenominationId,
    required String toDenominationId,
  });

  /// Formats a map of denomination balances into a readable string (e.g. '120 gp, 5 sp').
  String formatBalances(Map<String, int> balances);
}
