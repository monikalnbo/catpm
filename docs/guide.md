# catpm 使用指南（教程）

仓库内有两份教程文章，按时间顺序阅读：

1. **上手篇**：怎么装到手、怎么 add/remove、怎么做包发布、怎么更新依赖与自身——覆盖 v0.5.0 时代的基础四块。
2. **进阶篇**（v0.5.5 新增）：apt 式 update/upgrade 分工与索引缓存、任意时刻被杀重跑即续的中断恢复、self-update 日常节奏、性能优化叙事、成文的发版规矩。

两篇都以真实命令与实测日志为据（各文末附出处清单），教程中的命令随版本演进可能微调，**权威用法以 [README.md](../README.md) §3 命令清单为准，协议细节以 [PROTOCOL.md](../PROTOCOL.md) 为准**。

## 上手篇要点速查

- 安装：`curl -fsSL https://raw.githubusercontent.com/monikalnbo/catpm/main/install.sh | sh`（fish 用 `install.fish | source`）；装完 `catpm --version` 验证。
- 日常：`catpm init` 建清单，`catpm add mathx` 装包并写锁，`catpm install` 按锁精确还原（同 npm ci），`catpm remove mathx` 移除并清孤儿传递依赖。
- 版本说明符：`mathx@1.2.3` 精确、`mathx@^1.2.0` 范围、`mathx@>=0.2.0,<0.4.0` 逗号 AND、`mathx@*` 任意取最高。
- 做包：包目录放 `catpm.json` + `index.catc`，`catpm pack` 出 `dist/<name>-<ver>.cpkg`，`catpm publish <registry 检出>` 合并索引，`git push` 即发布。
- 源：`package.where` 一行一源，`prio=N` 定优先级、`pkg=a,b` 钉定包名；`catpm sources` 查可达性。详见 [registry.md](registry.md)。

## 进阶篇要点速查（v0.5.4–v0.5.5）

- **update ≠ upgrade**：`catpm update` 只刷新索引缓存不装包（apt update 语义）；`catpm upgrade` 重解析重写锁再安装（apt upgrade 语义）。读命令 TTL 内走缓存；某源死掉保留旧缓存打 `PARTIAL FAILURE`；读时源不可达回退旧缓存打 `STALE` 照常装。
- **中断恢复**：任意时刻 kill -9 / Ctrl+C / 断网，磁盘不留半写状态，重跑同一命令自愈；`catpm fix` 显式清扫六类残留。机制四层：原子写（tmp+mv）、暂存解包（`.stage-`）、缓存自愈（先验 sha256）、读侧防护（截断文件明确报错）。
- **self-update 日常**：`catpm --version` 有新版本提示就跑 `catpm self-update`；sha256 门 + 候选冒烟 + 原子替换，失败旧版零接触。
- **性能**：实测方法与全部数据见 [perf.md](perf.md)；URL 源并行预取、批量哈希、合并子进程调用；本地源为中断恢复多付一点子进程成本（既定取舍，文档如实记录）。
- **发版规矩**：版本号 +0.0.1；commit 一律空白或极短词；说明全写文档；registry 只留最新版完整产物（老版本 git 历史找回）；发版前 diff 落盘核对；版本替换全量整包。checklist 见 [release.md](release.md)。
