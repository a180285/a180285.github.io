# Ceph host 重启期间，集群没有自动恢复

现象：在生产环境重启 ceph host 节点时，会有部分 pool io 卡住。直到 host 重启正常后才恢复。

## 怀疑 Ceph 有问题

在 6 个节点的 Ceph 集群测试，重启节点时没有明显卡顿。无法复现该现象。

这就很奇怪了。但基本说明 Ceph 自己应该有恢复能力的。

## 怀疑配置有问题

对比了两个集群的配置，也没有发现不同的地方。

但是期间发现一个很奇怪的现象。就是我们把集群中的机器关机了。之前都是会被自动标记为 down。但是这次有些 osd 没有自动被标记为 down。当时只是以为是不是哪里操作不太对，没有注意到什么错误输出。就手动标记了一下 osd down.

## 缩小测试范围

随后尝试 shutdown 单个 osd 来对比两个集群的表现。

还真发现了区别：

- 小集群上手动关闭 osd 后，ceph 会几乎立刻将 osd 标记为 down。这样不会影响 pg 的正常操作
- 但大集群上，手动关闭 osd 后。ceph 没有对 osd 进行自动标记。

虽然大集群表现同样不正常。但至少给了一个突破口，毕竟大集群还有一些业务在跑，不能影响太大。单个 osd 测试的话，也会方便不少。

## 了解 ceph osd 自动标记机制

经过一番搜索，发现 Ceph 一些参数与 osd 自动标记有关

- `osd_heartbeat_grace` 默认是 20s，也就是说 20s 后 osd 应该会被标记为 down
- `mon_osd_down_out_subtree_limit` 默认为 rack。表示当整个 rack 的 osd 都 down 的时候，禁止将 osd 标记为 out。

### 对参数 mon_osd_down_out_subtree_limit  的误解

这个参数默认是 `rack` 。当时以为这个参数是说如果发现一个 rack 的 osd 都 down 后。不把对应 osd 标记为 down。想着我们没有配置 rack bucket，难道是自动 fallback 到 host 了。这样正好符合重启 host 卡住的表现。

现在回忆起来，对这个参数的错误理解比较大

- 文档没有说明当没有配置 rack bucket 时的行为表现。我现在也不知道具体表现如何，目前猜测是如果没有配置 rack bucket ，等于这个参数就不会生效。
- 另外这个参数文档说的是不会标记为 `out` 。但我遇到的问题是没有被标记为 `down`。

### 怀疑是 mon_osd_adjust_heartbeat_grace 的问题

从参数名 `mon_osd_adjust_heartbeat_grace` 也可以看出来，这个参数允许 ceph 动态调整参数 `osd_heartbeat_grace ` 参数的配置，即 osd 自动标记为 down 的时长。

然后果断关闭了这个配置。然而也并没有什么用。

## 发现罪魁祸首

还记得上面提到一下，发现最近手动关机的一些机器中的 osd 没有被自动标记为 down 吗，之前手动关机一直是好好的。这时我都怀疑是不是 ceph 运行时间太长，导致出现了什么奇怪的 bug ，是不是需要重启一下相关组件来试试了。直到发现下面两个配置参数。

- `mon_osd_min_up_ratio` 默认值 0.3。表示如果 osd up 的比例小于该值时，不会自动标记为 down
- `mon_osd_min_in_ratio` 默认值 0.75。同理，表示如果 osd in 的比例小于该值时，不会自动标记为 out

这下就合理了，因为关机太多，导致 osd up 的比例已经小于默认值 30% 了。所以当我再手动关闭 osd / host  的时候，对应的 osd 都没有自动被标记为 down 了。上面说的，最后一次手动关机的部分 osd 的状态没有变为 down 也能说通了。

至于默认值更高的 `min_in_ratio` 为什么没有对我们产生什么影响。则是因为我们是计划内关机，所以都是手动标记 osd 为 out 的。所以就没有对我们计划内关机造成影响。

修改 `mon_osd_min_up_ratio` 为更小的值后，ceph 一切都变得正常了。当我重启节点时，ceph 也能很快自动恢复了。（大概半分钟左右吧）

## 事后回顾

虽然 ceph 文档在参数项一开始就写了 `mon_osd_min_up_ratio` 相关参数，但是完全没有注意到。也是挺遗憾的，如果提前注意到，可以少走不少弯路。

最后想说一下，我感觉这个参数 `mon_osd_down_out_subtree_limit` 的文档不是很清晰，想去 github 提个 issue。发现不能在 github 提 issue ，必须去 ceph 自己的网站提。想着也行吧，那注册个账号提一下吧。结果注册账号还需要一个工作日的人工审核时间。最后想想，人家都开源了，我们又没花钱，确实也不能对它要求太高~~

# 参考

- ceph [configuring monitor/osd interaction](https://docs.ceph.com/en/latest/rados/configuration/mon-osd-interaction/)
