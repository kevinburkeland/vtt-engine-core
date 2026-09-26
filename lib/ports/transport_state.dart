/// Connection states for the cascading peer-to-peer and cloud relay transport hierarchy.
enum TransportState {
  connecting,
  localWifi,
  webRtc,
  fallbackRelay,
  offline;

  /// Backwards compatibility alias for code expecting [p2pEstablished].
  @Deprecated('Use webRtc instead')
  static const TransportState p2pEstablished = TransportState.webRtc;
}
