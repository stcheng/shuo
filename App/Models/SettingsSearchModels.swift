import Foundation

enum SettingsPipelineStage: String, CaseIterable, Identifiable {
    case voiceInput
    case audioProcessing
    case contextPreparation
    case aiInference
    case postProcessing
    case humanCorrection
    case finalResult

    var id: String { rawValue }
}

struct SettingsPipelinePlacement: Equatable {
    let stage: SettingsPipelineStage
    let appearsInBasicSettings: Bool
}

enum SettingsSearchTarget: String, CaseIterable, Hashable {
    case inputPushToTalk
    case inputShortcut
    case inputRecordingCue
    case inputRecordingCueStyle
    case microphonePermission
    case accessibilityPermission
    case transcriptionLanguage
    case transcriptionProvider
    case audioInputDevice
    case whisperMode
    case transcriptionModel
    case openAIAPIKey
    case openAIConnectionDetails
    case openAIBaseURL
    case openAIOrganizationID
    case openAIProjectID
    case elevenLabsAPIKey
    case alibabaAPIKey
    case geminiAPIKey
    case localModelManagement
    case localManualSetup
    case advancedAudio
    case localWhisperPerformance
    case ignoreSilentRecordings
    case speechThreshold
    case minimumSpeech

    case featureCorrectionRules
    case featureChineseConversion
    case featureEmojiOutput
    case featureTextCleanup
    case featurePromptContext
    case featureAdaptiveRecognition
    case featureTranscriptRetouch
    case featureVoiceEdit
    case deletePreviousCommand
    case featureFloatingWindow

    case manualTerms
    case correctionData
    case projectVocabulary
    case linkProject

    case customCorrections
    case chineseTextConversion
    case emojiOutput
    case smartEmojiMatching
    case punctuationHandling
    case collapseRepeatedSpaces
    case trimWhitespace
    case lowercaseEnglish
    case insertChineseEnglishSpace
    case transcriptBoundary

    case openAITextModel
    case voiceEditCommands
    case voiceEditMode
    case aiEmojiResolver
    case transcriptRetouch
    case promptContexts

    case appLanguage
    case launchAtLogin
    case updates
    case exportSettings
    case architectureOverview

    case aboutInformation
    case reportFeedback
    case privacy
    case releaseNotes
    case uninstallAndData
    case localData

    var pipelinePlacement: SettingsPipelinePlacement? {
        switch self {
        case .inputPushToTalk, .inputShortcut, .inputRecordingCue,
             .inputRecordingCueStyle, .audioInputDevice:
            return SettingsPipelinePlacement(stage: .voiceInput, appearsInBasicSettings: true)

        case .whisperMode:
            return SettingsPipelinePlacement(stage: .audioProcessing, appearsInBasicSettings: true)
        case .advancedAudio, .ignoreSilentRecordings, .speechThreshold, .minimumSpeech:
            return SettingsPipelinePlacement(stage: .audioProcessing, appearsInBasicSettings: false)

        case .featurePromptContext, .manualTerms, .projectVocabulary,
             .linkProject, .promptContexts:
            return SettingsPipelinePlacement(stage: .contextPreparation, appearsInBasicSettings: false)

        case .transcriptionLanguage, .transcriptionProvider, .transcriptionModel,
             .openAIAPIKey, .elevenLabsAPIKey, .alibabaAPIKey, .geminiAPIKey,
             .localModelManagement:
            return SettingsPipelinePlacement(stage: .aiInference, appearsInBasicSettings: true)
        case .openAIConnectionDetails, .openAIBaseURL, .openAIOrganizationID,
             .openAIProjectID, .localManualSetup, .localWhisperPerformance,
             .openAITextModel:
            return SettingsPipelinePlacement(stage: .aiInference, appearsInBasicSettings: false)

        case .featureCorrectionRules, .featureChineseConversion, .featureEmojiOutput,
             .featureTextCleanup, .featureTranscriptRetouch, .customCorrections,
             .chineseTextConversion, .emojiOutput,
             .smartEmojiMatching, .punctuationHandling, .collapseRepeatedSpaces,
             .trimWhitespace, .lowercaseEnglish, .insertChineseEnglishSpace,
             .transcriptBoundary, .aiEmojiResolver, .transcriptRetouch:
            return SettingsPipelinePlacement(stage: .postProcessing, appearsInBasicSettings: false)

        case .featureFloatingWindow:
            return SettingsPipelinePlacement(stage: .humanCorrection, appearsInBasicSettings: true)
        case .featureVoiceEdit, .deletePreviousCommand, .voiceEditCommands,
             .voiceEditMode, .featureAdaptiveRecognition, .correctionData:
            return SettingsPipelinePlacement(stage: .humanCorrection, appearsInBasicSettings: false)

        case .microphonePermission, .accessibilityPermission,
             .appLanguage, .launchAtLogin, .updates, .exportSettings,
             .architectureOverview, .aboutInformation, .reportFeedback,
             .privacy, .releaseNotes, .uninstallAndData, .localData:
            return nil
        }
    }

}

