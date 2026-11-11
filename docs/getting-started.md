# catpm 上手指南（Getting Started）

面向第一次点开本仓库的读者，四件事讲完：catpm 能干什么、怎么安装、装完之后每一步怎么做（重点——照着走到第一个能跑的程序）、以及它能帮你做什么；最后再补一节进阶——怎么挂上你自己的包仓库。文中每条命令与回显都来自真实仓库与实测日志（本次逐条复验存档于 `logs/getting-started.log`，其余出处见文末）；权威命令清单以 [README.md](../README.md) §3 为准，协议细节以 [PROTOCOL.md](../PROTOCOL.md) 为准。

## 一、它能干什么

catpm 管的事，和 pip 之于 Python、npm 之于 Node 是同一件：让项目声明依赖，然后替你解析、下载、校验、锁定、安装。

命令集一口气就能数完。`catpm init` 建项目清单；`catpm add mathx` 装包，版本想怎么钉都行——精确的 `mathx@0.2.0`、范围的 `mathx@^0.2.0`（npm 的 caret 语义，`~`、`>=`、`<` 同理）、多个条件逗号 AND 的 `mathx@'>=0.2.0,<0.4.0'`、任意取最高的 `mathx@*`。解析会把传递依赖的闭包全部装进项目的 `deps/`，每个包下载后过 sha256 校验，结果写进给人看的纯文本锁文件 `catpm.lock`。日常动词：`catpm install` 认锁精确还原（npm ci 的脾气）；`catpm update` 只刷新索引缓存、不装包（apt update 的语义）；`catpm upgrade` 重解析、重写锁、装上新版（apt upgrade 的语义）；`catpm outdated` 看谁有新版；`catpm list` 列家底；`catpm remove` 删直接依赖并顺手清掉没人需要的传递依赖。

