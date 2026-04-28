# Quota Supervisor README

这份文档是给“人”和“Agent”一起看的操作手册。

目标只有一个：

- 让 `codexAppBar + codexbarctl + quota-watcher.py` 这一套东西能长期稳定跑
- 让你或者 Azine 在不需要读很多源码的情况下，也能正确地下任务、观察状态、排查问题

---

## 1. 这套系统是干什么的

这是一套“无人值守额度守卫 Supervisor”。

它负责：

- 监控当前活跃 Codex 账号的额度
- 当额度接近耗尽时，先等待当前任务结束
- 在 Codex 空闲后安全切换到另一个健康账号
- 切号完成后，从任务账本里继续恢复未完成任务

它不负责：

- 直接恢复一个被中断的内存上下文
- 猜测你没写进任务账本的临时想法
- 替你决定一个模糊不清的任务到底该做什么

一句话理解：

**它恢复的是“任务列表”，不是“上一个 Agent 的脑内现场”。**

---

## 2. 组件与文件位置

核心组件：

- 菜单栏 App：`/Users/zhouguichao/Desktop/codexAppBar-safe-switch.app`
- 控制命令：`/Users/zhouguichao/.local/bin/codexbarctl`
- Supervisor 脚本：`/Users/zhouguichao/Desktop/quota-watcher.py`

状态与数据文件：

- Supervisor 状态：`~/.codex/quota-supervisor/state.json`
- 任务账本：`~/.codex/quota-supervisor/tasks.json`
- Agent 输出：`~/.codex/quota-supervisor/task-outputs/`
- CodexBar 状态桥：`~/.codex/codexbar/status.json`
- CodexBar 命令桥：`~/.codex/codexbar/commands/`
- CodexBar 结果桥：`~/.codex/codexbar/results/`

---

## 3. 系统怎么工作

状态机会在这几个状态之间切换：

- `monitoring`
  正常监控中
- `waiting`
  已经发现额度快不够，但当前 Codex 还忙，先等任务结束
- `switching`
  正在调用 `codexbarctl switch-auto ... --wait`
- `resuming`
  已经切号，开始恢复待执行任务

触发切换的条件：

- `usageStatus == "exceeded"`
- `isSuspended == true`
- `tokenExpired == true`
- `primaryUsedPercent >= threshold`
- `secondaryUsedPercent >= weekly_threshold`

默认阈值：

- `5h` 阈值：`95%`
- `7d` 阈值：`97%`

---

## 4. 最常用命令

### 4.1 查看状态

```bash
codexbarctl status --json
python3 ~/Desktop/quota-watcher.py state
```

### 4.2 查看账号池

```bash
codexbarctl accounts --json
```

### 4.3 前台运行 Supervisor

```bash
python3 ~/Desktop/quota-watcher.py
```

### 4.4 只跑一轮，便于验证

```bash
python3 ~/Desktop/quota-watcher.py --once --verbose
```

### 4.5 Dry-run 观察，不真的切号

```bash
python3 ~/Desktop/quota-watcher.py --dry-run --verbose
```

### 4.6 后台运行

```bash
nohup python3 ~/Desktop/quota-watcher.py > ~/Desktop/quota-watcher.log 2>&1 &
```

### 4.7 预热账号池

如果你希望早上先把所有健康账号的 `5h` 窗口启动起来，可以跑：

```bash
~/Desktop/codexbar/Tools/codexbar-warmup.sh
```

它会逐个账号执行：

- `codexbarctl switch-auto <identityKey> --wait`
- `codex exec --ephemeral "只回复：你好"`
- 最后切回原本的活跃账号

先看计划、不真的消耗额度：

```bash
~/Desktop/codexbar/Tools/codexbar-warmup.sh --dry-run
```

只预热前 3 个账号：

```bash
~/Desktop/codexbar/Tools/codexbar-warmup.sh --limit 3
```

预热日志会写到：

```text
~/.codex/codexbar/warmups/
```

注意：单纯刷新 usage 或切换账号通常不会启动 `5h` 计算窗口，必须有一次非常小的 Codex 请求才算真正预热。

---

## 5. 任务账本是什么

任务账本就是 `tasks.json`。

每一条任务都应该被理解成：

- 一个明确的目标
- 一个明确的工作目录
- 一个明确的恢复方式
- 一个明确的完成标准

支持两种任务：

- `agent`
  让 `codex exec` 去执行一个自然语言任务
- `shell`
  执行一个确定性的 shell 命令，更适合做验证、同步、清理、导出
  也支持加 `--interval-seconds` 变成周期任务，适合做每分钟轮询或状态采样

常见状态：

- `pending`
  待执行
- `running`
  正在执行
- `done`
  已完成
- `failed`
  执行失败，等待人工处理或再次恢复

---

## 6. 怎么加任务

### 6.1 加一个 Agent 任务

```bash
python3 ~/Desktop/quota-watcher.py task add-agent \
  --title "继续处理登录页重构" \
  --cwd /Users/zhouguichao/Desktop/你的项目目录 \
  --prompt "继续处理登录页重构。先检查当前仓库状态，再完成未完成的改动，并给出简短结果说明。"
```

### 6.2 加一个 Shell 任务

```bash
python3 ~/Desktop/quota-watcher.py task add-shell \
  --title "导出今日日志" \
  --cwd /Users/zhouguichao/Desktop \
  --command "tar -czf ~/Desktop/today-logs.tar.gz ~/.codex/log"
```

如果你想加一个周期 shell 任务，例如每分钟看一次 A40 实验状态：