struct SettingsNavigationRequest: Identifiable, Equatable {
    let id: UUID
    let section: AppPanelSection
    let target: SettingsSearchTarget

    init(
        id: UUID = UUID(),
        section: AppPanelSection,
        target: SettingsSearchTarget
    ) {
        self.id = id
        self.section = section
        self.target = target
    }
}

struct SettingsSearchItem: Identifiable, Equatable {
    let title: String
    let pageTitle: String
    let keywords: [String]
    let section: AppPanelSection
    let target: SettingsSearchTarget

    var id: String { "\(target.rawValue)|\(title)" }
}

struct SettingsFeatureVisibility: Equatable {
    let isTranscriptRetouchEnabled: Bool
    let isAIEmojiResolverEnabled: Bool
    let isVoiceEditEnabled: Bool
    let isVoiceModifyEnabled: Bool
    let voiceEditCommandMode: VoiceEditCommandMode
    private let cloudTextProvider: TranscriptionProvider

    init(
        pluginConfiguration: PluginConfiguration,
        provider: TranscriptionProvider = .openAI,
        transcriptRetouchEnabled: Bool = false,
        emojiPostProcessingEnabled: Bool = false,
        aiEmojiResolverEnabled: Bool = false,
        voiceEditCommandsEnabled: Bool = false,
        voiceEditCommandMode: VoiceEditCommandMode = .localOnly,
        openAITextModelSelectionMode: OpenAITextModelSelectionMode = .automatic
    ) {
        cloudTextProvider = provider
        let allowsCloudTextAI = provider != .local
            && openAITextModelSelectionMode != .disabled
        isTranscriptRetouchEnabled = allowsCloudTextAI
            && pluginConfiguration.isEnabled(.outputLLMRetouch)
            && transcriptRetouchEnabled
        isAIEmojiResolverEnabled = allowsCloudTextAI
            && pluginConfiguration.isEnabled(.outputEmoji)
            && emojiPostProcessingEnabled
            && aiEmojiResolverEnabled
        isVoiceEditEnabled = (
            pluginConfiguration.isEnabled(.commandModifyPrevious)
                || pluginConfiguration.isEnabled(.commandDeletePrevious)
        ) && voiceEditCommandsEnabled
        isVoiceModifyEnabled = pluginConfiguration.isEnabled(.commandModifyPrevious)
            && voiceEditCommandsEnabled
        self.voiceEditCommandMode = allowsCloudTextAI ? voiceEditCommandMode : .localOnly
    }

    var usesOpenAITextFeatures: Bool {
        cloudTextProvider != .gemini
            && (isTranscriptRetouchEnabled
            || isAIEmojiResolverEnabled
            || (isVoiceModifyEnabled && voiceEditCommandMode != .localOnly))
    }
}

