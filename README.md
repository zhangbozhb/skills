# Skill Map

本仓库维护一组可独立触发、也可显式组合的 Skill。组织模型由三部分组成：

- **领域树**：帮助人理解和查找能力。
- **依赖图**：描述 Skill 之间的复用与转交关系。
- **平铺注册表**：每个 Skill 仍以全局唯一名称独立触发，不从目录继承行为。

机器可读清单见 [`skills/catalog.yaml`](skills/catalog.yaml)。

## 领域地图

```text
skills
├── reasoning
│   ├── problem-solution-design
│   └── definition-audit
├── research
│   ├── tea-time-research
│   └── deep-research
├── orchestration
│   └── goal-driven-workflow
├── communication
│   └── communication-rewriter
├── agent-engineering
│   └── agent-harness-review
└── skill-engineering
    └── skill-optimizer
```

这是逻辑分类，不代表当前物理目录或运行时存在父子、继承关系。

## Skill 清单

| Skill | 领域 | 角色 | 使用时机 |
| --- | --- | --- | --- |
| [`problem-solution-design`](skills/problem-solution-design/SKILL.md) | 推理与设计 | 专项能力 | 模糊问题、从零设计、方案取舍和必要性评估 |
| [`definition-audit`](skills/definition-audit/SKILL.md) | 推理与设计 | 专项能力 | 审核已成文的分类、字段、schema、契约或判据 |
| [`tea-time-research`](skills/tea-time-research/SKILL.md) | 研究与学习 | 专项能力 | 按使用意图、topic 形态、目标读者和证据条件快速研究 |
| [`deep-research`](skills/deep-research/SKILL.md) | 研究与学习 | 专项能力 | 对复杂问题执行多轮取证、反证、综合与主张级审计 |
| [`goal-driven-workflow`](skills/goal-driven-workflow/SKILL.md) | 工作编排 | 编排器 | 跨阶段、跨会话、多轮实验或分支依赖任务 |
| [`communication-rewriter`](skills/communication-rewriter/SKILL.md) | 沟通表达 | 专项能力 | 根据事实要点起草或改写短消息、口头话术及其后续追改 |
| [`agent-harness-review`](skills/agent-harness-review/SKILL.md) | Agent 工程 | 专项能力 | 建设评估或架构评审，识别 agent/harness 的可靠性、安全和成熟度缺口 |
| [`skill-optimizer`](skills/skill-optimizer/SKILL.md) | Skill 工程 | 专项能力 | 审查和优化已有 Skill 的触发、执行与结构 |

## 组合关系

```text
goal-driven-workflow
├── uses problem-solution-design
├── uses definition-audit
└── uses skill-optimizer

problem-solution-design ── routes_to ──> definition-audit
definition-audit ──────── routes_to ──> problem-solution-design
definition-audit ──────── routes_to ──> skill-optimizer
skill-optimizer ───────── routes_to ──> problem-solution-design
skill-optimizer ───────── routes_to ──> definition-audit
agent-harness-review ──── routes_to ──> problem-solution-design
tea-time-research <────── routes_to ──> deep-research
```

- **`uses`**：当前 Skill 在自身流程内调用另一 Skill，并继续维护主任务。
- **`routes_to`**：当前请求超出职责边界，停止当前流程并转交给另一 Skill。
- **`references/`**：只存放所属 Skill 的内部子能力和资料，不作为独立 Skill 触发。

`uses` 应保持无环。`routes_to` 可以双向存在，但必须由互斥的职责边界决定，不能形成自动来回调用。

## 维护规则

1. 新增 Skill，或调整名称、路径、领域、角色及组合关系时，同步更新 `skills/catalog.yaml` 和本地图；仅修改内部规则且条目仍准确时不制造清单改动。
2. `name` 保持全局唯一；领域目录不参与触发，也不构成名称前缀。
3. 可复用能力通过明确的 Skill 调用组合，不通过复制正文或跨目录深层引用复用。
4. 编排器负责主流程和状态，专项 Skill 负责单一领域判断或动作。
5. 高副作用操作的确认、安全和隔离门槛不能被编排器绕过。
6. 当前源码和安装目录保持平铺；确认运行时支持递归发现并具备迁移收益后，再考虑调整物理目录。

## 安装

运行 [安装脚本](scripts/install.sh) 时，脚本从当前目录发现 Skill：若存在 `./skills/` 则优先使用该目录；若当前目录本身包含 `SKILL.md`，则安装该单个 Skill；否则扫描当前目录的直接子目录。默认安装到 `~/.claude/skills`，可使用 `--agent` 或 `--target` 指定其它目标：

```sh
./scripts/install.sh --help
./scripts/install.sh --list
./scripts/install.sh --agent trae-cn
```

## 维护验证

在仓库根目录使用 Ruby 2.6+ 及其标准库执行，无需额外安装依赖：

```sh
ruby --disable-gems scripts/check_skills.rb
```

- [结构检查](scripts/check_skills.rb)：校验本库 frontmatter、YAML 重复键、清单、`uses` 无环性、行内 Markdown 本地链接与标题锚点，以及各 skill 内现有专项场景的字段、唯一 ID 与输入完整性。不联网，不执行 skill 业务流程。
- [快速研究专项场景](skills/tea-time-research/tests/cases.yaml)：覆盖研究预算、来源限制、后续追问和风险准入。

结构检查通过只证明文件和声明一致。场景需逐条人工或模型走查；只有在真实路由器与执行环境中实测，才能声称触发或执行效果已经验证。安装、全局更新和真实业务调用不属于上述检查。
