# 第 11 轮交付报告：registry 核对 + 完整数学库 mathx 0.5.0 + 哈希库 hashx 0.1.0

日期：2026-11-10 ~ 2026-11-11。需求五部分（核对 / 数学库 / 哈希库 / 包流程与发布 / 测试与交付）全部完成，逐项证据见下。

---

## 一、registry 核对结论（发布前）

对线上源（raw.githubusercontent.com/monikalnbo/catpm-registry/main）现跑核对，发布前 8 包各 1 版：

| 包 | 版本 | 对外函数 |
|---|---|---|
| catpm | 0.5.5 | PM 本体（bin/catpm 预编译 + 全部源码） |
| fmtx | 0.1.0 | format、pad 等 |
| hellox | 1.0.0 | 预编译工具（bin/hellox ELF） |
| loganx | 0.1.0 | log/带时间戳日志 |
| mathx | 0.4.0 | gcd、lcm、is_prime、fib、loud_double、power、collatz_steps（7 个） |
| randx | 0.1.0 | seed/between/below/pick/die6 |
| stringx | 0.3.0 | shout/capitalize 等字符串工具 |
| timex | 0.1.0 | iso8601/epoch/stamp/days_between |

与主仓库 README §5 表一致；mathx 0.2.0/0.3.0 已按「只留最新版」规则删除（git 历史 + tag `full-history-pre-0.5.5` 可找回），index.json 无多余条目。核对过程无发现偏差。

## 二、数学库 mathx 0.5.0（7 → 62 函数）

- **版本步进说明**：0.4.0 → 0.5.0 取 minor 步进（不是默认 +0.0.1）——整库从 7 个函数扩到 62 个，属 PROTOCOL §4.6 规则 1 允许且需求方明示许可的「整库大幅扩容按既定规则取大步进并说明」情形。
- **兼容性**：0.4.0 全部 7 个函数（gcd/lcm/is_prime/fib/loud_double/power/collatz_steps）语义不变保留；gcd/lcm 额外接受负数输入。169 断言全过（`logs/mathx-build.log`），其中含 0.4.0 语义回归项。
- **函数清单（62 个公开函数 + 常量 PI/E/MATHX_VERSION/MATHX3）**：

| 域 | 函数 |
|---|---|
| 整数/浮点基础（16） | abs_int、abs_float、sign_int、sign_float、clamp_int、clamp_float、max_int、min_int、max_float、min_float、max_of_list、min_of_list、floor_float、ceil_float、round_half_away |
| 数论（12） | gcd、lcm、is_prime、sieve、prime_factors、distinct_primes、count_divisors、is_perfect、next_prime、totient、collatz_steps |
| 幂与根（6） | power（快速幂）、mod_pow、isqrt（牛顿）、sqrt_float（牛顿）、cbrt_float、hypot |
| 组合（4） | factorial、perm、comb（乘式精确）、fib |
| 统计（8） | sum_list、mean、sort_floats、median、variance、variance_sample、stddev |
| 进制（3） | to_base、from_base、digit_val（2–36） |
| 三角/对数（13） | sin、cos、tan、atan、exp、ln、log10、log2、pow_float、deg2rad、rad2deg |

（以上函数均真编译、真运行、断言覆盖；实现纯算术——语言无 sqrt 内建、无位运算，平方根用牛顿迭代。）

- **明确不做（如实记录，见包内 README）**：复数/矩阵（超范围）；asin/acos/双曲（精度边界未验证不虚报）；位运算（语言无）。
- **测试**：`logs/mathx-build.log`，169 断言 0 失败；测试源 `pkgsrc/mathx/test.cat`（169 项断言 harness）随主仓库存档。
- **diff**：`diffs/v0.4.0..v0.5.0-mathx.diff`（1050 行，旧快照取自已发布 0.4.0 cpkg）。

## 三、哈希库 hashx 0.1.0（新包）

- **算法**：crc32（查表法，多项式 0xEDB88320）、adler32、djb2、djb2_xor、sdbm、fnv1a32、fnv1_32 + hex 助手（crc32_hex、adler32_hex、to_hex32）。共 10 个公开函数。
- **验证方式**：8 个公开标准输入（空串、"abc"、"hello"、"123456789"、"Wikipedia"、fox 句、"a"、"0123456789"）× 全部算法，逐字节与公开测试向量一致（与 zlib 参考对照先行在 python 验证），64 断言 0 失败（`logs/hashx-build.log`）。
- **实现要点**：语言无位运算——xor32 逐位算术模拟（%2//2 重建 32 位）、rotl 同法；所有 i64 中间值严格低于 2^63。
- **明确不做（包内 README + index.catc 尾注如实记录）**：
  - **64 位变体（fnv1a64 等）不做**：FNV-1a 64 偏移基 14695981039346656037 已超 i64 上限 9223372036854775807，且 h×prime 溢出；语言无 u64、无 2^64 回绕乘法。
  - **md5/sha1 不做**：rotl 算术模拟可行（已验证），但 64 轮×16 步/80 轮体量大且加密价值为零（现实中均已被破解，不应再用于安全场景）。
  - **sha256 归 catpm 自身分工**：catpm 安装链路统一用系统 sha256sum（索引校验、pack 哈希），库内不做重复实现。