struct SettingsSearchContext {
    let provider: TranscriptionProvider
    let pluginConfiguration: PluginConfiguration
    let supportsDirectUpdates: Bool
    let showsUpdateSettings: Bool
    let recordingStartSoundEnabled: Bool
    let projectVocabularyEnabled: Bool
    let selectedTranscriptionLanguages: Set<TranscriptionLanguage>
    let useCustomCorrections: Bool
    let emojiPostProcessingEnabled: Bool
    let featureVisibility: SettingsFeatureVisibility
    let openAITextModelSelectionMode: OpenAITextModelSelectionMode

    init(
        provider: TranscriptionProvider,
        pluginConfiguration: PluginConfiguration,
        supportsDirectUpdates: Bool = true,
        showsUpdateSettings: Bool = true,
        recordingStartSoundEnabled: Bool = true,
        projectVocabularyEnabled: Bool = false,
        selectedTranscriptionLanguages: Set<TranscriptionLanguage> = Set(TranscriptionLanguage.allCases),
        useCustomCorrections: Bool = false,
        transcriptRetouchEnabled: Bool = false,
        emojiPostProcessingEnabled: Bool = false,
        aiEmojiResolverEnabled: Bool = false,
        voiceEditCommandsEnabled: Bool = false,
        voiceEditCommandMode: VoiceEditCommandMode = .localOnly,
        openAITextModelSelectionMode: OpenAITextModelSelectionMode = .automatic
    ) {
        self.provider = provider
        self.pluginConfiguration = pluginConfiguration
        self.supportsDirectUpdates = supportsDirectUpdates
        self.showsUpdateSettings = showsUpdateSettings
        self.recordingStartSoundEnabled = recordingStartSoundEnabled
        self.projectVocabularyEnabled = projectVocabularyEnabled
        self.selectedTranscriptionLanguages = selectedTranscriptionLanguages
        self.useCustomCorrections = useCustomCorrections
        self.emojiPostProcessingEnabled = emojiPostProcessingEnabled
        featureVisibility = SettingsFeatureVisibility(
            pluginConfiguration: pluginConfiguration,
            provider: provider,
            transcriptRetouchEnabled: transcriptRetouchEnabled,
            emojiPostProcessingEnabled: emojiPostProcessingEnabled,
            aiEmojiResolverEnabled: aiEmojiResolverEnabled,
            voiceEditCommandsEnabled: voiceEditCommandsEnabled,
            voiceEditCommandMode: voiceEditCommandMode,
            openAITextModelSelectionMode: openAITextModelSelectionMode
        )
        self.openAITextModelSelectionMode = openAITextModelSelectionMode
    }

    func isEnabled(_ pluginID: PluginID) -> Bool {
        pluginConfiguration.isEnabled(pluginID)
    }

    var includesChinese: Bool {
        selectedTranscriptionLanguages.contains(.chinese)
    }

    var includesEnglish: Bool {
        selectedTranscriptionLanguages.contains(.english)
    }
}

