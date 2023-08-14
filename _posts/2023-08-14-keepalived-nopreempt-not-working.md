# keepalived nopreempt 不生效

## Keepalived 简介

keepalived 是一款用于 Linux 系统的开源软件，主要用于提供简单的负载均衡和高可用性功能。

### 高可用性 (High Availability):

keepalived 使用 VRRP (Virtual Router Redundancy Protocol) 实现高可用性。

VRRP 允许多个服务器共享一个虚拟 IP 地址。在这些服务器中，有一个被指定为主服务器 (master)，而其他的为备份服务器 (backup)。

这样，如果一台服务器出现故障，那么其他的服务器就会接管这个虚拟 IP 地址，从而保证服务的可用性。

## 故障现象

在已经配置了 nopreempt 的集群里，当节点重启时，虚拟 IP 会在节点立即切换到其它节点上。但是当节点重启完成后，虚拟 IP 会再次切换到被重启的节点上。预期是节点重启后，虚拟 IP 仍然在其它节点上。

## 现象分析

假设有 A, C 两个节点。A, C 节点都配置了 nopreempt 。虚拟 IP 在 A 上，现在重启 A 节点。在 C 节点发现了如下日志：

```
17:56:06 Keepalived_vrrp[261668]: (VI_2) Entering BACKUP STATE (init)
17:56:06 Keepalived_vrrp[261668]: VRRP_Script(chk_nginx) succeeded
18:16:05 Keepalived_vrrp[261668]: (VI_2) Entering MASTER STATE
18:21:00 Keepalived_vrrp[261668]: (VI_2) Master received advert from 10.xxx with same priority 90 but higher IP address than ours
18:21:00 Keepalived_vrrp[261668]: (VI_2) Entering BACKUP STATE
```

从日志可以看出
* 18:16:05 : A 节点开始重启
* 18:21:00 : A 节点重启完成，并立刻抢占回虚拟 IP，C 节点重新变为 BACKUP


## 调查原因

经过一番搜索，发现网上也有很多人遇到类似情况。发现一个官方的 issue [nopreempt option ignored in keepalived](https://github.com/acassen/keepalived/issues/2032) 。仔细阅读后，发现这个 issue 里提到了一个要点：

```
# On some systems when bond interfaces are created, they can start passing traffic
# and then have a several second gap when they stop passing traffic inbound. This
# can mean that if keepalived is started at boot time, i.e. at the same time as
# bond interfaces are being created, keepalived doesn't receive adverts and hence
# can become master despite an instance with higher priority sending adverts.
# This option specifies a delay in seconds before vrrp instances start up after
# keepalived starts,
vrrp_startup_delay 5.5
```

简单来说，就是当使用 bond （链路聚合）接口时，keepalived 会在启动时立刻抢占虚拟 IP。因为 bond 接口在启动时，会有几秒钟的延迟，这几秒钟内 keepalived 无法收到 advert，从而导致 keepalived 认为自己是 master。

## 验证与修复

在我的环境中，使用的也是 bond 接口。所以在重启的过程中，尝试 ping 正在重启的节点，并对比日志。发现在重启过程中，从 keepalived 启动，到机器能被 ping 通，中间确实有一定的延迟。基本可以确认，这个问题就是由于 bond 接口的延迟导致的。

以下是我解决问题关键的配置：
```
global_defs {
    vrrp_startup_delay 60
}

vrrp_instance xxx {
    state BACKUP
    nopreempt
}
```

### 备注
* vrrp_startup_delay: 我配置的比较保守
* state BACKUP: 这里需要所有节点全部配置为 BACKUP，nopreempt 在 BACKUP 状态下才生效
* nopreempt: 这里需要所有节点全部配置为 nopreempt
* priority: 似乎影响不大