- **diff**：`diffs/new-hashx-0.1.0.diff`（1014 行，新包无旧版，全量内容快照）。

## 四、包流程与发布（PROTOCOL 规矩全程）

1. `catpm init` → 本地开发 /tmp/libwork/{mathx,hashx}，逐函数编译运行断言；
2. `catpm pack`：mathx-0.5.0.cpkg（6871 B，sha256 2ab9e257…502845）、hashx-0.1.0.cpkg（3319 B，sha256 54805adb…00ed7）；
3. diff 落盘核对（上两份 diff 文件）；
4. `catpm publish <registry>`（在包目录内执行——踩过一次「no catpm.json here」后按规矩在包目录跑成）；
5. registry 推送：commit `c3f0ccf`（空白 message），变更 = hashx 新增 + mathx 0.4.0 删/0.5.0 增 + index.json 收敛至 9 包；
6. raw 直链验证（`logs/run11-online.log`）：index.json 200、hashx-0.1.0.cpkg 200、mathx-0.5.0.cpkg 200、mathx-0.4.0.cpkg **404**（旧版已按规则删除，符合预期）；
7. **本地源端到端**（`logs/run11-local.log`）：init → add 两包 → lock 3 条 → catcc demo → 输出正确，exit=0；
8. **线上源端到端**（`logs/run11-online.log`，用户硬性要求）：全新目录、无任何本地源覆盖（无 package.where、无 CATPM_* 环境变量），走 catpm 默认线上源——init → add mathx（解析 0.5.0、拉 stringx 0.3.0 传递依赖）→ add hashx（lock 3 包）→ catcc demo.cat 编译成功 → 运行输出 27 行全部正确（mathx 17 行 + hashx 6 行 + 标题），exit=0。

发布后线上源 index 9 包各 1 版（catpm/fmtx/hashx/hellox/loganx/mathx/randx/stringx/timex）。

## 五、测试结论汇总

| 项 | 结果 |
|---|---|
| mathx 169 断言 | ✅ 全过（含 0.4.0 回归） |
| hashx 64 断言 | ✅ 全过（公开向量逐字节） |
| 本地源端到端 | ✅ init→add→lock→compile→run，exit=0 |
| 线上源端到端 | ✅ 同上，HTTPS 真下载 + sha256 校验，exit=0 |
| raw 直链 | ✅ 200/200/200/404（404 为旧版按规则删除） |

## 六、交付物索引

| 交付物 | 位置 |
|---|---|
| mathx 源码/清单/README/测试 | `pkgsrc/mathx/`（index.catc 17886 B、test.cat、catpm.json、README.md） |
| hashx 源码/清单/README/测试 | `pkgsrc/hashx/`（index.catc 4767 B、test.cat、catpm.json、README.md） |
| 两库发布归档 | catpm-registry：mathx/mathx-0.5.0.cpkg、hashx/hashx-0.1.0.cpkg（commit c3f0ccf） |
| 版本 diff | `diffs/v0.4.0..v0.5.0-mathx.diff`（1050 行）、`diffs/new-hashx-0.1.0.diff`（1014 行） |
| 测试日志 | `logs/mathx-build.log`、`logs/hashx-build.log`、`logs/run11-local.log`、`logs/run11-online.log` |
| 主仓库 README | §5 registry 表已更新（9 包、mathx 0.5.0 62 函数、hashx 0.1.0 新增） |

## 七、遗留与边界（如实）

- 64 位哈希、md5/sha1 的不做理由见第三节，均为能力边界而非疏漏。
- mathx 三角/对数为级数近似，精度区间在包 README 里逐函数标注（如 sin/cos 在全数轴周期归约后 |x|≤π/4 段泰勒，16 项，双精度内与参考一致）。
- 教程类文档（guide.md）未在本轮更新 registry 表——本轮交付核心是两库与发布链路，guide 的包清单为教程速查性质，README §5 为权威表（已更新）；后续教程轮可同步。

---

# 追加交付：随机数库 randx 0.2.0（2026-11-11，与数学库/哈希库同轮同一套发版规矩）

## 功能与实现