enum SettingsSearchIndex {
    static func items(
        localizer: AppLocalizer,
        context: SettingsSearchContext
    ) -> [SettingsSearchItem] {
        var result: [SettingsSearchItem] = []

        func add(
            _ title: String,
            section: AppPanelSection,
            target: SettingsSearchTarget,
            keywords: [String]
        ) {
            let resolvedSection: AppPanelSection
            let pageTitle: String
            if let placement = target.pipelinePlacement {
                if placement.appearsInBasicSettings {
                    resolvedSection = .transcription
                    pageTitle = AppPanelSection.transcription.sidebarTitle(localizer: localizer)
                } else {
                    resolvedSection = .architecture
                    pageTitle = "\(localizer.advancedLabel()) · \(localizer.architectureStageTitle(placement.stage))"
                }
            } else {
                resolvedSection = section
                pageTitle = section.sidebarTitle(localizer: localizer)
            }

            result.append(
                SettingsSearchItem(
                    title: title,
                    pageTitle: pageTitle,
                    keywords: keywords,
                    section: resolvedSection,
                    target: target
                )
            )
        }

        func addFeature(
            _ title: String,
            section: AppPanelSection,
            target: SettingsSearchTarget,
            keywords: [String]
        ) {
            add(
                title,
                section: section,
                target: target,
                keywords: keywords
            )
        }

        add(
            localizer.text(.shortcut),
            section: .transcription,
            target: .inputShortcut,
            keywords: [
                "hotkey", "keyboard", "command", "option", "push to talk", "hold to talk",
                "快捷键", "快速鍵", "按住说话", "按鍵說話"
            ]
        )
        add(
            localizer.text(.recordingStartSound),
            section: .transcription,
            target: .inputRecordingCue,
            keywords: ["cue", "sound", "tone", "提示音", "录音声音", "錄音聲音"]
        )
        if context.recordingStartSoundEnabled {
            add(
                localizer.text(.recordingStartSoundStyle),
                section: .transcription,
                target: .inputRecordingCueStyle,
                keywords: ["cue style", "sound choice", "tone", "提示音风格", "声音选择", "提示音風格", "聲音選擇"]
            )
        }
        add(
            localizer.onboardingMicrophoneLabel(),
            section: .about,
            target: .microphonePermission,
            keywords: ["permission", "microphone", "mic access", "权限", "麦克风", "話筒", "權限", "麥克風"]
        )
        add(
            localizer.onboardingAccessibilityLabel(),
            section: .about,
            target: .accessibilityPermission,
            keywords: ["permission", "accessibility", "paste permission", "权限", "辅助功能", "自动粘贴", "權限", "輔助使用", "自動貼上"]
        )
        add(
            localizer.text(.transcriptionLanguage),
            section: .transcription,
            target: .transcriptionLanguage,
            keywords: ["language", "bilingual", "Chinese English", "语言", "中英混说", "語言", "日英"]
        )
        add(
            localizer.text(.provider),
            section: .transcription,
            target: .transcriptionProvider,
            keywords: ["cloud", "local", "OpenAI", "Gemini", "Google", "ElevenLabs", "Alibaba", "Qwen", "阿里云", "通义", "service", "服务商", "本地", "云端", "服務商", "本機"]
        )
        add(
            localizer.text(.audioInputDevice),
            section: .transcription,
            target: .audioInputDevice,
            keywords: ["microphone", "mic", "audio device", "麦克风", "输入设备", "麥克風", "輸入裝置"]
        )
        add(
            localizer.text(.whisperMode),
            section: .transcription,
            target: .whisperMode,
            keywords: ["whisper", "quiet", "soft voice", "耳语", "低声", "悄悄话", "耳語", "小聲"]
        )
        add(
            localizer.text(.model),
            section: .transcription,
            target: .transcriptionModel,
            keywords: ["model", "Whisper", "Scribe", "Gemini", "gemini-3.1-flash-lite", "Qwen", "qwen3-asr-flash", "gpt-4o-transcribe", "模型"]
        )

        let openAIIsAvailable = context.provider == .openAI
            || context.featureVisibility.usesOpenAITextFeatures
        add(
            "OpenAI · \(localizer.text(.apiKey))",
            section: .transcription,
            target: openAIIsAvailable ? .openAIAPIKey : .transcriptionProvider,
            keywords: ["OpenAI", "API", "key", "token", "credential", "keychain", "密钥", "钥匙串", "金鑰", "鑰匙圈"]
        )
        add(
            localizer.connectionDetailsLabel(),
            section: .transcription,
            target: openAIIsAvailable ? .openAIConnectionDetails : .transcriptionProvider,
            keywords: ["base URL", "organization ID", "project ID", "endpoint", "OpenAI compatible", "连接", "端点", "组织", "連線", "端點", "組織"]
        )
        if openAIIsAvailable {
            add(
                localizer.text(.baseURL),
                section: .transcription,
                target: .openAIBaseURL,
                keywords: ["endpoint", "OpenAI compatible", "server URL", "端点", "兼容接口", "端點", "相容介面"]
            )
            add(
                localizer.text(.organizationID),
                section: .transcription,
                target: .openAIOrganizationID,
                keywords: ["OpenAI organization", "org ID", "组织 ID", "組織 ID"]
            )
            add(
                localizer.text(.projectID),
                section: .transcription,
                target: .openAIProjectID,
                keywords: ["OpenAI project", "project ID", "项目 ID", "專案 ID"]
            )
        }
        add(
            "ElevenLabs · \(localizer.text(.apiKey))",
            section: .transcription,
            target: context.provider == .elevenLabs ? .elevenLabsAPIKey : .transcriptionProvider,
            keywords: ["ElevenLabs", "Scribe", "API", "key", "密钥", "金鑰"]
        )
        add(
            "Alibaba Qwen · \(localizer.text(.apiKey))",
            section: .transcription,
            target: context.provider == .alibaba ? .alibabaAPIKey : .transcriptionProvider,
            keywords: ["Alibaba", "Qwen", "DashScope", "Model Studio", "阿里云", "通义", "百炼", "API", "key", "密钥", "金鑰"]
        )
        add(
            "Google Gemini · \(localizer.text(.apiKey))",
            section: .transcription,
            target: context.provider == .gemini ? .geminiAPIKey : .transcriptionProvider,
            keywords: ["Gemini", "Google", "AI Studio", "API", "key", "credential", "密钥", "金鑰"]
        )
        add(
            localizer.text(.modelManagement),
            section: .transcription,
            target: context.provider == .local ? .localModelManagement : .transcriptionProvider,
            keywords: ["local model", "download model", "Whisper", "本地模型", "下载模型", "本機模型", "下載模型"]
        )
        if context.provider == .local {
            add(
                localizer.manualSetupLabel(),
                section: .transcription,
                target: .localManualSetup,
                keywords: ["executable", "model directory", "path", "手动设置", "模型目录", "路径", "手動設定", "模型目錄", "路徑"]
            )
        }
        add(
            localizer.advancedAudioLabel(),
            section: .audio,
            target: .advancedAudio,
            keywords: ["noise gate", "silence", "speech threshold", "minimum speech", "噪声", "静音", "阈值", "噪音", "靜音", "門檻"]
        )
        if context.provider == .local {
            add(
                localizer.text(.localWhisperPerformance),
                section: .audio,
                target: .localWhisperPerformance,
                keywords: ["performance", "speed", "quality", "性能", "速度", "质量", "效能", "品質"]
            )
        }
        add(
            localizer.text(.ignoreSilentRecordings),
            section: .audio,
            target: .ignoreSilentRecordings,
            keywords: ["noise gate", "silence", "empty recording", "忽略静音", "空录音", "忽略靜音", "空白錄音"]
        )
        add(
            localizer.text(.speechThreshold),
            section: .audio,
            target: .speechThreshold,
            keywords: ["threshold", "dB", "sensitivity", "阈值", "灵敏度", "門檻", "靈敏度"]
        )
        add(
            localizer.text(.minimumSpeech),
            section: .audio,
            target: .minimumSpeech,
            keywords: ["minimum duration", "short speech", "最短语音", "持续时间", "最短語音", "持續時間"]
        )

        addFeature(
            localizer.enableRulesLabel(),
            section: .postProcessing,
            target: .featureCorrectionRules,
            keywords: ["replacement rules", "replace text", "纠正规则", "替换规则", "修正規則", "取代規則"]
        )
        if context.isEnabled(.outputCustomCorrections), context.useCustomCorrections {
            add(
                localizer.text(.correctionRules),
                section: .postProcessing,
                target: .customCorrections,
                keywords: ["rule editor", "text replacement", "规则编辑", "替换内容", "規則編輯", "取代內容"]
            )
        }
        if context.includesChinese {
            addFeature(
                localizer.enableChineseConversionLabel(),
                section: .postProcessing,
                target: .featureChineseConversion,
                keywords: ["simplified", "traditional", "简体", "繁体", "簡體", "繁體"]
            )
            if context.isEnabled(.outputChineseConversion) {
                add(
                    localizer.text(.chineseTextConversion),
                    section: .postProcessing,
                    target: .chineseTextConversion,
                    keywords: ["conversion mode", "script", "简繁模式", "字形", "簡繁模式", "字形"]
                )
            }
        }
        addFeature(
            localizer.enableEmojiOutputLabel(),
            section: .postProcessing,
            target: .featureEmojiOutput,
            keywords: ["emoji", "表情", "表情符号", "表情符號", "絵文字"]
        )
        addFeature(
            context.isEnabled(.outputCleanup)
                ? localizer.text(.textCleanup)
                : localizer.enableTextCleanupLabel(),
            section: .postProcessing,
            target: .featureTextCleanup,
            keywords: [
                "sentence endings", "format", "punctuation", "whitespace", "newline",
                "句末处理", "文本清理", "标点", "空格", "换行",
                "句末處理", "文字清理", "標點", "空白", "換行",
                "文末処理", "句読点", "空白", "改行"
            ]
        )
        if context.isEnabled(.outputCleanup) {
            add(
                localizer.text(.punctuationHandling),
                section: .postProcessing,
                target: .punctuationHandling,
                keywords: [
                    "sentence endings", "automatic punctuation", "as transcribed",
                    "Chinese full stop", "punctuation mode",
                    "句末处理", "自动标点", "保留标点",
                    "句末處理", "自動標點", "保留標點",
                    "文末処理", "句読点", "自動補完"
                ]
            )
        }
        addFeature(
            localizer.text(.promptContext),
            section: .aiAndLLM,
            target: .featurePromptContext,
            keywords: ["prompt", "context", "instruction", "提示词", "上下文", "指令", "提示詞"]
        )
        if context.isEnabled(.smartPromptContext) {
            add(
                localizer.text(.customization),
                section: .aiAndLLM,
                target: .promptContexts,
                keywords: ["prompt list", "reusable prompt", "提示列表", "自定义提示", "提示清單", "自訂提示"]
            )
        }
        addFeature(
            localizer.text(.transcriptRetouch),
            section: .aiAndLLM,
            target: .featureTranscriptRetouch,
            keywords: ["LLM", "rewrite", "polish", "润色", "修饰", "潤飾"]
        )
        let voiceEditEnabled = context.featureVisibility.isVoiceModifyEnabled
        add(
            localizer.text(.voiceEditCommands),
            section: .aiAndLLM,
            target: .featureVoiceEdit,
            keywords: ["modify previous", "delete previous", "voice command", "修改上一条", "删除上一条", "修改上一條", "刪除上一條"]
        )
        if voiceEditEnabled {
            add(
                localizer.text(.voiceEditCommandMode),
                section: .aiAndLLM,
                target: .voiceEditMode,
                keywords: ["local only", "LLM fallback", "command mode", "本地命令", "模型回退", "本機指令", "模型備援"]
            )
        }
        add(
            localizer.floatingWindowLabel(),
            section: .transcription,
            target: .featureFloatingWindow,
            keywords: [
                "floating", "overlay", "correction window", "command return", "confirm correction",
                "悬浮", "浮窗", "纠正窗口", "确认替换", "快捷键",
                "懸浮", "修正視窗", "確認取代", "快速鍵"
            ]
        )
        add(
            localizer.manualTermsLabel(),
            section: .vocabulary,
            target: .manualTerms,
            keywords: [
                "preferred terms", "glossary", "jargon", "vocabulary source", "preset package",
                "Coding", "Machine Learning", "ML", "Product Management", "PM",
                "常用词", "术语", "词汇", "词库", "内置术语包", "编程开发", "机器学习", "产品管理",
                "常用詞", "術語", "詞彙", "詞庫", "內建術語包", "程式開發", "機器學習", "產品管理",
                "優先用語", "用語集", "内蔵用語パック", "コーディング", "機械学習", "プロダクト管理"
            ]
        )
        add(
            localizer.correctionLearningLabel(),
            section: .advanced,
            target: .featureAdaptiveRecognition,
            keywords: [
                "correction learning", "adaptive recognition", "learn edits", "spelling hints",
                "replacement", "cloud AI", "纠错学习", "历史修改", "替换", "云端 AI",
                "修正學習", "歷史修改", "替換", "雲端 AI", "修正学習", "履歴の修正"
            ]
        )
        add(
            localizer.correctionDataLabel(),
            section: .advanced,
            target: .correctionData,
            keywords: [
                "learning history", "manual corrections", "correction data", "personalization data",
                "export learning", "clear learning", "学习记录", "人工纠正", "历史修改", "修改数据",
                "學習記錄", "人工修正", "歷史修改", "修改資料", "学習履歴", "手動修正"
            ]
        )
        add(
            localizer.projectVocabularyLabel(),
            section: .vocabulary,
            target: .projectVocabulary,
            keywords: ["project", "folder", "repository", "code terms", "项目", "文件夹", "代码术语", "專案", "資料夾", "程式術語"]
        )
        add(
            localizer.linkProjectFolderLabel(),
            section: .vocabulary,
            target: context.projectVocabularyEnabled ? .linkProject : .projectVocabulary,
            keywords: ["add project", "folder", "repository", "关联文件夹", "添加项目", "連結資料夾", "加入專案"]
        )

        add(
            localizer.text(.afterEachTranscription),
            section: .postProcessing,
            target: context.isEnabled(.outputCleanup) ? .transcriptBoundary : .featureTextCleanup,
            keywords: [
                "smart space", "automatic space", "newline", "return", "enter",
                "line break", "separator", "add nothing", "after transcription",
                "自动空格", "智能空格", "回车", "换行", "不添加", "句末",
                "智慧空格", "自動空格", "換行", "不加入", "改行", "追加しない"
            ]
        )
        if context.isEnabled(.outputCleanup) {
            if context.includesEnglish {
                add(
                    localizer.text(.lowercaseEnglish),
                    section: .postProcessing,
                    target: .lowercaseEnglish,
                    keywords: ["lowercase", "capitalization", "英文小写", "大小写", "英文小寫", "大小寫"]
                )
            }
            if context.includesChinese, context.includesEnglish {
                add(
                    localizer.text(.insertSpaceBetweenChineseAndEnglish),
                    section: .postProcessing,
                    target: .insertChineseEnglishSpace,
                    keywords: ["Chinese English spacing", "CJK space", "中英空格", "中英文空格"]
                )
            }
        }
        if context.isEnabled(.outputEmoji) {
            add(
                localizer.text(.aiEmojiResolver),
                section: .aiAndLLM,
                target: context.emojiPostProcessingEnabled
                    ? .aiEmojiResolver
                    : .featureEmojiOutput,
                keywords: ["AI emoji", "emoji model", "表情模型", "絵文字モデル"]
            )
            if context.emojiPostProcessingEnabled {
                add(
                    localizer.text(.smartEmojiMatching),
                    section: .postProcessing,
                    target: .smartEmojiMatching,
                    keywords: ["smart emoji", "fuzzy emoji", "智能表情", "智慧表情"]
                )
            }
        }
        if context.provider == .gemini {
            add(
                localizer.geminiTextEnhancementsLabel(),
                section: .aiAndLLM,
                target: .geminiAPIKey,
                keywords: [
                    "Gemini", "Gemini Flash", "text enhancement", "LLM model", "retouch",
                    "Gemini 文本增强", "文本润色", "Gemini 文字增強", "文字潤飾", "Gemini テキスト拡張"
                ]
            )
        } else {
            add(
                localizer.openAITextModelSelectionLabel(),
                section: .aiAndLLM,
                target: .openAITextModel,
                keywords: [
                    "chat model", "LLM model", "automatic model", "fixed model", "disable AI",
                    "AI 模型", "自动选择", "固定模型", "不使用", "自動選択", "固定モデル"
                ]
            )
        }

        add(
            localizer.advancedLabel(),
            section: .architecture,
            target: .architectureOverview,
            keywords: [
                "architecture", "pipeline", "signal chain", "transcription workflow",
                "架构", "信号链", "处理流程", "转写流程",
                "架構", "信號鏈", "處理流程", "轉寫流程"
            ]
        )
        add(
            localizer.text(.appLanguage),
            section: .transcription,
            target: .appLanguage,
            keywords: ["interface language", "English", "中文", "日本語", "界面语言", "介面語言"]
        )
        add(
            localizer.launchAtLoginLabel(),
            section: .transcription,
            target: .launchAtLogin,
            keywords: ["startup", "login item", "open at login", "开机启动", "登录项", "啟動", "登入項目"]
        )
        if context.showsUpdateSettings {
            add(
                localizer.text(.updates),
                section: .transcription,
                target: .updates,
                keywords: ["update", "upgrade", "Sparkle", "更新", "升级", "升級"]
            )
            if context.supportsDirectUpdates {
                add(
                    localizer.text(.automaticUpdateChecks),
                    section: .transcription,
                    target: .updates,
                    keywords: ["check automatically", "background update", "自动检查更新", "自動檢查更新"]
                )
                add(
                    localizer.text(.automaticUpdates),
                    section: .transcription,
                    target: .updates,
                    keywords: ["download update", "install update", "自动更新", "自动下载", "自動更新", "自動下載"]
                )
                add(
                    localizer.text(.checkForUpdates),
                    section: .transcription,
                    target: .updates,
                    keywords: ["check now", "new version", "检查更新", "新版本", "檢查更新"]
                )
            }
        }
        add(
            localizer.text(.exportSettings),
            section: .about,
            target: .exportSettings,
            keywords: ["export", "backup", "JSON", "导出", "备份", "匯出", "備份"]
        )

        add(
            localizer.aboutAppLabel(),
            section: .about,
            target: .aboutInformation,
            keywords: ["version", "build", "bundle", "关于", "版本", "關於"]
        )
        add(
            localizer.text(.reportFeedback),
            section: .about,
            target: .reportFeedback,
            keywords: ["feedback", "bug", "issue", "support", "反馈", "问题", "回饋", "問題"]
        )
        add(
            localizer.privacyLabel(),
            section: .about,
            target: .privacy,
            keywords: ["privacy", "data collection", "local first", "隐私", "数据", "隱私", "資料"]
        )
        add(
            localizer.releaseNotesLabel(),
            section: .about,
            target: .releaseNotes,
            keywords: ["release notes", "changelog", "what's new", "版本说明", "更新日志", "版本說明", "更新紀錄"]
        )
        add(
            localizer.uninstallAndDataLabel(),
            section: .about,
            target: .uninstallAndData,
            keywords: ["uninstall", "remove", "delete data", "keychain", "卸载", "删除数据", "钥匙串", "解除安裝", "刪除資料", "鑰匙圈"]
        )
        add(
            localizer.text(.localData),
            section: .about,
            target: .localData,
            keywords: ["recordings", "application support", "crash reports", "folder", "录音", "本地数据", "崩溃报告", "錄音", "本機資料", "當機報告"]
        )

        return result
    }

