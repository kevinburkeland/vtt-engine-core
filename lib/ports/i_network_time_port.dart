/// Abstract port defining the contract for retrieving authoritative network time.
/// Implementations live in the infrastructure layer to isolate the domain from network I/O.
abstract class INetworkTimePort {
  /// Fetches the authoritative current UTC time in milliseconds from a trusted external source.
  Future<int> getNetworkTimeMs();
}