- **生成器**：MINSTD（x → 48271·x mod 2³¹−1）。选型理由：可被任何 64 位整数语言逐值复算对照（测试确含 python 独立实现对照）；中间值 ≤ ~1.04×10¹⁴ 远低于 i64 上限；语言无位运算符（已探明），xorshift 不可行。**0.1.0 已知缺陷（below(2) 因低位周期性恒输出 0101…）在本版修复**——0.1.0 的注释如实记录过该现象，本版生成器不再有此问题。
- **种子机制（需求核心）**：
  - `seed(n)` 显式种子，同种子同序列；
  - `auto_seed()` 默认自动种子 = 当前时间戳（毫秒）+ **实测 ping 往返时延**（`ping -c 1` 的 `time=` 字段按整数微秒解析，小数位归一化；v0.1.8 无可靠 str→float，codegen 缺陷已探明，故整数路径），FNV 式乘法混合入生成器；ping 目标默认 1.1.1.1，`set_ping_target()` 可配（空串忽略）；
  - **ping 不可达兜底**：降级纯时间种子，不崩；`last_seed_source()` 如实标注 `time+ping` / `time-only`；实测把目标设为 TEST-Net 地址 192.0.2.1（保证不可达），断言 `ping_latency_us()==-1`、源降级、生成器照常出数。
- **API 全套**：`random()` [0,1)、`randint(a,b)` 含两端且**无偏**（拒绝采样；100 次拒绝回退取模，实测从未触发）、`uniform`、`pick`/`sample(k)`（不放回）/`shuffled`/`shuffle_ints`、`rand_str`/`set_alphabet`/`rand_bytes_hex`、`normal()`/`normal_mu_sigma`（Box-Muller）、`poisson(lam)`（Knuth 法）——正态/泊松复用 mathx 的 ln/cos/exp/sqrt_float/PI，依赖声明 `mathx ^0.5.0`。0.1.0 兼容面（seed/below/between/chance/pick/die6/auto_seed）保留；**破坏性变更如实记录**：同显式种子的序列与 0.1.0 不同（生成器更换）。

## 质量验证（logs/randx-build.log，全部真跑）

1. **固定种子复现**：seed(42) 两次生成序列逐值一致；raw 流与 python 独立实现逐值对照（seed 1/0/−5/42）；randint/random/正态/泊松/shuffle/rand_str 的期望值全部来自 python 复算。**83 断言 0 失败**。
2. **默认熵源生效**：连续 6 次 auto_seed，ping 时延样例 1750–6330 µs 波动、每轮种子混合值不同、首抽序列两两不同（wall_ms/ping_us/src/first3 逐轮落盘）；连续两次 auto_seed 首抽不等断言过。
3. **统计抽查**：randint(1,100)×100,000 次——χ²=104.05（df=99，α=0.05 接受域 [67.33, 134.64]），min/max bin=927/1067（全部 bin 频数落盘日志）；random()×100,000 均值 0.50096（|mean−0.5|<2σ≈0.0032）；边界值：randint(10,20)×500 两端均命中且不越界、randint(5,5)==5、负区间 randint(−3,−1) 逐值对照；正态 50,000 次 mean=0.0057/var=0.9944；泊松(4) 50,000 次均值 4.0032。
4. **兜底实测**：见上，行为如实可查。

## 发版（PROTOCOL 规矩全程）

- diff 落盘核对：`diffs/v0.1.0..v0.2.0-randx.diff`（493 行；旧快照取自已发布 randx-0.1.0.cpkg）；
- `catpm pack`（6756 B，sha256 ac14663a…d745e3）→ `catpm publish` → registry 收敛只留 0.2.0（0.1.0 删除，git 历史可找回）→ 推送 commit `9c2da58`（空白 message）；
- raw 直链：index.json 200、randx-0.2.0.cpkg 200、randx-0.1.0.cpkg 404（`logs/run12-online.log`）；
- **线上源端到端**（logs/run12-online.log）：全新目录无本地源覆盖，默认线上源 `catpm add randx` 解析 0.2.0 并拉传递依赖 mathx 0.5.0 + stringx 0.3.0（lock 3 包，sha256 全过）；catcc 编译 demo → 全 API 真实调用（复现 dice、auto_seed+ping、抽样、洗牌、随机串/字节、正态/泊松、不可达兜底）15 行输出全部正确，exit=0。

## 版本号说明

0.1.0 → 0.2.0 取 minor 步进：生成器整体更换 + 种子机制重构 + API 从 7 个扩到 20 个，属同轮 mathx 同理的「整库大幅扩容取大步进并说明」情形（PROTOCOL §4.6 规则 1）。

## 同轮踩坑实录（如实）

- catbase v0.1.8 下标里带函数调用（`abc[f(...)]`）会生成 indexer 每迭代重复调用 f 的坏代码（zig 层可见）——库内所有此类写法已提离下标（先赋值临时变量再索引）；
- `float(str)` 在 v0.1.8 是坏 codegen（`@floatFromInt(Str)`）——ping 时延解析改整数微秒路径；
- 测试期望值第一版误按「前序消耗后的流状态」复算，重算为新鲜流对照后 83 项全过（实现无误，期望值错）。