```bash
python3 ~/Desktop/quota-watcher.py task add-shell \
  --title "A40 experiment monitor" \
  --cwd /Users/zhouguichao \
  --command "/Users/zhouguichao/.comb222_a40_monitor/check_a40_experiment.sh" \
  --timeout 120 \
  --interval-seconds 60
```

### 6.3 查看任务

```bash
python3 ~/Desktop/quota-watcher.py task list
```

### 6.4 立即恢复待执行任务

```bash
python3 ~/Desktop/quota-watcher.py task run-pending --verbose
```

### 6.5 手动改任务状态

```bash
python3 ~/Desktop/quota-watcher.py task mark <task_id> pending
python3 ~/Desktop/quota-watcher.py task mark <task_id> failed --error "原因说明"
```

---

## 7. 该怎么向 Azine 说话

如果你希望 Azine 帮你加任务，不要只说：

- “帮我搞一下这个”
- “继续做那个项目”
- “你自己看着办”

这种请求太模糊，恢复时也没法稳定重放。

更好的说法应该包含 5 个信息：

- 任务标题
- 工作目录
- 目标
- 完成标准
- 是否允许切号后自动继续

推荐模板：

```text
帮我给 quota supervisor 加一个任务：

标题：继续处理支付页 bug
目录：/Users/zhouguichao/Desktop/my-project
目标：检查支付页提交失败的问题，定位原因并修复
完成标准：代码改好，必要时跑测试，并告诉我改了什么
恢复策略：如果中途切号，允许自动继续
```

如果你想让 Azine 只读不改，可以这样说：

```text
帮我加一个只读分析任务：

标题：分析 iOS 登录问题
目录：/Users/zhouguichao/Desktop/my-app
目标：只分析，不改代码，告诉我根因和建议方案
完成标准：输出结论，不做文件修改
```

如果你想让 Azine 做执行型任务，可以这样说：

```text
帮我加一个执行任务：

标题：修复构建失败
目录：/Users/zhouguichao/Desktop/my-app
目标：修复当前构建失败问题
完成标准：至少让项目重新 build 通过，告诉我验证结果
恢复策略：允许自动继续
```

---

## 8. Azine 最好怎么翻译你的需求

如果 Azine 需要把自然语言需求转成任务，建议按这个结构整理：

- `title`
  简短、能识别的任务名
- `cwd`
  唯一正确的工作目录
- `prompt`
  任务本身的描述，不要把调度和路径塞进 prompt 里
- `sandbox`
  `read-only` / `workspace-write` / `danger-full-access`
- `timeout`
  任务最长运行时间
- `resumeOnSwitch`
  切号后是否继续恢复

建议规则：

- 只分析、不改文件：用 `read-only`
- 项目内改代码：用 `workspace-write`
- 需要更高权限或跨目录系统操作：用 `danger-full-access`

---

## 9. 好任务和坏任务的区别

好的任务：

- “继续完善订单页。先看当前改动，再补齐未完成的接口联调，完成后告诉我结果。”
- “分析这个仓库的登录失败原因，只读，不改代码，给出 3 条最可能原因。”
- “修复当前 iOS 构建失败，并验证 `xcodebuild` 是否通过。”

不好的任务：

- “继续弄”
- “把那个项目搞完”
- “你看一下哪里有问题”
- “顺便都优化一下”

原因很简单：

- 任务越模糊，恢复时越难稳定复现
- 任务越明确，切号之后越容易继续跑

---

## 10. 常见工作流

### 10.1 你自己先加任务，再让 Supervisor 守着

1. 用 `task add-agent` 或 `task add-shell` 把任务放进账本
2. 启动 `quota-watcher.py`
3. 正常使用 Codex
4. 当额度紧张时，Supervisor 会等待空闲后自动切号
5. 切号完成后，它会恢复账本中的待执行任务

### 10.2 让 Azine 代你加任务

1. 你给 Azine 一个明确的任务描述
2. Azine 负责把它转成 `task add-agent`
3. 任务进入账本
4. Supervisor 后续负责守额度和恢复任务

### 10.3 发现失败任务

1. 跑 `python3 ~/Desktop/quota-watcher.py task list`
2. 找到 `failed` 任务
3. 看 `state.json` 的 `lastError`
4. 修正任务描述或环境
5. 再把任务改回 `pending`

---

## 11. 数据文件一般不要手改

虽然这些都是本地 JSON，但正常情况下不要直接手改：

- `~/.codex/quota-supervisor/tasks.json`
- `~/.codex/quota-supervisor/state.json`

建议优先用命令：

- `task add-agent`
- `task add-shell`
- `task list`
- `task mark`
- `task run-pending`
- `state`

直接手改 JSON 的风险：

- 写坏格式
- 把任务状态改乱
- 恢复时出现重复执行

---

## 12. 当前已知边界

这套系统现在已经能做：

- 自动监控额度
- 等待 Codex 空闲
- 安全切号
- 记录状态
- 恢复任务账本中的待执行任务
- 执行账本中的周期 shell 任务（例如每分钟轮询远端实验状态）

但现在还没有做：

- 真正的任务优先级队列
- 多任务并发调度
- 更复杂的智能选账号策略
- LaunchAgent 常驻安装器
- 一个专门给 Azine 调用的更高层 API

---

## 13. 推荐你平时怎么用

最稳的方式是：

1. `codexAppBar-safe-switch.app` 常驻
2. `quota-watcher.py` 后台运行
3. 重要任务都先登记进 `tasks.json`
4. 给 Azine 下任务时，明确写出标题、目录、目标、完成标准

如果只记一句：

**把任务说具体，把目录说准确，把完成标准说清楚。**

这样 Supervisor 才能在切号后帮你真正续上工作。
