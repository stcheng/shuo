# Shuo

**Speak. Edit. Keep writing.**

Shuo is a local-first voice input app for macOS. Hold Right Command or Right
Option, speak, and release. Your words go into the app you are already using.
If one word is wrong, edit the latest result in the Floating Bar and return it
without having to dictate the whole sentence again.

[Website](https://stcheng.github.io/shuo/) · [Download](https://github.com/stcheng/shuo/releases/latest) · [Privacy](https://stcheng.github.io/shuo/privacy.html) · [Release notes](https://stcheng.github.io/shuo/release-notes.html)

## What it is for

- **Real working language.** English, Simplified Chinese, Traditional Chinese,
  Japanese, technical terms, names, and project jargon can live in one input.
- **Editable voice input.** The Floating Bar keeps the latest result close at
  hand. Shuo rewrites the changed suffix only when it can verify the original
  target safely; otherwise it copies the complete correction.
- **Local by default.** Download a local model and use Shuo without an account.
  Cloud transcription and text features are optional.
- **Data that stays useful.** When a recording is available, retained History
  links it with the initial output and final revision on the Mac until you
  delete the item. Explicit corrections can later become opt-in, locally
  controlled learning data.

## Data boundary

With local transcription selected and cloud AI turned off, audio, text,
history, recordings, vocabulary, and correction data stay on the Mac. Shuo
does not require an account and the app sends no telemetry or advertising data.

When you enable a cloud feature, Shuo sends only the current task data required
by that feature—such as the current audio, selected settings, enabled context,
or text instruction—to the endpoint you configured. Project source files and
paths are not uploaded.

## Technical snapshot

- macOS 14 or later; Apple silicon and Intel
- Push-to-talk with Right Command or Right Option
- Local speech models, optional cloud transcription, and optional cloud text
  features
- Local History, replayable recordings, vocabulary, correction records, and
  metrics
- GPL-3.0 source; the Shuo name and logo are covered by the
  [trademark policy](TRADEMARK.md)

## Build from source

The supported source-build path is the isolated **Shuo Community** target:

```sh
git clone https://github.com/stcheng/shuo.git
cd shuo
make build-community
make test-community
```

See [BUILDING.md](BUILDING.md) for requirements and [ARCHITECTURE.md](ARCHITECTURE.md)
for the seven-stage pipeline.

---

# Shuo（简体中文）

**按住。说话。松开。听错了，即刻改好。**

Shuo 是一款本地优先的 macOS 语音输入工具。按住右 Command 或右 Option，
说话，松开；文字会输入到你正在使用的 App。听错一个词时，直接在悬浮栏修改，
不必重说整句话。

[官网](https://stcheng.github.io/shuo/) · [下载](https://github.com/stcheng/shuo/releases/latest) · [隐私](https://stcheng.github.io/shuo/privacy.html) · [更新](https://stcheng.github.io/shuo/release-notes.html)

## 它解决什么

- **真实的工作语言。** 英文、简体中文、繁体中文、日文、技术术语、人名和项目
  黑话，可以在同一句里自然输入。
- **可修改的语音输入。** 悬浮栏保留最新结果；只有能够安全确认原目标时，Shuo
  才会重写变化的后缀，否则只复制完整修正，避免误删。
- **本地为默认。** 下载本地模型后无需账号；云端转写和云端文本功能均为可选。
- **留下可用的数据。** 录音可用时，保留的历史会在本机关联录音、初始输出和
  最终修订，直到你删除它。明确发生的修改可成为未来由你主动开启的本地学习材料。

## 数据边界

选择本地转写并关闭云端 AI 时，音频、文字、历史、录音、词汇和修改数据都只留在
这台 Mac。Shuo 无需账号，App 不发送遥测或广告数据。

开启云端功能时，Shuo 只会向你配置的服务端点发送该功能完成当前任务所需的数据，
例如当前音频、所选设置、已启用的上下文或文本指令。项目源文件和路径不会上传。

## 技术概览

- macOS 14 或更高版本；支持 Apple silicon 与 Intel
- 右 Command 或右 Option 按住说话
- 本地语音模型；可选云端转写与云端文本功能
- 本地历史、录音回放、词汇、修改记录和统计
- 源码采用 GPL-3.0；Shuo 名称和图标受
  [商标政策](TRADEMARK.md)保护

## 从源码构建

推荐使用隔离的 **Shuo Community** 目标：

```sh
git clone https://github.com/stcheng/shuo.git
cd shuo
make build-community
make test-community
```

构建要求见 [BUILDING.md](BUILDING.md)，七阶段架构见
[ARCHITECTURE.md](ARCHITECTURE.md)。
