# Round 10 报告：性能对标 + 仓库/发版规范

日期：2026-11-10。版本：v0.5.5（与第 9 轮中断恢复合并发版）。全部数字为本机同环境真实测量，方法与样本数随表给出；跑不动/缺工具的场景如实标注。

## 一、性能对标 apt 与 cargo（实测）

### 方法

- **计时**：`date +%s%N` 纳秒墙钟；冷装场景每次全新 `mktemp -d` 项目目录；n=5 或 n=7 取中位数；版本间对照用**交错 A/B**（同一循环内交替跑两版，逐对差值）。
- **子进程画像**：本机无 strace/hyperfine，用 PATH spy（包装 curl/sha256sum/tar/cp/mv/rm 记日志后 exec 原二进制）+ 时间戳 spy（还原各阶段时间线）。
- **对照工具**：apt（本机 dpkg 真实执行）、cargo（本机 rustc 真实编译，依赖集与仓库生态同规模：tinystr + cfg-if）。

### 结果（中位数）

| 操作 | apt | catpm v0.5.5 | 样本 |
|---|---|---|---|
| 刷新索引 | `apt-get update` **1913 ms** | `catpm update` **106 ms**（HTTPS 单源）/ 61 ms（本地源） | 各 n=5 |
| 冷装一个小包（含依赖） | `apt-get install --reinstall hello` **7134 ms** | `catpm add mathx`（2 包闭包，HTTPS）**301 ms** | apt n=5 / catpm n=5 |
| 已装列表 | `apt list --installed` **531 ms**（`dpkg -l` 30 ms） | `catpm list` **5 ms** | 各 n=5 |

| 操作 | cargo | catpm v0.5.5 | 样本 |
|---|---|---|---|
| `add`（只写清单） | `cargo add` **645 ms** | 并入 `catpm add`（写清单+装） | n=5 |
| 冷构建 2 依赖 | `cargo build` **12,374 ms** | —（catpm 装包即完成，不编译） | n=5 |
| 热构建 2 依赖 | `cargo build` **10,990 ms** | `catpm add` 全缓存重装 **122 ms** | n=5 |
| 冷装 2 包闭包 | —（等价物即 build） | HTTPS **301 ms** / 本地源 **158 ms** | n=5 / n=7 |

catpm 与 cargo 的工作量不同（catpm 不编译），对比目的是「装好一套能 import 的依赖」的用户可感时延量级差：30–40 倍。详见 `docs/perf.md`。

### 落后点定位（时间戳 spy）与优化

v0.5.4 冷装 2 包 = 7 个子进程 fork；时间线显示时延大头在串行 curl（HTTPS）与逐包 sha256sum。五项优化落地：

| # | 改动 | 效果 |
|---|---|---|
| 1 | 并行预取（仅 URL 源；本地源进程内复制零 fork） | 多包 HTTPS 串行下载变并发 |
| 2 | 批量哈希 + 进程内复用（psha，仅内存不落盘） | 每包省 1 次 sha256sum fork |
| 3 | 索引缓存路径 memo（每进程一次） | 每次运行省 1-2 次 printf\|sha256sum fork |
| 4 | 原子写跳过未变内容 | 幂等重跑省全部 tmp+mv fork |
| 5 | 合并 sh 调用（清 stage+解包、删旧+换入） | 每包省 2 次 sh fork |

**如实结果（交错 A/B 成对差值）**：

| 场景 | v0.5.4 | v0.5.5 | 差 |
|---|---|---|---|
| 冷装 2 包闭包（本地源） | 115–133 ms | 148–158 ms | **+30~40 ms（v0.5.5 慢）** |
| 冷装 6 包闭包（本地源，3 次 add） | 401–441 ms | 464–524 ms | **+60~90 ms（v0.5.5 慢）** |
| 冷装 2 包闭包（HTTPS raw 源） | 298–341 ms | 268–301 ms | **−30~40 ms（v0.5.5 快）** |

本地源变慢不掩饰：v0.5.5 中断恢复机制（原子写 + 暂存解包，第 9 轮特性）每装一次多 4-6 次 fork（~40-60 ms），这是鲁棒性换时延的既定取舍；并行预取在 HTTPS 源上净赚 30-40 ms。过程插曲（如实记录）：prefetch 初版对本地源也用 `cp` fork，交错 A/B 当场暴露回归（本地源慢 40 ms），已回退为进程内复制。

**安全不变量保持**：psha 只在同一进程内复用预取阶段真实算出的哈希（内存 dict，不落盘，无可伪造工件）；换进程/未预取/重拉后的新字节仍走真实 sha256sum。篡改缓存实测仍被拦截并自愈重拉。

### 回归验证

62 断言全过；e2e_v9 中断恢复矩阵（fix 清扫六类残留/截断 manifest 拒绝/缓存自愈/kill -9×3 场景/断网/随机强杀×45 零违规/A-B 一致性/离线 STALE）用最终二进制全量重跑通过。日志 `logs/build9.log` + `logs/run9.log`。

