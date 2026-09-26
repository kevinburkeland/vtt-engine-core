import '../models/character_models.dart';

/// Port (interface) defining character persistence operations in the Domain layer.
abstract class ICharacterRepository {
  /// Loads all saved characters from persistent storage.
  Future<List<Character>> loadCharacters();

  /// Retrieves a single character by ID, or null if not found.
  Future<Character?> getCharacter(String id);

  /// Fetches characters matching the given IDs/slugs, preserving the order of requested IDs.
  Future<List<Character>> getCharactersByIds(List<String> ids);

  /// Saves or updates a single character in storage.
  Future<void> saveCharacter(Character character);

  /// Saves multiple characters to storage.
  Future<void> saveCharacters(List<Character> characters);

  /// Saves the complete character roster to persistent storage.
  Future<void> saveRoster(List<Character> roster);

  /// Deletes a character by ID.
  Future<void> deleteCharacter(String characterId);

  /// Loads the ID of the active character, or null if unset.
  Future<String?> loadActiveCharacterId();

  /// Saves the ID of the active character.
  Future<void> saveActiveCharacterId(String id);

  /// Clears the saved active character ID.
  Future<void> clearActiveCharacterId();

  /// Reparses and updates a single character against current compendiums and rules.
  Future<Character> reparseCharacter(Character character);

  /// Reparses and updates all characters in the roster against current compendiums and rules.
  Future<List<Character>> reparseAllCharacters();
}
