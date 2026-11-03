#!/usr/bin/env bash
# Prints the runner DNS configuration, to troubleshoot Netty DNS resolver failures.
# Every command is best effort: this script never fails the build.

section() {
  echo "::group::$1"
}

run() {
  echo "\$ $*"
  "$@" 2>&1 || true
}

echo "Runner image: ${ImageOS:-unknown} ${ImageVersion:-unknown}"

section "/etc/resolv.conf"
run cat /etc/resolv.conf
run ls -l /etc/resolv.conf
echo "::endgroup::"

section "resolvectl status"
run resolvectl status
echo "::endgroup::"

section "UDP listeners (port 53)"
echo "\$ ss -lunp | grep ':53 '"
(ss -lunp 2>&1 | grep -E ':53\s' ) || true
echo "::endgroup::"

section "/etc/hosts and localhost resolution"
run cat /etc/hosts
run getent hosts localhost
echo "::endgroup::"

section "Loopback interface"
run ip addr show lo
echo "::endgroup::"

section "Docker daemon DNS configuration"
run cat /etc/docker/daemon.json
echo "::endgroup::"

exit 0