    static func search(
        _ query: String,
        in items: [SettingsSearchItem],
        limit: Int = 7
    ) -> [SettingsSearchItem] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }

        let tokens = normalizedQuery.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return []
        }

        return items
            .compactMap { item -> (SettingsSearchItem, Int)? in
                let title = normalize(item.title)
                let page = normalize(item.pageTitle)
                let keywords = item.keywords.map(normalize)
                var score = 0

                for token in tokens {
                    if title == token {
                        score += 1_000
                    } else if title.hasPrefix(token) {
                        score += 700
                    } else if title.contains(token) {
                        score += 500
                    } else if keywords.contains(where: { $0 == token }) {
                        score += 420
                    } else if keywords.contains(where: { $0.hasPrefix(token) }) {
                        score += 320
                    } else if keywords.contains(where: { $0.contains(token) }) {
                        score += 240
                    } else if isCJK(token), title.count >= 2, token.contains(title) {
                        score += 210
                    } else if isCJK(token), keywords.contains(where: { $0.count >= 2 && token.contains($0) }) {
                        score += 180
                    } else if page.contains(token) {
                        score += 100
                    } else {
                        return nil
                    }
                }

                if title == normalizedQuery {
                    score += 1_500
                } else if title.hasPrefix(normalizedQuery) {
                    score += 600
                }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.title.localizedStandardCompare(rhs.0.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}