场景 [7/9] 有一行 `add while offline -> exit=0 (expected nonzero)` 核实说明：kill 发生在 0.9 s 时索引与包缓存已完整落盘，离线 + 完整缓存可装正是 [9/9] 验证的设计特性（v0.5.5 索引缓存语义），不是回归；另做了真离线无缓存对照实测：exit=1 如预期。

## 二、仓库与文档规范（已写进 PROTOCOL §4.6a，长期规则）

- **commit message 一律空白**（`git commit --allow-empty-message`）或至多一个极短词；一切说明写文档（README / PROTOCOL / docs/ / logs/ / reports/）。
- 本轮落地：registry 提交为空白 message（amend 修正 author 为 monikalnbo）；主仓库同样。
- 文档补齐：`docs/perf.md`（性能实测全记录）、`docs/registry.md`（源操作手册）、`docs/release.md`（发版 checklist + registry 只留最新版操作细节）；README 增加安装/快速上手/全部命令/配置/缓存与 self-update/发版协议/性能说明各节与 docs/ 索引。

## 三、发版产物规范（已写进 PROTOCOL §4.6b，长期规则）与本次执行记录

规则：registry 每包只留最新版 `.cpkg`；老版本从 git 历史找回；发布产物为完整整包；替换一律全量。

本次执行（2026-11-10）：

1. 删前打 tag：`full-history-pre-0.5.5`（最后含全部老版本的树）并推送。
2. 删除 8 个老版本 cpkg：catpm 0.4.0/0.5.0/0.5.1/0.5.2/0.5.3/0.5.4 + mathx 0.2.0/0.3.0；index.json 收敛为每包单版本。
3. publish catpm 0.5.5（194,824 B，sha256 `bd986c3e…`）。
4. registry 一次推送成功（空白 message commit `8f08f8b`）。
5. raw 直链验证：index.json 与 catpm-0.5.5.cpkg 均 200；CDN 传播后 index 只含 catpm 0.5.5 / mathx 0.4.0。
6. **删旧影响实测**：`add mathx@0.3.0`（线上）exit=1 如实报错；`add mathx@0.4.0` 正常。**找回路径实测**：`git show full-history-pre-0.5.5:mathx/mathx-0.3.0.cpkg` 取回 + 自建本地目录源（含 index.json）→ `add mathx@0.3.0` 成功安装（sha256 校验通过）。注意（文档已写）：找回目录必须有 index.json，且 `.catpm-cache/` 里有旧索引会导致 not found——清缓存即可。
7. **self-update 全量替换实测**：从 registry 历史取回 0.5.4 二进制（sha 与旧 index 一致）→ 线上 self-update → 下载 0.5.5 → sha256 ok → 候选验证 → 全量替换 → `--version` 报 0.5.5。
8. install.sh / install.fish 版本注释与 README 安装节从 catpm54 更新为 catpm55。

## 四、发版 diff 核对（v0.5.4..v0.5.5）

- 快照来源：上一版从已发布 `catpm-0.5.4.cpkg` 解出（sha `12e3080f…` 与 registry 旧 index 一致）；新版源 = src2 定稿。
- diff 共 997 行（+622/−161），落盘 `diffs/v0.5.4..v0.5.5.diff`；util.catc / ver.catc 两版完全相同。
- 逐块人工核对：新增函数全部对应第 9 轮中断恢复特性（atomic_write / refetch_cpkg / sweep_self_residues / cmd_fix 等）与第 10 轮性能优化（prefetch_all / psha / idx 路径 memo / 合并 sh），无未预期漂移。

## 五、curl|sh 新装实测与收尾状态

- 主仓库推送：commit `3a4cd32`（`0.5.5`，源码/二进制/diff/docs/logs/reports 全量）。
- raw 验证：`catpm/catpm55` 与 `install.sh` 均 200。
- **curl|sh 新装实测**：`curl -fsSL .../install.sh | sh` 全新环境 → 装出 `catpm 0.5.5 (for CatBase 0.1.8)` + 同目录 package.where；随后全新项目 `catpm add mathx` 从线上源正常安装（stringx+mathx，sha256 ok，写 lock）。新装拿到的就是新版，符合发版要求。
- registry 仓库本轮起进入「只留最新版」稳态；下次发版按 `docs/release.md` checklist 执行。

## 六、本轮交付物清单

| 交付物 | 位置 |
|---|---|
| 性能优化源码（v0.5.5 定稿） | `catpm/src2/catpm.cat` |
| 二进制 | `catpm/catpm55`（324,976 B，sha256 `d4a07ef2…`） |
| 版本 diff | `diffs/v0.5.4..v0.5.5.diff`（997 行，+622/−161，已逐块核对） |
| 性能报告 | `docs/perf.md` + `logs/perf-final.log` + `scripts/perf_v10.sh` |
| 规范文档 | `PROTOCOL.md` §4.6a/§4.6b、`docs/release.md`、`docs/registry.md` |
| 中断恢复实测（重跑） | `logs/build9.log` + `logs/run9.log` |
| 本报告 | `reports/round10-report.md` |
| registry 发布 | catpm-registry commit `8f08f8b`（catpm 0.5.5，8 个老版本 cpkg 已删，tag `full-history-pre-0.5.5` 留档） |
