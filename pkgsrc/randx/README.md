# randx 0.2.0 — 随机数库（CatBase 0.1.8）

生成器为 MINSTD（x → 48271·x mod 2³¹−1，Lewis-Goodman-Miller「最小标准」LCG）：
序列可被任何具备 64 位整数的语言逐值复算对照，全部中间值 ≤ ~1.04×10¹⁴，远低于 i64 上限。语言无位运算符（已探明），故未选 xorshift。

## 种子机制（核心）

- `seed(n)`：显式整数种子，同种子必出同序列（跨语言可复算，测试含 python 逐值对照）。
- `auto_seed()`：**默认自动种子 = 当前时间戳（毫秒，`date +%s%3N`）+ 实测 ping 往返时延**，经 FNV 式乘法混合后进入生成器。ping 目标默认 `1.1.1.1`，`set_ping_target("8.8.8.8")` 可改（空串忽略）。
- **ping 不可达兜底**：超时/丢包时降级为纯时间种子，绝不崩溃；降级与否可查——`last_seed_source()` 返回 `"time+ping"` 或 `"time-only"`。实测路径：把目标设为 TEST-Net 保留地址 192.0.2.1（保证不可达），断言 `ping_latency_us() == -1`、`last_seed_source() == "time-only"`、生成器照常出数。
- `ping_latency_us()`：公开当前实测时延（微秒整数），供使用方落盘熵源证据。
- 时延解析说明：ping 输出 `time=2.220 ms`，语言无可靠 str→float（v0.1.8 codegen 缺陷，已探明），故按**整数微秒**解析（"2.220" → 2220，小数位归一化补齐到 3 位）。

## API

| 函数 | 说明 |
|---|---|
| `random() -> float` | [0,1) 均匀浮点 |
| `randint(a,b) -> int` | [a,b] 含两端，**无偏**（拒绝采样，尾部丢弃；100 次拒绝后回退普通取模——实测从未触发，接受率 ≥ 1−n/2³¹） |
| `below(n)` / `between(a,b)` / `chance(p)` / `die6()` | 0.1.0 兼容面（below/between 现走无偏路径） |
| `uniform(lo,hi) -> float` | [lo,hi) 均匀浮点 |
| `pick(lst)` | 随机取一个元素 |
| `sample(lst,k)` | 不放回抽 k 个（交换删除法，原列表不动） |
| `shuffled(lst)` / `shuffle_ints(xs)` | Fisher-Yates 洗牌（返回新列表 / 原地 int 列表） |
| `rand_str(n)` / `rand_bytes_hex(n)` | 随机字符串（[a-z0-9]，`set_alphabet` 可换）/ 随机字节十六进制串 |
| `normal()` / `normal_mu_sigma(mu,sigma)` | 标准正态（Box-Muller，复用 mathx 的 ln/cos/sqrt_float/PI） |
| `poisson(lam) -> int` | 泊松分布（Knuth 法，复用 mathx.exp） |
| `seed(n)` / `auto_seed()` / `last_seed_source()` / `set_ping_target(t)` / `ping_target()` / `ping_latency_us()` / `set_alphabet(a)` | 种子与熵源管理 |

依赖：`mathx ^0.5.0`（正态/泊松用其 ln/cos/exp/sqrt_float/PI；只装基础 API 时 mathx 也会被解析器作为依赖装入——按 catpm 协议全闭包装配）。

## 兼容性（如实记录）

- 0.1.0 的 `seed/below/between/chance/pick/die6/auto_seed` 名字与语义保留；`auto_seed` 从纯时间种子升级为时间+ping 混合（`auto_seed_time()` 保留旧名别名）。
- **破坏性变更**：同一显式种子下的序列与 0.1.0 不同（生成器从 LCG-mod-2³² 换为 MINSTD，为了可跨语言验证与更好的低位质量）；0.1.0 已知缺陷（below(2) 因低位周期性输出 0101…）在本版修复。

## 质量验证（全部真跑，日志 `logs/randx-build.log`）

1. 固定种子复现：seed(42) 两次生成完整序列逐值一致；raw 流与 python 独立实现逐值对照（seed 1/0/-5）。
2. 默认熵源生效：连续 6 次 auto_seed，ping 时延样例 1750–3430 µs 波动、序列两两不同（种子值/时延/首抽值落盘）。
3. 统计抽查：randint(1,100) × 100,000 次，χ²=104.05（df=99，α=0.05 接受域 [67.33, 134.64]），min/max bin 927/1067；random() 10 万次均值 0.50096（|mean−0.5| < 2σ）；上下界边界值命中且不越界；正态 mean≈0.0057/var≈0.9944；泊松(4) 均值 4.0032。
4. ping 不可达兜底实测（见上）。

## 明确不做

- 加密安全随机（CSPRNG）：无系统熵源接口（/dev/urandom 经 exec 可读，但语言无字节串原语，逐字节读效率不成样子且仍非密码学实现）——安全场景请用系统工具。
- Mersenne Twister 等更重生成器：MINSTD 已通过上述全部统计检查，重生成器收益配不上纯算术实现的复杂度。
