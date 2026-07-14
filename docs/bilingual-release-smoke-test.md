# Shuo 中英混合发布验收

用途：发布前用真实说话方式检查 Shuo 的核心生态位，而不是只验证纯中文或纯英文转写。

## 测试设置

分别完成两轮：

1. Local：选择推荐的多语言 whisper.cpp 模型；在转写语言中同时勾选
   “中文”和“English”，中文形式选择“简体”。
2. OpenAI-compatible：模型选择 Automatic；同样同时勾选“中文”和
   “English”，中文形式选择“简体”。

每轮先清空下面这些测试专用常用词，跑一次基线；然后加入并重跑：

```text
Shuo
Shuotian
SwiftUI
GitHub Release
gpt-4o-transcribe
MetricsStore
Postgres
Kubernetes
```

记录实际输出，不要为了通过测试而刻意放慢到逐字朗读。每句话使用日常语速说两次。

## 语料

| # | 朗读内容 | 主要检查点 | Local | OpenAI-compatible |
|---|---|---|---|---|
| 1 | 我们把这个 API deploy 到 staging，然后开一个 PR。 | API、deploy、staging、PR |  |  |
| 2 | 这个 endpoint 用 gpt-4o-transcribe，fallback 到 local Whisper。 | 模型名、英文动词 |  |  |
| 3 | 跟 Shuotian 确认一下 SwiftUI onboarding，今天发 GitHub Release。 | 人名、框架、发布术语 |  |  |
| 4 | 先不要改 MetricsStore，我们只修这个 crash。 | Swift 类型名、crash |  |  |
| 5 | 把 Postgres migration 放进下一个 release。 | 数据库名、migration |  |  |
| 6 | Kubernetes 的 namespace 还是用 production。 | 长技术词、namespace |  |  |
| 7 | 这个 bug 只在 macOS fourteen 上出现。 | bug、macOS、英文数字 |  |  |
| 8 | 帮我 review 一下这个 diff，重点看 cancellation。 | review、diff、抽象术语 |  |  |
| 9 | 今天先 ship，analytics 和 billing 下周再做。 | 连续英文术语 |  |  |
| 10 | 用户说登录以后 UI 会 freeze 两秒。 | UI、freeze、数字 |  |  |
| 11 | Please update the onboarding，但是不要动下载模型的流程。 | 英文开头切中文 |  |  |
| 12 | The API key 存在 Keychain，不要写进 UserDefaults。 | 类型名和安全术语 |  |  |
| 13 | 这个 feature 暂时 behind a flag，默认关闭。 | 短语切换 |  |  |
| 14 | 明天和 Alice sync 一下 release notes。 | 人名、日常工作表达 |  |  |
| 15 | 修完以后跑 make verify，然后把结果贴到 GitHub。 | 命令、产品名 |  |  |

## 通过标准

- 15 句话都没有丢失完整分句、重复整段或插入无关内容。
- 中英文切换后不翻译原话，不把整句强制变成单一语言。
- 加入常用词后，测试词的拼写不能比基线更差；核心词最多允许两处错误。
- 自动粘贴、剪贴板恢复、取消和失败回退没有出现回归。
- Local 和 OpenAI-compatible 的差异被记录，而不是为了得到相同结果而隐藏。

如果失败，保留对应 History、原始音频、provider、model 和实际输出，再决定是词表、模型选择、提示词还是后处理问题。
