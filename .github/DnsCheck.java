/*
 * Copyright (c) 2011-2026 Contributors to the Eclipse Foundation
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License 2.0 which is available at
 * http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
 * which is available at https://www.apache.org/licenses/LICENSE-2.0.
 *
 * SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
 */

import io.netty.channel.MultiThreadIoEventLoopGroup;
import io.netty.channel.nio.NioIoHandler;
import io.netty.channel.socket.nio.NioDatagramChannel;
import io.netty.resolver.dns.DefaultDnsServerAddressStreamProvider;
import io.netty.resolver.dns.DnsNameResolver;
import io.netty.resolver.dns.DnsNameResolverBuilder;
import io.netty.resolver.dns.DnsServerAddressStream;
import io.netty.resolver.dns.DnsServerAddressStreamProviders;
import io.netty.resolver.dns.DnsServerAddresses;
import io.netty.util.concurrent.Future;
import io.netty.util.internal.PlatformDependent;

import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Diagnostic for CI: shows the DNS name servers Netty finds on this machine, the same way Vert.x does when no
 * servers are configured, whether two of them would collide on the mirrored loopback key used by
 * {@code DnsQueryContextManager}, and whether resolving an unknown host name completes.
 *
 * <p>Run with assertions enabled, as surefire does: {@code java -ea -cp <classpath> DnsCheck.java}.
 * This program never fails the build, it only prints.
 */
public class DnsCheck {

  public static void main(String[] args) throws Exception {
    System.out.println("assertions enabled: " + DnsCheck.class.desiredAssertionStatus());
    System.out.println("java: " + System.getProperty("java.version") + ", os: " + System.getProperty("os.name"));
    System.out.println("netty resolver-dns: " + DnsNameResolver.class.getPackage().getImplementationVersion());

    // Same as Vert.x DnsAddressResolverProvider when no servers are configured
    List<InetSocketAddress> servers = new ArrayList<>();
    DnsServerAddressStream stream = DefaultDnsServerAddressStreamProvider.defaultAddresses().stream();
    Set<InetSocketAddress> seen = new HashSet<>();
    while (true) {
      InetSocketAddress address = stream.next();
      if (!seen.add(address)) {
        break;
      }
      servers.add(address);
    }
    System.out.println("default name servers (as used by Vert.x): " + servers);

    DnsServerAddressStream platform = DnsServerAddressStreamProviders.platformDefault()
      .nameServerAddressStream("does.not.exist.com");
    List<InetSocketAddress> platformServers = new ArrayList<>();
    for (int i = 0; i < platform.size(); i++) {
      platformServers.add(platform.next());
    }
    System.out.println("platform default name servers: " + platformServers);

    reportMirrorCollisions(servers);

    resolve(servers);
    System.exit(0);
  }

  // Mirror of the keys registered by DnsQueryContextManager#getOrCreateContextMap
  private static void reportMirrorCollisions(List<InetSocketAddress> servers) {
    Map<InetSocketAddress, InetSocketAddress> keys = new HashMap<>();
    boolean collision = false;
    for (InetSocketAddress server : servers) {
      InetAddress a = server.getAddress();
      int port = server.getPort();
      InetSocketAddress mirror = null;
      if (a instanceof Inet4Address && a.isLoopbackAddress()) {
        mirror = new InetSocketAddress(io.netty.util.NetUtil.LOCALHOST6, port);
      } else if (a instanceof Inet6Address && a.isLoopbackAddress()) {
        mirror = new InetSocketAddress(io.netty.util.NetUtil.LOCALHOST4, port);
      }
      if (keys.put(server, server) != null) {
        collision = true;
        System.out.println("COLLISION: key already registered " + server);
      }
      if (mirror != null && keys.put(mirror, server) != null) {
        collision = true;
        System.out.println("COLLISION: mirror key " + mirror + " of " + server + " already registered");
      }
    }
    System.out.println("mirror key collision: " + collision);
  }

  private static void resolve(List<InetSocketAddress> servers) throws Exception {
    MultiThreadIoEventLoopGroup group = new MultiThreadIoEventLoopGroup(1, NioIoHandler.newFactory());
    DnsServerAddresses addresses = DnsServerAddresses.sequential(servers);
    DnsNameResolver resolver = new DnsNameResolverBuilder(group.next())
      .datagramChannelType(NioDatagramChannel.class)
      .nameServerProvider(host -> addresses.stream())
      .queryTimeoutMillis(2000)
      .build();
    long start = System.currentTimeMillis();
    Future<List<InetAddress>> future = resolver.resolveAll("does.not.exist.com");
    boolean completed = future.await(10_000);
    System.out.println("lookup of does.not.exist.com: completed=" + completed
      + ", elapsed=" + (System.currentTimeMillis() - start) + "ms"
      + (completed ? ", failure=" + future.cause() : " (HUNG)"));
  }
}