源这件事它学的是 apt：`package.where` 一行一个源，可以设优先级、也可以把某个源钉给特定的包；多源时候选版本取并集，下载按优先级从高到低试、失败自动降级。而且源不需要服务器——本地目录和 GitHub raw URL 都行，所以包仓库就是一个普通的 GitHub 仓库（[monikalnbo/catpm-registry](https://github.com/monikalnbo/catpm-registry)，与本仓库分离，本仓库只留工具本体）。

做包发版也是闭环：`catpm pack` 把当前目录打成 `.cpkg`（tar.gz，附 sha256），`catpm publish <registry 目录>` 把归档复制进源并自动维护 `index.json`；发布给全世界就是 pack、publish、git push 三步。

最有性格的一件事留到最后：`catpm self-update`。catpm 本体也是源里的一个普通包（包名就叫 `catpm`），更新自己走的是和更新依赖完全相同的解析与校验路径——像 apt 从自己的源里装 apt。替换前先过哈希门，再给候选二进制做冒烟测试，全部通过才做一次原子换文件。

新近版本还补了几块硬骨头：预编译二进制包、索引缓存加新版本提示、远程包并行预取，以及中断恢复——装到一半被杀、断网，重跑同一命令就能自愈（实测记录见 `logs/run11-local.log`；进阶细节看 [guide.md](guide.md) 的进阶篇速查与 [perf.md](perf.md)）。

边界也要如实说：二进制只出了 x86_64 Linux 的 ELF，别的平台没移植过；没有全局安装，也没有隔离沙箱，依赖永远装在项目内；说明符是挑选过的子集（`1.x`、`||`、`~=`、预发布后缀都不支持）；0.4.0 及更早的版本没有 self-update 子命令。

## 二、怎么安装

主仓库在这里，包装在 catpm-registry——你只需要装前者。sh、bash、zsh 共用同一份 POSIX 脚本：

```sh
curl -fsSL https://raw.githubusercontent.com/monikalnbo/catpm/main/install.sh | sh
```

fish 用户用仓库里的 `install.fish`，同款写法把结尾换成 `| source`。

脚本会把编译好的二进制和一份 `package.where` 源清单一起放进 `~/.local/bin`（想装别处，先设 `CATPM_INSTALL_DIR`）。清单放在二进制旁边是故意的：catpm 找源时优先读二进制旁边那份，而它默认就指向 catpm-registry——装完即配好，不需要设任何变量。如果目标目录还不在 PATH 里，脚本会把该加的那行按你的 shell 直接打出来：bash 和 zsh 都是 `export PATH="$HOME/.local/bin:$PATH"`，fish 是 `fish_add_path ~/.local/bin`。照抄进对应配置文件、重开终端即可。

验证就两条：`catpm --version` 应回 `catpm 0.5.5 (for CatBase 0.1.8)`；`catpm sources` 里 GitHub 源的状态应显示 ok。

如实说：安装脚本在 sh、bash、zsh、fish 四种 shell 里都做过语法检查、真装过一遍并逐个验证了版本输出（`logs/run4.log` [5/6]）；但交互式登录会话里的持久 PATH 只提供了写法，没有逐个登录实测。不想用脚本也行——手动把二进制和 `package.where` 两个文件放进同一目录，或者用 CatBase 工具链的 catcc 从源码把它编译出来。

## 三、装完之后：一步一步，走到第一个能跑的程序

下面每一步都按「做什么、敲哪条、会发生什么、你会看到什么」来讲，顺序就是实测流程本身（`logs/getting-started.log`，对线上 v0.5.5 逐条复验）。找一个新目录当项目根，开始。

**第一步，建项目。** 敲 `catpm init`。它会回 `catpm: created catpm.json`，再提一句让你用 add 装依赖。此刻项目里只有一个清单文件 `catpm.json`。

**第二步，装第一个包。** 敲 `catpm add timex`——这是真实发布在 catpm-registry 上的包，提供基于 POSIX date 的真实时间函数。它会先回 `added timex 'latest' to catpm.json (resolves to 0.1.0)`，然后开始解析：timex 自己声明依赖 stringx，于是你看到 `resolved 2 package(s)`；接着两个包并行预取（屏幕上是 `prefetch` 行），再逐个回 `installed timex@0.1.0 (sha256 ok)` 这样的行——包名、版本、校验结论都在里面；最后 `catpm: wrote catpm.lock`。此刻项目里多了 `deps/timex/`、`deps/stringx/` 两份源码和一份锁。

**第三步，在代码里用起来。** 新建 `main.cat`，引用包就是一行相对导入，别名必须等于包名（catcc 的硬约束）。实测用的验证程序长这样，连标题行一起原样保留：

```catbase
import ./deps/timex/index.catc as timex
import ./deps/stringx/index.catc as stringx

def main() {
    print("== tutorial verify: timex from catpm-registry ==")
    print("timex.iso8601() = ", timex.iso8601())
    print("timex.stamp('hi') = ", timex.stamp("hi"))
    print("stringx.shout('ok') = ", stringx.shout("ok"))
}
```

**第四步，编译并跑起来。** 编译用的是 CatBase 的编译器 catcc（语言在 [monikalnbo/catbase-lang](https://github.com/monikalnbo/catbase-lang)；catpm 管包，catcc 管编译，两件事分开）。敲 `catcc main.cat -o app`，它回 `Compilation successful.`；再敲 `./app`，屏幕上就是那几行——标题行，然后 `timex.iso8601() =  2026-11-11T05:14:38Z`（真实 UTC 时间，每次运行都不一样）、`timex.stamp('hi') =  [05:14:38] hi`、`stringx.shout('ok') =  OK!`，程序正常退出。你的第一个 catpm 程序跑起来了：它调用的 timex，是从 GitHub 下载、经 sha256 校验后装进 `deps/` 的。

**第五步，看看家底。** 敲 `catpm list`，它列出已装的 stringx 与 timex 及各自版本；敲 `catpm outdated`，它逐包对比源里的最新版——刚装完当然都是新的，回一句 `(all up to date)`。

**第六步，不想要就删。** 敲 `catpm remove timex`：它回 `removed timex from catpm.json`，然后把没人再需要的传递依赖一并清掉——你会看到 `pruned deps/stringx (no longer needed)` 和 `pruned deps/timex (no longer needed)`，锁同步重写为空。如果你想删的只是别人的传递依赖，它会拒绝你——实测里 timex 作为 randx 的传递依赖时，回的是 `timex is not a direct dependency`（`logs/run4.log` [2/6]）。

**第七步，依赖更新。** 这对命令从 v0.5.4 起是 apt 的分工：`catpm update` 只刷新索引缓存不装包，回 `catpm: refreshing package index from 1 source(s)` 和一行 `index cache updated` 摘要；`catpm upgrade` 才重解析、重写锁并安装——源里有新版时（`outdated` 会标 `-> upgradable`）它把新版装上，没有就原样重装一遍、锁不变。锁语义记住一条就够：`install` 认锁不认清单，锁里写什么装什么。

**第八步，更新 catpm 自己。** 敲 `catpm self-update`。刚装完的最新版会回 `already up to date`；真正的升级路径长这样（用旧版二进制实测）：`current version 0.5.0`、`target version  0.5.5`、从 catpm-registry 拉包、`sha256 ok`、`candidate verified: catpm 0.5.5 (for CatBase 0.1.8)`，最后一行 `catpm: updated ... -> 0.5.5`。它绝不直接覆盖活二进制：候选先放在旁边，真跑一次 `--version`、报得出目标版本才算数，最后用一次原子 `mv` 换过去。失败路径（源不可达、索引里的哈希被篡改、包坏但哈希对得上）全部实测过——一律中止并以非零退出，目录里不留半成品，旧版本继续能干活（`logs/selfupdate5.log`）。也支持 `catpm self-update @<版本>` 钉版本；线上源按发版规矩只保留最新版，想降级得自备含旧版本的本地源。老话重提：0.4.0 及更早没有这个子命令，从那些版本升级请用第二节的安装命令重装一遍。

## 四、收尾：这东西对你有什么用

如果你在写 CatBase，它替你省掉的是「手抄依赖源码进项目」这件事：一句 add 从 GitHub 拉全依赖链，纯文本锁保证下次装回来还是同一套，sha256 挡住传输损坏与篡改，装到一半断了重跑就能续上。

如果你想给这门语言生态添砖，发包的门槛被压到了最低：一个目录两个文件就能成包，GitHub 仓库本身就是源，pack、publish、push 三步之后全世界都能 `catpm add` 你的包——索引自动维护，不需要申请账号，也不需要架服务。

如果你是来研究包管理器怎么造的，这里有一个完整而小巧的样本：清单、解析、封装、源四层协议各自独立；apt 式多源清单；钻石依赖与传递闭包的处理；中断恢复的原子写与暂存解包；以及一个会把自己当包发布的自举设计。每一项能力都有实测日志背书，每一项边界也都如实写在那里。

它不是万能工具：只出了一种植入平台的二进制，说明符是子集，语言本身也很年轻。但如果你恰好在这门语言的世界里，它已经是那条「一句命令装齐依赖」的路。

最后一句心里话：这份指南里的每个动作都是真跑过的——装过、装包过、编译运行过、删过、刷过索引、升过级、连三种失败都专门造出来验证过。照着敲，遇到的和文中说的应该是同一个世界；万一不是，文末的出处清单能帮你逐条对账。

## 五、进阶：挂上你自己的包仓库

基础闭环走完了。如果你还想更进一步——不管是想用别人的源，还是想把自己的包仓库挂起来给别人用——都在这一节。

**使用方：添加与切换第三方源。** `catpm sources` 是查看命令：它列出每个源的优先级、类型、服务范围和实测可达性，但添加源不靠它，靠改 `package.where` 文件。这个文件有三处可写，catpm 按顺序找：用 `CATPM_WHERE=<路径>` 指定的那份 → 项目目录里的 `./package.where` → 二进制旁边的 `~/.local/bin/package.where`（装好后默认就在这里，默认源就是 catpm-registry 的 GitHub raw 地址），都没有时才回退老的 `CATPM_REGISTRY=<dir|URL>` 单源写法。实测：项目里放一份 `./package.where`，`catpm sources` 立刻回 `catpm: sources from ./package.where`；改用 `CATPM_WHERE=/tmp/where-alt`，它回 `catpm: sources from /tmp/where-alt`——两处都会盖过默认清单。

源清单一行一个源，`prio=` 定优先级，比如把自己的源排在官方源前面：

```text
/my/registry-dir                                        prio=10
https://raw.githubusercontent.com/<user>/<repo>/main   prio=1
```

添加之后就照常 add／install，解析自动变成多源并集、下载按 prio 从高到低试。实测回显长这样：`resolving dependencies (source: 2 source(s): /tmp/my-reg, https://raw.githubusercontent.com/monikalnbo/catpm-registry/main)`；`catpm add demox` 的下载行来自新源（`prefetch demox@0.1.0 <- /tmp/my-reg/demox/demox-0.1.0.cpkg`），同一项目里 `catpm add timex` 又自动落到 GitHub 源——一个项目混用两个源，互不干扰。某一路源挂了也不致命：`catpm sources` 会标 `UNREACHABLE`、命令打个 warning 继续用其余源；要找的包哪都没有时，回 `package not found in any source: <包名>` 并附 `searched:` 列出它实际查过的源。还可以给某个源加 `pkg=demox` 钉定——它就只参与这几个包的解析（`sources` 的 serves 列会如实显示），跟 apt 的 pin 一个思路。

**提供方：把自己的仓库挂起来。** 一个 registry 就是一个目录：一份 `index.json` 加 `<包名>/<包名>-<版本>.cpkg` 归档，仅此而已。本地目录直接就能当源；要挂到网上，GitHub 仓库天然满足——raw 地址就是源地址（官方的 catpm-registry 本身就是这么跑的）。发布三步：在包目录里 `catpm pack`；`catpm publish <registry 目录>`；git 提交推送。实测回显：`catpm: published demox@0.1.0`，跟着两行 `-> /tmp/my-reg/demox/demox-0.1.0.cpkg` 和 `-> index.json updated (sha256 ...)`——索引是 publish 自动维护的，不用手写。一个实测出来的细节：publish 不会替你建目录，先 `mkdir` 再 publish，漏了会回你一句 `registry directory not found`。两个老坑再提一遍：仓库的 `.gitignore` 不能含 `*.cpkg`（否则归档上不了库、索引却更新了）；raw 传播有一点延迟，推完稍等片刻。都做完之后，别人只需把你的 raw 地址写进他的 `package.where`（就是上面那个两行的例子反过来用），一句 `catpm add <你的包>` 就能装到。

## 附：证据出处清单

- 本文各步回显：`logs/getting-started.log`（[A] 安装／[B] 版本与源／[C] init＋add＋list／[D] 编译运行／[E] outdated／[F] update＋upgrade／[G] remove／[H] 幂等 self-update／[I] 0.5.0→0.5.5 升级路径，对线上 v0.5.5 实测）。
- 传递依赖拒绝删除、install 认锁的锁语义：`logs/run4.log` [2/6][3/6]。
- self-update 钉版本语法与三种失败回退：`logs/selfupdate5.log` [1/5]–[5/5]。
- 中断恢复（被杀重跑即续）：`logs/run11-local.log`（方法与场景详见 [guide.md](guide.md) 进阶篇）。
- 添加／切换第三方源与自建 registry：`logs/own-registry.log`（提供方 pack＋publish、使用方 ./package.where 与 CATPM_WHERE、双源 prio、pkg= 钉定、不可达与 not found 回显，对 v0.5.5 现场实测）；多源原始六场景另见 `logs/where3.log`；GitHub 当源的三步流程见 `scripts/publish-remote.md` 与 [registry.md](registry.md)。
- 安装脚本行为与四 shell 实装：`install.sh`、`install.fish`、`logs/run4.log` [5/6]。
- 权威命令清单与说明符表：[README.md](../README.md) §3；四层协议：[PROTOCOL.md](../PROTOCOL.md)。

## 附：自查

1. 四件事齐全：一（能干什么）→ 二（怎么安装）→ 三（装完每一步怎么做，八步到第一个程序跑起来）→ 四（收尾认知）；另补进阶节五（挂上自己的包仓库，使用方与提供方两视角）。
2. 命令与输出可溯源：正文回显逐字取自 `logs/getting-started.log` 与上述日志；未实测的写法（登录会话持久 PATH、降级到旧版本）均如实注明。
3. 仅保留三条短代码块（单行安装命令、实测验证程序原文、双源源清单示例），其余为行内代码；正文不罗列统计数字；中文标点全角（命令与代码除外）。
