/// The role of a found gateway's broker (ADR 0036): the one that serves,
/// or its warm standby. The gateway's `GatewayRole` is mapped to it once,
/// where `/api/info` is read.
enum BrokerRole {
  active,
  standby,
}
