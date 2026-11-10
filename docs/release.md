# catpm 发版手册（checklist）

本文是每次发 catpm 新版的操作手册。规则本体见 [PROTOCOL.md §4.6–§4.6b](../PROTOCOL.md)；这里是可逐项打勾的执行清单。

## 长期规则速查

1. **版本号 +0.0.1**：`0.5.4 → 0.5.5 → 0.5.6 → …`，无论改动大小，不跳 minor。
2. **commit message 极短或空白**：`git commit --allow-empty-message` 或至多一个极短词（如 `0.5.5`）；一切说明写文档（README / PROTOCOL / docs/），不写进 commit。
3. **registry 只留最新版**：每个包目录只保留最新版本的 `.cpkg`；老版本产物删除，但**删前**确认它们已在 git 历史里（老版本随时可从历史找回，必要时打 tag）。
4. **发布产物 = 完整整包**：tag/release 附件、diff 文件、self-update 下载的都是对应版本的完整内容；全量替换，不做增量。

## 发版 checklist

按序执行，任何一步不过不进下一步：

```
[ ] 1. 源码定稿          catpm/src2/ 全部改动完成，changelog 头注释更新
[ ] 2. 全量单测          catcc test_ver.cat -> 运行 -> "ALL VER TESTS PASSED"（62 断言）
[ ] 3. 全新编译          catcc catpm.cat -o catpm/catpm5X；记录体积；--version 报新版号
[ ] 4. 生成 diff         上一版快照（从已发布 .cpkg 解出或 git 历史）vs 新版源码
                          diff -ruN <旧> <新> > diffs/v<旧>..v<新>.diff
                          逐块核对：每个 hunk 都能对上本轮有意改动，无未预期漂移
[ ] 5. 端到端实测        本轮特性的 e2e 脚本全绿（scripts/e2e_vN.sh，日志落 logs/）
[ ] 6. 打包              干净目录复制源码 -> catpm pack -> 记录 sha256 与字节数
[ ] 7. registry 清理     删除各包老版本 .cpkg（本包 + 其他包只留最新版），
                          index.json 同步收敛；老版本确认在 git 历史（需要时打 tag）
[ ] 8. publish           catpm publish <registry 检出目录>
[ ] 9. 一次推送          registry 仓库 git add -A && git commit（极短 message）&& git push
                          ——只推一次（raw CDN 会短暂出现新旧不一致窗口，推两次会放大）
[ ] 10. 主仓库推送       catpm 仓库：源码/二进制/diff/日志/文档全部 add，
                          commit（极短 message 或空白）+ push
[ ] 11. raw 直链验证     curl -o /dev/null -w '%{http_code}' <raw>/index.json 与新 .cpkg 都要 200
                          ——注意 CDN 传播：404 时等 1-2 分钟重试，不要急着重复推送
[ ] 12. self-update 实测 用上一版二进制（catpm5(X-1)）跑 self-update：必须升到新版本号；
                          失败场景（源断/sha 篡改）不在每次发版重测，版本升级链路必须每次过
[ ] 13. curl|sh 实测     全新目录 curl -fsSL .../install.sh | sh 装出的是新版
[ ] 14. 文档收尾         README 版本表/体积/日志清单更新；报告落 reports/（如本轮有）
```

## registry 只留最新版：操作细节

**删什么**：`<name>/<name>-<旧ver>.cpkg` 全部删除（每个包目录只留最高版本一个文件）；`index.json` 里该包只留最新版本条目。

**删之前必须**：

```bash
cd catpm-registry-checkout
git status --short          # 工作树干净
git log --oneline -1        # 老版本 .cpkg 已在此 commit 及之前的树里
# 可选但推荐：给「最后一个含全部老版本的树」打 tag，便于用户找回
git tag -a v0.5.4-full-history -m "" && git push origin v0.5.4-full-history
```

**删的影响（如实）**：

- `catpm add <pkg>@<旧版>`、`catpm self-update @<旧版>` 对被删版本**报错 exit 1**（解析器在索引中找不到版本，与「从未存在」同行为）。
- 已装项目**零影响**：`deps/` 与 `.catpm-cache/` 里是完整整包，lock 照常工作。
- **找回老版本**：`git show <tag或commit>:<name>/<name>-<ver>.cpkg > x.cpkg`，然后二选一：(a) 放进本地目录源（package.where 加一行路径）即可安装任意老版本；(b) 放进项目 `.catpm-cache/<name>/` 后正常 `catpm add <pkg>@<旧版>`（sha256 仍强制校验，索引里没条目则不可用——须本地源）。
- 删除后 **self-update 全量替换链路必须复测**（checklist 第 12 步）：确认「源里只剩最新版」不妨碍从上一版升级。

## commit 规范落地示例

```bash
# 推荐：空白 message
git commit --allow-empty-message --no-edit -a
# 或一个极短词
git commit -m "0.5.5"
```

说明去哪了？——README（用户可见的行为变化）、PROTOCOL.md（协议层规则）、docs/（专题手册）、logs/（实测证据）、diffs/（版本间审计）。

## 版本历史与找回

| 版本 | 发布物在 | 老版本找回方式 |
|---|---|---|
| 最新（如 0.5.5） | registry 根目录 `<name>/<name>-<ver>.cpkg` + index.json | — |
| 历史（0.4.0–0.5.4） | catpm-registry git 历史（各发布 commit 的树里） | `git show` / `git checkout <commit> -- <path>`；tag `v0.5.4-full-history` 是最后一个全量树 |

主仓库同理：每个版本的源码、二进制、diff、日志都在对应 commit 里，`git log -- catpm/catpm55` 可定位任意历史版本。
