import Foundation

enum AppStatus {
    case ready
    case preparingMicrophone
    case recording
    case checkingAudio
    case transcribing
    case ignoredSilence
    case ignoredEmptyTranscript
    case microphonePermissionGranted
}

enum AppTextKey: String, CaseIterable {
    case about
    case aboutShuo
    case aboutDescription
    case aboutDiagnosticsHint
    case general
    case appLanguage
    case dictation
    case transcription
    case provider
    case model
    case customModel
    case modelManagement
    case localWhisperEngine
    case localWhisperModel
    case localWhisperModelDirectory
    case localWhisperExecutablePath
    case localWhisperModelDirectoryPath
    case localWhisperModelPath
    case localWhisperPerformance
    case localWhisperPerformanceHint
    case audioInputDevice
    case automaticAudioInput
    case systemDefaultAudioInput
    case audioInputDeviceHint
    case unavailableAudioInputDevice
    case chooseFile
    case clear
    case close
    case noLocalModelSelected
    case noLocalModelsFound
    case localWhisperAutoDetectHint
    case localWhisperModelDirectoryHint
    case localWhisperMVPHint
    case installLocalWhisperEngine
    case detectLocalWhisperEngine
    case details
    case localWhisperEngineInstallHint
    case localWhisperManagedModels
    case localWhisperManagedModelsHint
    case download
    case delete
    case use
    case installed
    case notInstalled
    case installing
    case downloading
    case transcriptionLanguage
    case chineseScript
    case context
    case openAI
    case apiKey
    case baseURL
    case organizationID
    case projectID
    case sendContextPrompt
    case controls
    case pushToTalk
    case shortcut
    case recordingStartSound
    case recordingStartSoundStyle
    case recordingStartSoundHint
    case previewRecordingStartSound
    case requestMicrophonePermission
    case openAccessibilitySettings
    case openMicrophone
    case noiseGate
    case ignoreSilentRecordings
    case whisperMode
    case whisperModeHint
    case speechThreshold
    case minimumSpeech
    case output
    case pasteAfterTranscription
    case restoreClipboardAfterPaste
    case voiceEditCommands
    case voiceEditCommandMode
    case developerGlossary
    case useGlossary
    case history
    case metrics
    case customization
    case aiAndLLM
    case specialCommands
    case modifyPreviousCommand
    case modifyPreviousCommandHint
    case deletePreviousCommand
    case deletePreviousCommandHint
    case emojiCommand
    case emojiCommandHint
    case settings
    case quitShuo
    case promptContext
    case postProcessing
    case glossary
    case addPromptContext
    case chineseTextConversion
    case keepChineseText
    case convertChineseToSimplified
    case convertChineseToTraditional
    case chineseTextConversionHint
    case transcriptRetouch
    case enableTranscriptRetouch
    case transcriptRetouchHint
    case emojiOutput
    case smartEmojiMatching
    case smartEmojiMatchingHint
    case aiEmojiResolver
    case aiEmojiResolverHint
    case emojiReplacementHint
    case punctuationHandling
    case automaticPunctuationRecommended
    case asTranscribed
    case keepPunctuation
    case replacePunctuationWithSpaces
    case textCleanup
    case collapseRepeatedSpaces
    case trimWhitespace
    case lowercaseEnglish
    case insertSpaceBetweenChineseAndEnglish
    case appendNewlineAfterTranscription
    case appendSpaceAfterTranscription
    case sentenceEndings
    case afterEachTranscription
    case smartSpaceRecommended
    case newLine
    case addNothing
    case sentenceEndingsHint
    case postProcessingHint
    case promptTitle
    case promptInstruction
    case preferredTerms
    case preferredTermsHint
    case correctionRules
    case correctionRulesHint
    case dataManagement
    case extensions
    case pluginProfile
    case pluginConfigurationHint
    case importPluginConfiguration
    case exportPluginConfiguration
    case useMVPProfile
    case useFullDevelopmentProfile
    case pluginStatus
    case enabled
    case disabled
    case corePlugin
    case experimentalPlugin
    case settingsExportDisabledHint
    case updates
    case automaticUpdateChecks
    case automaticUpdates
    case checkForUpdates
    case updatePlaceholderHint
    case updatePlaceholderMessage
    case appInformation
    case version
    case build
    case bundleIdentifier
    case support
    case openWebsite
    case reportFeedback
    case copyDiagnostics
    case localData
    case applicationSupportFolder
    case crashReportsFolder
    case openDataFolder
    case openCrashReportsFolder
    case exportSettings
    case exportSettingsHint
    case downloadHistoricalMetrics
    case downloadHistoricalMetricsHint
    case startRecording
    case stopRecording
    case latestTranscript
    case lastError
    case copy
    case paste
    case playAudio
    case stopAudio
    case retranscribeAudio
    case recordedAudioUnavailable
    case errorDetails
    case save
    case transcript
    case noTranscriptSelected
    case accessibilityPermissionMayBeNeeded
    case totalTranscripts
    case totalCharacters
    case totalWords
    case estimatedTokens
    case usageOverTime
    case hourly
    case daily
    case noTimelineData
    case languageBreakdown
    case noMetricsYet
    case otherMetricsNote
    case characters
    case words
    case tokens
    case transcriptsUnit
    case secondsUnit
}

struct AppLocalizer {
    let language: AppLanguage

    func text(_ key: AppTextKey) -> String {
        resourceText("text.\(key.rawValue)", fallback: key.rawValue)
    }

    func status(_ status: AppStatus) -> String {
        switch status {
        case .ready:
            return localized("Ready", "就绪", "就緒", "待機中")
        case .preparingMicrophone:
            return localized(
                "Preparing microphone...",
                "麦克风准备中...",
                "麥克風準備中...",
                "マイクを準備中..."
            )
        case .recording:
            return localized("Recording...", "正在录音...", "正在錄音...", "録音中...")
        case .checkingAudio:
            return localized("Checking audio...", "正在检查音频...", "正在檢查音訊...", "音声を確認中...")
        case .transcribing:
            return localized("Transcribing...", "正在转写...", "正在轉寫...", "文字起こし中...")
        case .ignoredSilence:
            return localized("Ignored silence", "已忽略静音", "已忽略靜音", "無音を無視しました")
        case .ignoredEmptyTranscript:
            return localized("Ignored empty transcript", "已忽略空转写", "已忽略空轉寫", "空の文字起こしを無視しました")
        case .microphonePermissionGranted:
            return localized("Microphone permission granted.", "麦克风权限已授权。", "麥克風權限已授權。", "マイク権限が許可されました。")
        }
    }

    func providerName(_ provider: TranscriptionProvider) -> String {
        switch provider {
        case .local:
            return localized("Local", "本地", "本機", "ローカル")
        case .openAI:
            return localized("Cloud (OpenAI)", "云端（OpenAI）", "雲端（OpenAI）", "クラウド（OpenAI）")
        case .elevenLabs:
            return localized("Cloud (ElevenLabs)", "云端（ElevenLabs）", "雲端（ElevenLabs）", "クラウド（ElevenLabs）")
        case .alibaba:
            return localized("Cloud (Alibaba Qwen)", "云端（阿里云通义）", "雲端（阿里雲通義）", "クラウド（Alibaba Qwen）")
        case .custom:
            return localized("Custom", "自定义", "自訂", "カスタム")
        }
    }

    func elevenLabsKeytermDetail() -> String {
        localized(
            "Scribe v2 receives active preferred and project terms as keyterms. Audio is sent to ElevenLabs; ElevenLabs bills keyterm prompting as an add-on.",
            "Scribe v2 会把当前常用词和项目词汇作为关键词提示；录音会发送给 ElevenLabs，关键词提示会由 ElevenLabs 额外计费。",
            "Scribe v2 會把目前常用詞與專案詞彙作為關鍵詞提示；錄音會傳送給 ElevenLabs，關鍵詞提示會由 ElevenLabs 額外計費。",
            "Scribe v2 は優先語とプロジェクト用語をキータームとして使用します。音声はElevenLabsへ送信され、キーターム機能は追加料金の対象です。"
        )
    }

    func onboardingElevenLabsDetail() -> String {
        localized(
            "Scribe v2 supports 90+ languages and accepts Shuo terminology as keyterms.",
            "Scribe v2 支持 90 多种语言，并会接收 Shuo 的术语作为关键词提示。",
            "Scribe v2 支援 90 多種語言，並會接收 Shuo 的術語作為關鍵詞提示。",
            "Scribe v2 は 90 以上の言語に対応し、Shuo の用語をキータームとして受け取ります。"
        )
    }

    func onboardingAlibabaDetail() -> String {
        localized(
            "Qwen3-ASR-Flash is optimized for Chinese and mixed-language speech. This release uses Model Studio's Beijing endpoint.",
            "Qwen3-ASR-Flash 针对中文和多语言语音优化；此版本使用百炼北京地域接口。",
            "Qwen3-ASR-Flash 針對中文與多語言語音最佳化；此版本使用 Model Studio 北京地域介面。",
            "Qwen3-ASR-Flash は中国語と多言語音声向けです。このリリースはModel Studioの北京エンドポイントを使用します。"
        )
    }

    func alibabaProviderDetail() -> String {
        localized(
            "Qwen3-ASR-Flash sends the current recording to Alibaba Cloud Model Studio's Beijing endpoint. Use an API key created for the Beijing region.",
            "Qwen3-ASR-Flash 会把当前录音发送到阿里云百炼北京地域接口；请使用在北京地域创建的 API key。",
            "Qwen3-ASR-Flash 會把目前錄音傳送至阿里雲 Model Studio 北京地域介面；請使用在北京地域建立的 API key。",
            "Qwen3-ASR-Flash は現在の録音をAlibaba Cloud Model Studioの北京エンドポイントへ送信します。北京リージョンのAPIキーを使用してください。"
        )
    }

    func apiKeyGuideLabel() -> String {
        localized(
            "How to get an API key",
            "如何获取 API key",
            "如何取得 API key",
            "APIキーの取得方法"
        )
    }

    func openAIModelSelectionLabel() -> String {
        localized("Model selection", "模型选择", "模型選擇", "モデル選択")
    }

    func openAITextModelSelectionLabel() -> String {
        localized("Text model selection", "文本模型选择", "文字模型選擇", "テキストモデル選択")
    }

    func openAIModelSelectionModeName(_ mode: OpenAIModelSelectionMode) -> String {
        switch mode {
        case .automatic:
            return localized("Automatic (recommended)", "自动（推荐）", "自動（建議）", "自動（推奨）")
        case .fixed:
            return localized("Fixed model", "固定模型", "固定模型", "固定モデル")
        }
    }

    func openAITextModelSelectionModeName(_ mode: OpenAITextModelSelectionMode) -> String {
        switch mode {
        case .automatic:
            return localized("Automatic (recommended)", "自动（推荐）", "自動（建議）", "自動（推奨）")
        case .fixed:
            return localized("Fixed model", "固定模型", "固定模型", "固定モデル")
        case .disabled:
            return localized("Do not use", "不使用", "不使用", "使用しない")
        }
    }

    func openAIModelPurposeName(_ purpose: OpenAIModelPurpose) -> String {
        switch purpose {
        case .accuracy:
            return localized("Accuracy", "准确优先", "準確優先", "精度優先")
        case .speedAndCost:
            return localized("Fast and economical", "快速经济", "快速經濟", "高速・低コスト")
        case .compatibility:
            return localized("Compatibility", "兼容", "相容", "互換性")
        case .textPostProcessing:
            return localized("Text processing", "文本处理", "文字處理", "テキスト処理")
        }
    }

    func refreshOpenAIModelsLabel() -> String {
        localized("Refresh models", "刷新模型", "重新整理模型", "モデルを更新")
    }

    func refreshingOpenAIModels() -> String {
        localized("Refreshing available models...", "正在刷新可用模型...", "正在重新整理可用模型...", "利用可能なモデルを更新中...")
    }

    func openAIModelRefreshNeedsAPIKey() -> String {
        localized(
            "Add an API key to check available models.",
            "添加 API key 后可以检查可用模型。",
            "加入 API key 後可以檢查可用模型。",
            "利用可能なモデルを確認するにはAPIキーを追加してください。"
        )
    }

    func openAIModelsNotChecked() -> String {
        localized(
            "Available models have not been checked yet.",
            "尚未检查这个账户可用的模型。",
            "尚未檢查這個帳戶可用的模型。",
            "このアカウントで利用可能なモデルはまだ確認されていません。"
        )
    }

    func openAIModelRefreshFailed(_ detail: String) -> String {
        localized(
            "Model refresh failed: \(detail)",
            "模型刷新失败：\(detail)",
            "模型重新整理失敗：\(detail)",
            "モデルの更新に失敗しました: \(detail)"
        )
    }

    func noCompatibleOpenAIModels() -> String {
        localized(
            "This API key returned no compatible transcription models.",
            "这个 API key 没有返回兼容的转写模型。",
            "這個 API key 沒有傳回相容的轉寫模型。",
            "このAPIキーでは互換性のある文字起こしモデルが見つかりませんでした。"
        )
    }

    func noCompatibleOpenAITextModels() -> String {
        localized(
            "This API key returned no compatible text-processing models.",
            "这个 API key 没有返回兼容的文本处理模型。",
            "這個 API key 沒有傳回相容的文字處理模型。",
            "このAPIキーでは互換性のあるテキスト処理モデルが見つかりませんでした。"
        )
    }

    func openAIModelsAvailable(count: Int, automaticModelID: String) -> String {
        localized(
            "\(count) compatible models available. Automatic uses \(automaticModelID).",
            "有 \(count) 个兼容模型；自动模式使用 \(automaticModelID)。",
            "有 \(count) 個相容模型；自動模式使用 \(automaticModelID)。",
            "互換モデルが\(count)個あります。自動では\(automaticModelID)を使用します。"
        )
    }

    func openAIModelUnavailableLabel() -> String {
        localized("Unavailable", "当前不可用", "目前不可用", "利用不可")
    }

    func openAIAutomaticModelHint(_ modelID: String) -> String {
        localized(
            "Shuo selected \(modelID) from the compatible models returned for this API key.",
            "Shuo 根据这个 API key 返回的兼容模型选择了 \(modelID)。",
            "Shuo 根據這個 API key 傳回的相容模型選擇了 \(modelID)。",
            "このAPIキーで利用できる互換モデルから\(modelID)を選択しました。"
        )
    }

    func openAIAutomaticTextModelHint(_ modelID: String) -> String {
        localized(
            "Automatically uses \(modelID).",
            "自动使用 \(modelID)。",
            "自動使用 \(modelID)。",
            "自動的に\(modelID)を使用します。"
        )
    }

    func fixedOpenAITextModelHint() -> String {
        localized(
            "All enabled cloud text features share this model.",
            "所有已启用的云端文字功能共用这个模型。",
            "所有已啟用的雲端文字功能共用這個模型。",
            "有効なクラウド文字機能はすべてこのモデルを共有します。"
        )
    }

    func disabledOpenAITextModelHint() -> String {
        localized(
            "Cloud text models are not called. Features that require one are paused.",
            "不会调用云端文本模型；依赖它的功能会暂停。",
            "不會呼叫雲端文字模型；依賴它的功能會暫停。",
            "クラウドのテキストモデルを呼び出さず、必要とする機能は停止します。"
        )
    }

    func languageHintName(_ hint: LanguageHint) -> String {
        switch hint {
        case .automatic:
            return localized("Automatic", "自动", "自動", "自動")
        case .chinese:
            return localized("Chinese", "中文", "中文", "中国語")
        case .english:
            return localized("English", "英文", "英文", "英語")
        case .spanish:
            return localized("Spanish", "西班牙语", "西班牙文", "スペイン語")
        case .french:
            return localized("French", "法语", "法文", "フランス語")
        case .japanese:
            return localized("Japanese", "日文", "日文", "日本語")
        case .mixed:
            return localized("Multiple languages", "多语言混合", "多語言混合", "複数言語")
        }
    }

    func transcriptionLanguageName(_ language: TranscriptionLanguage) -> String {
        switch language {
        case .chinese:
            return languageHintName(.chinese)
        case .english:
            return languageHintName(.english)
        case .spanish:
            return languageHintName(.spanish)
        case .french:
            return languageHintName(.french)
        case .japanese:
            return languageHintName(.japanese)
        }
    }

    func transcriptionLanguageSelectionDetail() -> String {
        localized(
            "Choose one or more. With multiple languages selected, the model detects the spoken language automatically.",
            "可选择一种或多种语言。多选时，模型会自动识别当前说的是哪种语言。",
            "可選擇一種或多種語言。多選時，模型會自動識別目前說的是哪種語言。",
            "1つ以上選択できます。複数選択時は、話されている言語をモデルが自動判定します。"
        )
    }

    func localWhisperLanguageCapabilityName(_ capability: LocalWhisperLanguageCapability) -> String {
        switch capability {
        case .unknown:
            return localized(
                "Model language: Unknown",
                "模型语言：未知",
                "模型語言：未知",
                "モデル言語: 不明"
            )
        case .englishOnly:
            return localized(
                "Model language: English only",
                "模型语言：仅英文",
                "模型語言：僅英文",
                "モデル言語: 英語のみ"
            )
        case .multilingual:
            return localized(
                "Model language: Multilingual",
                "模型语言：多语言",
                "模型語言：多語言",
                "モデル言語: 多言語"
            )
        }
    }

    func localWhisperEnglishOnlyLanguageHint() -> String {
        localized(
            "This local model is English-only, so English is the only available language.",
            "这个本地模型仅支持英文，因此语言固定为英文。",
            "這個本機模型僅支援英文，因此語言固定為英文。",
            "このローカルモデルは英語専用のため、言語は英語に固定されます。"
        )
    }

    func localWhisperModelTierName(_ tier: LocalWhisperModelTier) -> String {
        switch tier {
        case .small:
            return localized("Small", "小模型", "小模型", "小型")
        case .balanced:
            return localized("Balanced", "均衡", "均衡", "バランス")
        case .large:
            return localized("Large", "大模型", "大模型", "大型")
        }
    }

    func localWhisperPerformanceModeName(_ mode: LocalWhisperPerformanceMode) -> String {
        switch mode {
        case .balanced:
            return localized("Balanced", "均衡", "均衡", "バランス")
        case .fast:
            return localized("Fast", "快速", "快速", "高速")
        }
    }

    func localWhisperManagedModelSummary(_ model: LocalWhisperManagedModel) -> String {
        [
            model.sizeDescription,
            localWhisperLanguageCapabilityName(model.languageCapability)
        ]
        .joined(separator: " · ")
    }

    func localWhisperModelSizeExplanation() -> String {
        localized(
            "Model family names describe architecture and quality, not file size. Medium is unquantized; Large Turbo Q5 and Q8 use a smaller Turbo architecture plus quantization, so their downloads are smaller.",
            "模型名称表示架构与质量，不等于文件大小。Medium 未量化；Large Turbo Q5 与 Q8 使用更精简的 Turbo 架构并经过量化，因此下载体积更小。",
            "模型名稱表示架構與品質，不等於檔案大小。Medium 未量化；Large Turbo Q5 與 Q8 使用更精簡的 Turbo 架構並經過量化，因此下載體積更小。",
            "モデル名は構造と品質を示すもので、ファイルサイズ順ではありません。Medium は非量子化、Large Turbo Q5/Q8 は小型の Turbo 構造を量子化しているため、ダウンロード容量が小さくなります。"
        )
    }

    func localWhisperModelInUseLabel() -> String {
        localized("In use", "已使用", "已使用", "使用中")
    }

    func useLocalWhisperModelLabel(_ model: LocalWhisperManagedModel) -> String {
        localized(
            "Use \(model.displayName)",
            "使用 \(model.displayName)",
            "使用 \(model.displayName)",
            "\(model.displayName) を使用"
        )
    }

    func downloadLocalWhisperModelLabel(_ model: LocalWhisperManagedModel) -> String {
        localized(
            "Download \(model.displayName)",
            "下载 \(model.displayName)",
            "下載 \(model.displayName)",
            "\(model.displayName) をダウンロード"
        )
    }

    func removeLocalWhisperModelLabel(_ model: LocalWhisperManagedModel) -> String {
        localized(
            "Remove \(model.displayName)",
            "移除 \(model.displayName)",
            "移除 \(model.displayName)",
            "\(model.displayName) を削除"
        )
    }

    func deleteLocalWhisperModelConfirmationTitle(_ model: LocalWhisperManagedModel?) -> String {
        guard let model else {
            return localized(
                "Delete model?",
                "删除模型？",
                "刪除模型？",
                "モデルを削除しますか？"
            )
        }
        let name = model.displayName
        return localized(
            "Delete \(name)?",
            "删除 \(name)？",
            "刪除 \(name)？",
            "\(name) を削除しますか？"
        )
    }

    func deleteLocalWhisperModelConfirmationDetail() -> String {
        localized(
            "This removes the downloaded model from this Mac. History and recordings are not affected.",
            "这只会从这台 Mac 删除已下载的模型，不会影响历史记录和录音。",
            "這只會從這台 Mac 刪除已下載的模型，不會影響歷史記錄和錄音。",
            "この Mac からダウンロード済みモデルだけを削除します。履歴と録音には影響しません。"
        )
    }

    func cancelLocalWhisperModelDownloadLabel(_ model: LocalWhisperManagedModel) -> String {
        localized(
            "Cancel downloading \(model.displayName)",
            "取消下载 \(model.displayName)",
            "取消下載 \(model.displayName)",
            "\(model.displayName) のダウンロードをキャンセル"
        )
    }

    func moreLocalWhisperModelsLabel() -> String {
        localized("More models", "更多模型", "更多模型", "その他のモデル")
    }

    func fewerLocalWhisperModelsLabel() -> String {
        localized("Fewer models", "收起模型", "收起模型", "モデルを閉じる")
    }

    func q8QuantizationLabel() -> String {
        localized("Q8 quantization", "Q8 量化", "Q8 量化", "Q8 量子化")
    }

    func localWhisperEngineReady(_ path: String) -> String {
        localized(
            "whisper-cli is ready: \(path)",
            "whisper-cli 已就绪：\(path)",
            "whisper-cli 已就緒：\(path)",
            "whisper-cli を使用できます: \(path)"
        )
    }

    func builtInLocalWhisperEngineLabel() -> String {
        localized(
            "Local engine included",
            "已内置本地引擎",
            "已內建本機引擎",
            "ローカルエンジン内蔵"
        )
    }

    func builtInLocalWhisperEngineDetail() -> String {
        localized(
            "Download a model below to start local transcription. No Homebrew setup is required.",
            "只需在下方下载模型即可开始本地转写，不需要安装 Homebrew。",
            "只需在下方下載模型即可開始本機轉寫，不需要安裝 Homebrew。",
            "下からモデルをダウンロードするだけでローカル文字起こしを開始できます。Homebrew は不要です。"
        )
    }

    func localWhisperEngineNotFound() -> String {
        localized(
            "Could not find whisper-cli in common Homebrew locations.",
            "没有在常见 Homebrew 路径里找到 whisper-cli。",
            "沒有在常見 Homebrew 路徑裡找到 whisper-cli。",
            "一般的な Homebrew パスに whisper-cli が見つかりません。"
        )
    }

    func installingLocalWhisperEngine() -> String {
        localized(
            "Installing whisper.cpp with Homebrew...",
            "正在通过 Homebrew 安装 whisper.cpp...",
            "正在透過 Homebrew 安裝 whisper.cpp...",
            "Homebrew で whisper.cpp をインストール中..."
        )
    }

    func downloadingLocalWhisperModel(_ modelName: String) -> String {
        localized(
            "Downloading \(modelName)...",
            "正在下载 \(modelName)...",
            "正在下載 \(modelName)...",
            "\(modelName) をダウンロード中..."
        )
    }

    func localWhisperDownloadProgress(
        modelName: String,
        progress: LocalWhisperDownloadProgress
    ) -> String {
        let percentage = Int((progress.fractionCompleted * 100).rounded(.down))
        let received = ByteCountFormatter.string(
            fromByteCount: progress.receivedByteCount,
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: progress.totalByteCount,
            countStyle: .file
        )
        return localized(
            "Downloading \(modelName): \(percentage)% (\(received) of \(total))",
            "正在下载 \(modelName)：\(percentage)%（\(received) / \(total)）",
            "正在下載 \(modelName)：\(percentage)%（\(received) / \(total)）",
            "\(modelName) をダウンロード中：\(percentage)%（\(received) / \(total)）"
        )
    }

    func cancellingLocalWhisperDownload() -> String {
        localized(
            "Cancelling model download...",
            "正在取消模型下载...",
            "正在取消模型下載...",
            "モデルのダウンロードをキャンセル中..."
        )
    }

    func localWhisperDownloadCancelled() -> String {
        localized(
            "Model download cancelled.",
            "模型下载已取消。",
            "模型下載已取消。",
            "モデルのダウンロードをキャンセルしました。"
        )
    }

    func localWhisperInsufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64) -> String {
        let required = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
        let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
        return localized(
            "Not enough free space. The download needs \(required); \(available) is available.",
            "磁盘空间不足。下载需要 \(required)，当前可用 \(available)。",
            "磁碟空間不足。下載需要 \(required)，目前可用 \(available)。",
            "空き容量が不足しています。必要：\(required)、利用可能：\(available)。"
        )
    }

    func localWhisperModelReady(_ filename: String) -> String {
        localized(
            "Local model is ready: \(filename)",
            "本地模型已就绪：\(filename)",
            "本機模型已就緒：\(filename)",
            "ローカルモデルを使用できます: \(filename)"
        )
    }

    func localWhisperModelDeleted(_ filename: String) -> String {
        localized(
            "Deleted local model: \(filename)",
            "已删除本地模型：\(filename)",
            "已刪除本機模型：\(filename)",
            "ローカルモデルを削除しました: \(filename)"
        )
    }

    func localWhisperHomebrewNotFound() -> String {
        localized(
            "Homebrew was not found. Install Homebrew first, or choose an existing whisper-cli manually.",
            "没有找到 Homebrew。请先安装 Homebrew，或者手动选择已有的 whisper-cli。",
            "沒有找到 Homebrew。請先安裝 Homebrew，或手動選擇已有的 whisper-cli。",
            "Homebrew が見つかりません。先に Homebrew をインストールするか、既存の whisper-cli を手動で選択してください。"
        )
    }

    func localWhisperSetupProcessFailed(command: String, statusCode: Int32, output: String) -> String {
        localized(
            "\(command) failed (\(statusCode)): \(output)",
            "\(command) 失败（\(statusCode)）：\(output)",
            "\(command) 失敗（\(statusCode)）：\(output)",
            "\(command) が失敗しました（\(statusCode)）: \(output)"
        )
    }

    func localWhisperInstalledExecutableNotFound(_ output: String) -> String {
        localized(
            "whisper.cpp installed, but whisper-cli was not found. \(output)",
            "whisper.cpp 已安装，但没有找到 whisper-cli。\(output)",
            "whisper.cpp 已安裝，但沒有找到 whisper-cli。\(output)",
            "whisper.cpp はインストールされましたが、whisper-cli が見つかりません。\(output)"
        )
    }

    func localWhisperDownloadFailed(_ message: String) -> String {
        localized(
            "Model download failed: \(message)",
            "模型下载失败：\(message)",
            "模型下載失敗：\(message)",
            "モデルのダウンロードに失敗しました: \(message)"
        )
    }

    func chineseScriptName(_ preference: ChineseScriptPreference) -> String {
        switch preference {
        case .automatic:
            return localized("Automatic", "自动", "自動", "自動")
        case .simplified:
            return localized("Simplified Chinese", "简体中文", "簡體中文", "簡体字中国語")
        case .traditional:
            return localized("Traditional Chinese", "繁体中文", "繁體中文", "繁体字中国語")
        }
    }

    func chineseScriptOutputLabel() -> String {
        localized(
            "Chinese script",
            "中文字形",
            "中文字形",
            "中国語の字体"
        )
    }

    func chineseTextConversionModeName(
        _ mode: ChineseTextConversionMode
    ) -> String {
        switch mode {
        case .keep:
            return localized("Keep", "保留", "保留", "そのまま")
        case .simplified:
            return localized("Simplified", "简体", "简体", "簡体字")
        case .traditional:
            // Keep the actual target glyphs visible so the segmented control
            // also serves as a tiny output preview in Chinese interfaces.
            return localized("Traditional", "繁體", "繁體", "繁体字")
        }
    }

    func shortcutName(_ shortcut: PushToTalkShortcut) -> String {
        switch shortcut {
        case .rightOption:
            return localized("Right Option", "右 Option", "右 Option", "右Option")
        case .rightCommand:
            return localized("Right Command", "右 Command", "右 Command", "右Command")
        }
    }

    func advancedLabel() -> String {
        localized("Advanced", "高级", "進階", "詳細設定")
    }

    func commonSettingLabel() -> String {
        localized("Common", "常用", "常用", "基本")
    }

    func advancedSettingLabel() -> String {
        localized("Advanced", "进阶", "進階", "詳細")
    }

    func expandedStateLabel() -> String {
        localized("Expanded", "已展开", "已展開", "展開済み")
    }

    func collapsedStateLabel() -> String {
        localized("Collapsed", "已收起", "已收合", "折りたたみ済み")
    }

    func homeLabel() -> String {
        localized("Home", "首页", "首頁", "ホーム")
    }

    func architectureLabel() -> String {
        localized("Architecture", "架构", "架構", "アーキテクチャ")
    }

    func advancedOverviewTitle() -> String {
        localized(
            "How Shuo processes a recording",
            "Shuo 如何处理一段录音",
            "Shuo 如何處理一段錄音",
            "Shuoが録音を処理する流れ"
        )
    }

    func advancedOverviewDetail() -> String {
        localized(
            "Choose any stage above to see every setting used there.",
            "点击上方任一阶段，查看这一环节使用的全部设置。",
            "點按上方任一階段，查看這個環節使用的全部設定。",
            "上のステージを選ぶと、その工程で使うすべての設定を確認できます。"
        )
    }

    func architectureInteractionHint() -> String {
        localized(
            "Point to preview a stage. Click to show all of its settings below.",
            "悬停预览阶段，点击后在下方显示这一阶段的全部设置。",
            "懸停預覽階段，點擊後在下方顯示這一階段的全部設定。",
            "ステージにポインタを置くと概要を表示し、クリックすると下にすべての設定を表示します。"
        )
    }

    func architecturePathVariationHint() -> String {
        localized(
            "The actual path adapts to the provider and features you enable.",
            "实际路径会根据你启用的服务商和功能自动调整。",
            "實際路徑會根據你啟用的服務商與功能自動調整。",
            "実際の経路は、有効なプロバイダと機能に合わせて変わります。"
        )
    }

    func architectureOpenDestinationHint(_ destination: String) -> String {
        localized(
            "Shows all \(destination) settings below.",
            "在下方显示\(destination)的全部设置。",
            "在下方顯示\(destination)的全部設定。",
            "\(destination)のすべての設定を下に表示します。"
        )
    }

    func architectureReturnToOverviewHint() -> String {
        localized(
            "Returns to the seven-stage overview.",
            "返回七阶段总览。",
            "返回七階段總覽。",
            "7段階の概要に戻ります。"
        )
    }

    func architectureStageTitle(_ stage: ArchitectureStage) -> String {
        switch stage {
        case .voiceInput:
            return localized("Voice input", "语音输入", "語音輸入", "音声入力")
        case .audioProcessing:
            return localized("Audio processing", "声音处理", "聲音處理", "音声処理")
        case .contextPreparation:
            return localized("Context", "上下文", "上下文", "コンテキスト")
        case .aiInference:
            return localized("AI inference", "AI 推理", "AI 推論", "AI推論")
        case .postProcessing:
            return localized("Post-processing", "后处理", "後處理", "後処理")
        case .humanCorrection:
            return localized("Human correction", "人工纠正", "人工修正", "手動修正")
        case .finalResult:
            return localized("Final result", "最终结果", "最終結果", "最終結果")
        }
    }

    func architectureStageDetail(_ stage: ArchitectureStage) -> String {
        switch stage {
        case .voiceInput:
            return localized(
                "Captures microphone audio only while the push-to-talk shortcut is held.",
                "只在按住快捷键时捕获麦克风声音。",
                "只在按住快速鍵時擷取麥克風聲音。",
                "プッシュトゥトークのキーを押している間だけマイク音声を取り込みます。"
            )
        case .audioProcessing:
            return localized(
                "Detects speech, adapts quiet input, and prepares clean audio for transcription.",
                "检测人声、适配轻声输入，并为转写准备干净的音频。",
                "偵測人聲、適配輕聲輸入，並為轉寫準備乾淨的音訊。",
                "音声を検出し、小さな声を調整して文字起こし用の音声を整えます。"
            )
        case .contextPreparation:
            return localized(
                "Combines preferred terms, project vocabulary, and reusable prompt context.",
                "整合常用词、项目词汇和可复用的提示上下文。",
                "整合常用詞、專案詞彙與可重用的提示上下文。",
                "優先用語、プロジェクト語彙、再利用できるプロンプト文脈をまとめます。"
            )
        case .aiInference:
            return localized(
                "The selected local or cloud model turns the prepared audio into a draft.",
                "由选定的本地或云端模型把处理后的音频变成初稿。",
                "由選定的本機或雲端模型把處理後的音訊變成初稿。",
                "選択したローカルまたはクラウドモデルが、整えた音声を下書きに変換します。"
            )
        case .postProcessing:
            return localized(
                "Applies enabled text cleanup, script, emoji, replacement, and retouch steps.",
                "按需执行文本整理、字形、Emoji、替换和润色。",
                "視需要執行文字整理、字形、Emoji、替換與潤飾。",
                "有効なテキスト整形、字体変換、絵文字、置換、修正を適用します。"
            )
        case .humanCorrection:
            return localized(
                "The floating bar lets you revise the latest insertion while retaining both versions.",
                "在悬浮栏修改最新输入，同时保留修改前后两个版本。",
                "在懸浮列修改最新輸入，同時保留修改前後兩個版本。",
                "フローティングウインドウで直前の入力を修正し、修正前後の両方を保持します。"
            )
        case .finalResult:
            return localized(
                "The confirmed text stays in the target app and remains reviewable in local history and metrics.",
                "确认后的文字留在目标 App，也可以在本地历史和统计中回看。",
                "確認後的文字留在目標 App，也可以在本機歷史和統計中回看。",
                "確定したテキストは対象アプリに残り、ローカル履歴と統計でも確認できます。"
            )
        }
    }

    func settingsSearchPlaceholder() -> String {
        localized("Search settings", "搜索设置", "搜尋設定", "設定を検索")
    }

    func settingsSearchNoResults() -> String {
        localized("No matching settings", "没有匹配的设置", "沒有符合的設定", "一致する設定はありません")
    }

    func voiceInputLabel() -> String {
        localized("Settings", "设置", "設定", "設定")
    }

    func textOutputLabel() -> String {
        localized("Text Output", "文本输出", "文字輸出", "テキスト出力")
    }

    func textOutputNavigationLabel() -> String {
        localized("Output", "输出", "輸出", "出力")
    }

    func aiAndCommandsLabel() -> String {
        localized("AI & Commands", "AI 与命令", "AI 與指令", "AIとコマンド")
    }

    func aiNavigationLabel() -> String {
        localized("AI", "AI", "AI", "AI")
    }

    func audioNavigationLabel() -> String {
        localized("Audio", "音频", "音訊", "音声")
    }

    func metricsLabel() -> String {
        localized("Metrics", "统计", "統計", "統計")
    }

    func systemLabel() -> String {
        localized("System", "系统", "系統", "システム")
    }

    func applicationSettingsLabel() -> String {
        localized("App", "应用", "應用程式", "アプリ")
    }

    func launchAtLoginLabel() -> String {
        launchAtLoginLabel(appName: AppBuildIdentity.displayName)
    }

    func launchAtLoginLabel(appName: String) -> String {
        localized(
            "Launch \(appName) at login",
            "登录时启动 \(appName)",
            "登入時啟動 \(appName)",
            "ログイン時に\(appName)を起動"
        )
    }

    func launchAtLoginApprovalDetail() -> String {
        localized(
            "macOS needs approval in Login Items before Shuo can launch automatically.",
            "macOS 需要先在“登录项”中批准，Shuo 才能自动启动。",
            "macOS 需要先在「登入項目」中批准，Shuo 才能自動啟動。",
            "Shuoを自動起動するには、macOSのログイン項目で許可が必要です。"
        )
    }

    func openLoginItemsLabel() -> String {
        localized("Open Login Items", "打开登录项", "開啟登入項目", "ログイン項目を開く")
    }

    func launchAtLoginUpdateFailed(_ detail: String) -> String {
        localized(
            "Could not update Launch at Login: (detail)",
            "无法更新登录时启动：(detail)",
            "無法更新登入時啟動：(detail)",
            "ログイン時の起動設定を更新できませんでした：(detail)"
        )
    }

    func recognitionLabel() -> String {
        localized("Recognition", "识别", "辨識", "認識")
    }

    func microphoneLabel() -> String {
        localized("Microphone", "麦克风", "麥克風", "マイク")
    }

    func permissionsLabel() -> String {
        localized("Permissions", "权限", "權限", "権限")
    }

    func permissionGrantedLabel() -> String {
        localized("Granted", "已授权", "已授權", "許可済み")
    }

    func managePermissionLabel() -> String {
        localized("Manage", "管理", "管理", "管理")
    }

    func finalResultCongratulationsTitle() -> String {
        localized(
            "Congratulations — your final result is ready.",
            "恭喜，你已抵达最终结果。",
            "恭喜，你已抵達最終結果。",
            "おめでとうございます。最終結果が完成しました。"
        )
    }

    func finalResultCongratulationsDetail() -> String {
        localized(
            "Your words are ready. Review the local history or see how your voice adds up over time.",
            "文字已经就绪。你可以回看本地历史，也可以看看声音随时间留下的积累。",
            "文字已經就緒。你可以回看本機歷史，也可以看看聲音隨時間留下的累積。",
            "テキストの準備ができました。ローカル履歴を見返したり、音声入力の積み重ねを確認できます。"
        )
    }

    func dictationOffStatusLabel() -> String {
        localized("Dictation off", "听写已关", "聽寫已關", "音声入力オフ")
    }

    func setupNeededStatusLabel() -> String {
        localized("Setup needed", "需要设置", "需要設定", "設定が必要")
    }

    func featuresLabel() -> String {
        localized("Features", "功能", "功能", "機能")
    }

    func transcriptionEnhancementsLabel() -> String {
        localized("Transcription Enhancements", "转写增强", "轉寫增強", "文字起こし強化")
    }

    func voiceCommandsSectionLabel() -> String {
        localized("Voice Commands", "语音命令", "語音指令", "音声コマンド")
    }

    func localPerformanceLabel() -> String {
        localized("Local Performance", "本地性能", "本機效能", "ローカル性能")
    }

    func silenceDetectionLabel() -> String {
        localized("Silence Detection", "静音检测", "靜音偵測", "無音検出")
    }

    func enableRulesLabel() -> String {
        localized("Apply replacement rules", "应用替换规则", "套用替換規則", "置換ルールを適用")
    }

    func fixedReplacementSourceLabel() -> String {
        localized("Match text", "匹配文本", "比對文字", "一致させる文字")
    }

    func fixedReplacementSourcePlaceholder() -> String {
        localized("Match text", "匹配文本", "比对文字", "一致させる文字")
    }

    func fixedReplacementValueLabel() -> String {
        localized("Replace with", "替换为", "替換為", "置換後")
    }

    func fixedReplacementValuePlaceholder() -> String {
        localized("Replace with", "替换为", "替換為", "置換後")
    }

    func addFixedReplacementLabel() -> String {
        localized("Add Rule", "添加规则", "加入規則", "ルールを追加")
    }

    func deleteFixedReplacementLabel() -> String {
        localized("Delete Rule", "删除规则", "刪除規則", "ルールを削除")
    }

    func noFixedReplacementsLabel() -> String {
        localized(
            "No fixed replacements yet.",
            "还没有固定替换。",
            "還沒有固定替換。",
            "固定置換はまだありません。"
        )
    }

    func fixedReplacementSourceRequiredLabel() -> String {
        localized(
            "Enter the text to match.",
            "请输入需要匹配的文本。",
            "請輸入需要比對的文字。",
            "一致させる文字を入力してください。"
        )
    }

    func unrecognizedReplacementLinesLabel(_ count: Int) -> String {
        localized(
            "\(count) legacy line\(count == 1 ? "" : "s") could not be read",
            "有 \(count) 条旧内容无法识别",
            "有 \(count) 條舊內容無法辨識",
            "読み取れない旧形式の行が \(count) 件あります"
        )
    }

    func showLegacyReplacementLinesLabel() -> String {
        localized("Show", "查看", "查看", "表示")
    }

    func hideLegacyReplacementLinesLabel() -> String {
        localized("Hide", "收起", "收起", "隠す")
    }

    func legacyReplacementLinesHint() -> String {
        localized(
            "These lines are preserved but do not run. Delete them only if you no longer need them.",
            "这些内容会被原样保留，但不会执行；确认不再需要后再删除。",
            "這些內容會被原樣保留，但不會執行；確認不再需要後再刪除。",
            "この行はそのまま保存されますが実行されません。不要な場合のみ削除してください。"
        )
    }

    func enableChineseConversionLabel() -> String {
        localized(
            "Enable script conversion",
            "启用简繁字形转换",
            "啟用簡繁字形轉換",
            "文字変換を有効にする"
        )
    }

    func enableEmojiOutputLabel() -> String {
        localized("Apply replacement rules", "应用替换规则", "套用替換規則", "置換ルールを適用")
    }

    func enableTextCleanupLabel() -> String {
        localized("Enable text cleanup", "启用文本整理", "啟用文字整理", "テキスト整形を有効にする")
    }

    func outputCleanupFeatureDetail() -> String {
        localized(
            "Control punctuation, whitespace, casing, and line endings after transcription.",
            "控制转写后的标点、空格、英文大小写和换行。",
            "控制轉寫後的標點、空格、英文大小寫和換行。",
            "文字起こし後の句読点、空白、大文字小文字、改行を調整します。"
        )
    }

    func requiresCloudAILabel() -> String {
        localized("Requires cloud AI", "需要云端 AI", "需要雲端 AI", "クラウドAIが必要")
    }

    func mayUseCloudAILabel() -> String {
        localized(
            "May use cloud AI",
            "可能使用云端 AI",
            "可能使用雲端 AI",
            "クラウドAIを使用する場合があります"
        )
    }

    func cloudAIUnavailableInLocalModeDetail() -> String {
        localized(
            "Unavailable in Local mode so text stays on this Mac.",
            "本地模式下不可用，确保文字留在这台 Mac。",
            "本機模式下無法使用，確保文字留在這台 Mac。",
            "テキストをこのMac内に保つため、ローカルモードでは使用できません。"
        )
    }

    func punctuationModeDetail(_ mode: PunctuationPostProcessingMode) -> String {
        switch mode {
        case .automatic:
            return localized(
                "Keeps existing punctuation and adds a language-appropriate final period when it is missing; commands, URLs, and number-only input are left alone.",
                "保留已有标点；缺少句号时按结尾语言补“。”或“.”。命令、网址和纯数字保持不变。",
                "保留已有標點；缺少句號時按結尾語言補「。」或「.」。指令、網址和純數字保持不變。",
                "既存の句読点を保ち、必要な場合だけ言語に合う句点を補います。コマンド、URL、数字だけの入力は変更しません。"
            )
        case .keep:
            return localized(
                "Leaves the model's punctuation unchanged.",
                "保留模型转写出的标点，不增不减。",
                "保留模型轉寫出的標點，不增不減。",
                "モデルが出力した句読点を変更しません。"
            )
        case .replaceWithSpaces:
            return localized(
                "Replaces Chinese commas and periods with spaces; other punctuation is preserved.",
                "把中文逗号和句号替换为空格，其他标点保留。",
                "把中文逗號和句號替換為空格，其他標點保留。",
                "中国語の読点と句点を空白に置き換え、その他の句読点は保ちます。"
            )
        }
    }

    func transcriptBoundaryModeDetail(_ mode: TranscriptInsertionBoundaryMode) -> String {
        switch mode {
        case .smartSpace:
            return localized(
                "Adds a separating space after Latin letters or numbers. Bare Chinese or Japanese text gets a safety space only when no punctuation or closing quote already provides a boundary.",
                "拉丁字母或数字结尾时添加分隔空格；中文或日文裸文本仅在没有标点或右引号形成边界时添加安全空格。",
                "拉丁字母或數字結尾時加入分隔空格；中文或日文裸文字僅在沒有標點或右引號形成邊界時加入安全空格。",
                "ラテン文字や数字の後に区切り空白を追加します。中国語・日本語は句読点や閉じ引用符がない場合だけ安全用の空白を追加します。"
            )
        case .newline:
            return localized(
                "Moves the cursor to a new line after every completed transcription.",
                "每次转写完成后换到下一行。",
                "每次轉寫完成後換到下一行。",
                "文字起こしが完了するたびに改行します。"
            )
        case .none:
            return localized(
                "Adds no space or line break after the final text.",
                "最终文字后不添加空格或换行。",
                "最終文字後不加入空格或換行。",
                "最終テキストの後に空白や改行を追加しません。"
            )
        }
    }

    // MARK: - Context source modules

    func enablePromptContextLabel() -> String {
        localized(
            "Enable prompt context",
            "启用提示上下文",
            "啟用提示上下文",
            "プロンプトコンテキストを有効にする"
        )
    }

    func newPromptContextName(_ number: Int) -> String {
        localized(
            "Context \(number)",
            "上下文 \(number)",
            "上下文 \(number)",
            "コンテキスト \(number)"
        )
    }

    func promptContextsEmptyDetail() -> String {
        localized(
            "No contexts yet.",
            "还没有上下文。",
            "尚未加入上下文。",
            "コンテキストはまだありません。"
        )
    }

    func vocabularySourcesDetail() -> String {
        localized(
            "Keep difficult names and jargon in editable vocabularies. Disabled vocabularies stay saved but are omitted from transcription hints.",
            "把容易误识别的名称和术语保存在可编辑词库中；关闭的词库仍会保留，但不会加入转写提示。",
            "把容易誤辨識的名稱與術語儲存在可編輯詞庫中；關閉的詞庫仍會保留，但不會加入轉寫提示。",
            "誤認識されやすい名前や専門用語を編集可能な用語集に保存します。無効な用語集は保存されたまま、文字起こしのヒントから除外されます。"
        )
    }

    func alibabaVocabularyUnavailableDetail() -> String {
        localized(
            "Alibaba transcription does not currently accept vocabulary hints from Shuo. Editable vocabularies and project terms remain saved, but they will not affect transcription while Alibaba is selected.",
            "阿里云转写目前不会接收 Shuo 的词汇提示。可编辑词库和项目词汇仍会保留，但选择阿里云时不会影响转写。",
            "阿里雲轉寫目前不會接收 Shuo 的詞彙提示。可編輯詞庫與專案詞彙仍會保留，但選擇阿里雲時不會影響轉寫。",
            "Alibabaの文字起こしは現在、Shuoの語彙ヒントを受け取りません。編集可能な用語集とプロジェクト用語は保存されますが、Alibaba選択中の文字起こしには反映されません。"
        )
    }

    func addVocabularyLabel() -> String {
        localized("Add vocabulary", "添加词库", "加入詞庫", "用語集を追加")
    }

    func vocabularySourcesEmptyDetail() -> String {
        localized(
            "No vocabularies yet.",
            "还没有词库。",
            "尚未加入詞庫。",
            "用語集はまだありません。"
        )
    }

    func newVocabularyName(_ number: Int) -> String {
        localized(
            "Vocabulary \(number)",
            "词库 \(number)",
            "詞庫 \(number)",
            "用語集 \(number)"
        )
    }

    func vocabularyNameLabel() -> String {
        localized("Vocabulary name", "词库名称", "詞庫名稱", "用語集の名前")
    }

    func unnamedVocabularyLabel() -> String {
        localized("Untitled vocabulary", "未命名词库", "未命名詞庫", "名称未設定の用語集")
    }

    func importedPreferredTermsLabel() -> String {
        localized(
            "Existing preferred terms",
            "已有常用词",
            "現有常用詞",
            "既存の優先用語"
        )
    }

    func deleteVocabularyLabel() -> String {
        localized("Delete Vocabulary", "删除词库", "刪除詞庫", "用語集を削除")
    }

    func deleteVocabularyConfirmationTitle() -> String {
        localized("Delete this vocabulary?", "删除这个词库？", "刪除這個詞庫？", "この用語集を削除しますか？")
    }

    func deleteVocabularyConfirmationDetail() -> String {
        localized(
            "Its saved terms will be removed from Shuo. This cannot be undone.",
            "其中保存的词汇会从 Shuo 中删除，且无法撤销。",
            "其中儲存的詞彙會從 Shuo 中刪除，且無法復原。",
            "保存された用語はShuoから削除されます。この操作は取り消せません。"
        )
    }

    func deleteContextSourceLabel() -> String {
        localized("Delete Context", "删除上下文", "刪除上下文", "コンテキストを削除")
    }

    func deleteContextConfirmationTitle() -> String {
        localized("Delete this context?", "删除这个上下文？", "刪除這個上下文？", "このコンテキストを削除しますか？")
    }

    func deleteContextConfirmationDetail() -> String {
        localized(
            "This saved instruction will be removed from Shuo. This cannot be undone.",
            "这条已保存的说明会从 Shuo 中删除，且无法撤销。",
            "這則已儲存的說明會從 Shuo 中刪除，且無法復原。",
            "保存された指示はShuoから削除されます。この操作は取り消せません。"
        )
    }

    func promptContextFeatureDetail() -> String {
        localized(
            "When supported by the selected model, provide reusable context hints to cloud transcription.",
            "在模型支持的情况下，为云端转写提供可复用的上下文提示。",
            "在模型支援的情況下，為雲端轉寫提供可重用的上下文提示。",
            "選択したモデルが対応している場合、クラウド文字起こしへ再利用可能なコンテキストヒントを渡します。"
        )
    }

    func terminologyPresetTitle(_ id: String) -> String {
        switch id {
        case TerminologyPresetCatalog.codingID:
            return localized("Coding", "编程开发", "程式開發", "コーディング")
        case TerminologyPresetCatalog.machineLearningID:
            return localized("Machine learning", "机器学习", "機器學習", "機械学習")
        case TerminologyPresetCatalog.productManagementID:
            return localized("Product management", "产品管理", "產品管理", "プロダクト管理")
        default:
            return id
        }
    }

    func frequentCorrectionMappingsLabel() -> String {
        localized("Learned correction patterns", "已学习的修改", "已學習的修改", "学習した修正パターン")
    }

    func frequentCorrectionMappingsEmptyDetail() -> String {
        localized(
            "As you manually correct transcripts, recurring word-level changes will appear here in frequency order. You can select a pattern before it finishes collecting evidence.",
            "随着你手动纠正转写，重复出现的词元修改会按频率显示在这里；证据仍在积累时也可以先选中。",
            "隨著你手動修正轉寫，重複出現的詞元修改會按頻率顯示在這裡；證據仍在累積時也可以先選取。",
            "文字起こしを手動修正すると、繰り返し現れる語句単位の変更が頻度順に表示されます。証拠の蓄積中でも先に選択できます。"
        )
    }

    func useCorrectionPatternLabel() -> String {
        localized(
            "Learn this correction",
            "学习这条修改",
            "學習這條修改",
            "この修正を学習"
        )
    }

    func useCorrectionPatternAccessibilityLabel(
        observed: String,
        preferred: String
    ) -> String {
        localized(
            "Learn correction from \(observed) to \(preferred)",
            "学习从 \(observed) 到 \(preferred) 的修改",
            "學習從 \(observed) 到 \(preferred) 的修改",
            "\(observed) から \(preferred) への修正を学習"
        )
    }

    func correctionLearningLabel() -> String {
        localized(
            "Learning from Corrections",
            "人工纠正学习",
            "人工修正學習",
            "手動修正からの学習"
        )
    }

    func useCorrectionLearningLabel() -> String {
        localized(
            "Learn from past corrections",
            "学习过往人工纠正",
            "學習過往人工修正",
            "過去の手動修正から学習"
        )
    }

    func correctionLearningToggleDetail() -> String {
        localized(
            "Manual corrections are saved locally even while this is off. Turn it on to select learned patterns; a selected row affects new transcription only after it reaches the safety threshold.",
            "关闭时仍会在本机记录人工纠正。开启后可以逐条选择学习模式；只有达到安全门槛后，选中的模式才会影响新的转写。",
            "關閉時仍會在本機記錄人工修正。開啟後可以逐條選擇學習模式；只有達到安全門檻後，選取的模式才會影響新的轉寫。",
            "オフの間も手動修正はローカルに保存されます。オンにすると学習パターンを個別に選択でき、安全基準を満たした項目だけが新しい文字起こしへ反映されます。"
        )
    }

    func correctionLearningModeLabel() -> String {
        localized("Learning method", "学习方式", "學習方式", "反映方法")
    }

    func adaptiveRecognitionModeTitle(_ mode: AdaptiveRecognitionMode) -> String {
        switch mode {
        case .vocabularyHints:
            return localized("Cloud AI", "云端 AI", "雲端 AI", "クラウドAI")
        case .highConfidenceReplacement:
            return localized("Replacement", "替换", "替換", "置換")
        }
    }

    func adaptiveRecognitionModeDetail(_ mode: AdaptiveRecognitionMode) -> String {
        switch mode {
        case .vocabularyHints:
            return localized(
                "An enabled pattern needs at least two observations with 75% agreement. Cloud AI then receives only the preferred wording as a transcription hint and never rewrites the result locally.",
                "逐条开启的模式需累计出现至少 2 次且一致率达到 75%；之后云端 AI 只接收修正后的写法作为转写提示，不会在本地直接改写结果。",
                "逐條開啟的模式需累計出現至少 2 次且一致率達到 75%；之後雲端 AI 只接收修正後的寫法作為轉寫提示，不會在本機直接改寫結果。",
                "個別に有効化したパターンが2回以上、75%以上の一貫性を満たすと、クラウドAIには修正後の表記だけをヒントとして送ります。結果をローカルで書き換えることはありません。"
            )
        case .highConfidenceReplacement:
            return localized(
                "Enabled patterns replace locally only after three distinct sessions agree with no conflict or reverse mapping. Nothing is sent to cloud AI. Numbers, short common words, and single CJK characters are never auto-replaced. This is a context-free global token rule, so reserve it for names and jargon rather than ambiguous everyday words.",
                "逐条开启的模式只有在 3 个不同会话完全一致，且没有冲突或反向修改时，才在本地替换，不会发送给云端 AI。数字、短常用词和单个中日韩字符绝不会自动替换。这是不理解上下文的全局词元规则，适合专名和术语，不适合普通多义词。",
                "逐條開啟的模式只有在 3 個不同工作階段完全一致，且沒有衝突或反向修改時，才在本機替換，不會傳送給雲端 AI。數字、短常用詞和單個中日韓字元絕不會自動替換。這是不理解上下文的全域詞元規則，適合專名和術語，不適合一般多義詞。",
                "個別に有効化したパターンは、3つの異なるセッションが完全に一致し、競合や逆方向の修正がない場合だけローカルで置換し、クラウドAIには送信しません。数字、短い一般語、CJKの1文字は自動置換しません。文脈を理解しないグローバルな語句ルールのため、一般的な多義語ではなく固有名詞や専門用語に使ってください。"
            )
        }
    }

    func correctionLearningCloudDetail() -> String {
        localized(
            "For cloud transcription, only enabled, eligible preferred terms are sent to the selected provider as vocabulary hints. The original mistaken text and complete History are not sent for learning.",
            "使用云端转写时，只有已逐条开启且符合条件的修正后写法会作为词汇提示发送给当前服务商；修改前文本和完整历史不会因此被发送。",
            "使用雲端轉寫時，只有已逐條開啟且符合條件的修正後寫法會作為詞彙提示傳送給目前服務商；修改前文字和完整歷史不會因此被傳送。",
            "クラウド文字起こしでは、個別に有効化され条件を満たした修正後の表記だけを語彙ヒントとして選択中のプロバイダへ送ります。誤認識された元の文字や履歴全体は送信しません。"
        )
    }

    func correctionHintsUnavailableForAlibabaDetail() -> String {
        localized(
            "Alibaba transcription does not currently accept correction hints. Your learning data stays saved; Replacement can still apply enabled, eligible patterns locally after transcription.",
            "阿里云转写目前不接收纠错提示。学习数据仍会保留；选择“替换”后，已逐条开启且符合条件的模式仍可在转写完成后于本地应用。",
            "阿里雲轉寫目前不接收修正提示。學習資料仍會保留；選擇「替換」後，已逐條開啟且符合條件的模式仍可在轉寫完成後於本機套用。",
            "Alibabaの文字起こしは現在、修正ヒントを受け取りません。学習データは保存され、「置換」では個別に有効化され条件を満たしたパターンを文字起こし後にローカル適用できます。"
        )
    }

    func correctionHintsUnavailableForDiarizationDetail() -> String {
        localized(
            "The OpenAI diarization model does not accept vocabulary hints. Your learning data stays saved; Replacement can still apply enabled, eligible patterns locally after transcription.",
            "OpenAI 的说话人分离模型不接收词汇提示。学习数据仍会保留；选择“替换”后，已逐条开启且符合条件的模式仍可在转写完成后于本地应用。",
            "OpenAI 的說話者分離模型不接收詞彙提示。學習資料仍會保留；選擇「替換」後，已逐條開啟且符合條件的模式仍可在轉寫完成後於本機套用。",
            "OpenAIの話者分離モデルは語彙ヒントを受け取りません。学習データは保存され、「置換」では個別に有効化され条件を満たしたパターンを文字起こし後にローカル適用できます。"
        )
    }

    func correctionLearningSummary(evidenceCount: Int, patternCount: Int) -> String {
        localized(
            "\(evidenceCount) manual corrections · \(patternCount) learned patterns",
            "\(evidenceCount) 次人工纠正 · \(patternCount) 个学习模式",
            "\(evidenceCount) 次人工修正 · \(patternCount) 個學習模式",
            "手動修正\(evidenceCount)件 · 学習パターン\(patternCount)件"
        )
    }

    func correctionLearningPatternStatus(_ pattern: CorrectionLearningPattern) -> String {
        if pattern.hasReverseMapping || pattern.isAmbiguous {
            return localized("conflicting", "存在冲突", "存在衝突", "競合あり")
        }
        if pattern.isHighConfidenceReplacementEligible {
            return localized("safe to replace", "可安全替换", "可安全替換", "安全に置換可能")
        }
        if pattern.isVocabularyHintEligible {
            return localized("ready as hint", "可用于提示", "可用於提示", "ヒントに使用可能")
        }
        return localized("collecting", "继续积累", "繼續累積", "学習中")
    }

    func cloudConnectionLocationDetail() -> String {
        localized(
            "The API key is available in Settings; full connection details live in Advanced · AI inference.",
            "API key 可在“设置”中管理；完整连接详情位于“高级 · AI 推理”。",
            "API key 可在「設定」中管理；完整連線詳細資料位於「進階 · AI 推論」。",
            "APIキーは「設定」、詳細な接続設定は「詳細設定 · AI推論」で管理できます。"
        )
    }

    func advancedAudioLabel() -> String {
        localized("Advanced Audio", "高级音频", "進階音訊", "高度な音声設定")
    }

    func manualSetupLabel() -> String {
        localized("Manual Setup", "手动设置", "手動設定", "手動設定")
    }

    func connectionDetailsLabel() -> String {
        localized("Connection Details", "连接详情", "連線詳細資料", "接続の詳細")
    }

    func openAIConnectionDetailsHint() -> String {
        localized(
            "Keep the default Base URL for OpenAI. Change it only for an OpenAI-compatible service; Shuo adds the request paths automatically.",
            "使用 OpenAI 时请保留默认 Base URL。只有使用 OpenAI 兼容服务时才需要修改，Shuo 会自动补全请求路径。",
            "使用 OpenAI 時請保留預設 Base URL。只有使用 OpenAI 相容服務時才需要修改，Shuo 會自動補全請求路徑。",
            "OpenAIを使用する場合は既定のBase URLのままにします。OpenAI互換サービスの場合のみ変更してください。リクエストパスはShuoが自動で追加します。"
        )
    }

    func optionalFieldLabel(_ label: String) -> String {
        localized(
            "\(label) (optional)",
            "\(label)（可选）",
            "\(label)（選填）",
            "\(label)（任意）"
        )
    }

    func restoreOpenAIConnectionDefaultsLabel() -> String {
        localized(
            "Restore OpenAI defaults",
            "恢复 OpenAI 默认值",
            "恢復 OpenAI 預設值",
            "OpenAIの既定値に戻す"
        )
    }

    func openShuoLabel() -> String {
        openAppLabel(appName: AppBuildIdentity.displayName)
    }

    func openAppLabel(appName: String) -> String {
        localized(
            "Open \(appName)",
            "打开 \(appName)",
            "開啟 \(appName)",
            "\(appName)を開く"
        )
    }

    func holdSpeakReleaseTitle() -> String {
        localized("Hold — speak — release", "按住—说话—松开", "按住—說話—放開", "押す—話す—離す")
    }

    func holdSpeakReleaseDetail(shortcut: String) -> String {
        localized(
            "Hold \(shortcut), speak naturally, then release.",
            "按住 \(shortcut)，自然说话，然后松开。",
            "按住 \(shortcut)，自然說話，然後放開。",
            "\(shortcut) を押しながら話し、終わったら離します。"
        )
    }

    func homeShortcutInstructionPrefix() -> String {
        localized("Hold", "按住", "按住", "")
    }

    func homeShortcutInstructionSuffix() -> String {
        localized("to dictate.", "开始听写。", "開始聽寫。", "を押したまま話します。")
    }

    func preferredTermsHomeLabel() -> String {
        localized("Preferred Terms", "常用词", "常用詞", "優先用語")
    }

    func vocabularyLabel() -> String {
        localized("Vocabulary", "词汇", "詞彙", "語彙")
    }

    func manualTermsLabel() -> String {
        localized("Preferred Terms", "常用词", "常用詞", "優先用語")
    }

    func projectVocabularyLabel() -> String {
        localized("Project Vocabulary", "项目词汇", "專案詞彙", "プロジェクト語彙")
    }

    func projectVocabularyBetaLabel() -> String {
        localized("Project Vocabulary · Beta", "项目词汇 · Beta", "專案詞彙 · Beta", "プロジェクト語彙 · Beta")
    }

    func projectVocabularyEmptyDetail() -> String {
        localized(
            "Choose one or more local project folders. Shuo indexes distinctive names and symbols on this Mac, then sends only a small set of spelling hints during transcription.",
            "选择一个或多个本地项目文件夹。Shuo 会在本机索引有辨识度的名称和符号，转写时只发送少量拼写提示。",
            "選擇一個或多個本機專案資料夾。Shuo 會在本機索引有辨識度的名稱與符號，轉寫時只傳送少量拼字提示。",
            "1つ以上のローカルプロジェクトフォルダを選ぶと、このMac上で特徴的な名前とシンボルを索引し、文字起こし時には少数の表記ヒントだけを送信します。"
        )
    }

    func projectVocabularyBudgetDetail() -> String {
        localized(
            "Enabled projects share a budget of at most 60 high-priority terms per transcription. Linked folders stay local; cloud providers receive terms only, never paths or source files.",
            "所有启用的项目每次转写共同使用最多 60 个高优先级术语。关联文件夹保留在本机；云服务只会收到术语，不会收到路径或源文件。",
            "所有啟用的專案每次轉寫共同使用最多 60 個高優先級術語。連結資料夾保留在本機；雲端服務只會收到術語，不會收到路徑或原始檔案。",
            "有効なすべてのプロジェクトで、文字起こし1回あたり最大60件の高優先度用語を共有します。リンクしたフォルダはローカルに留まり、クラウドへ送るのは用語だけです。"
        )
    }

    func correctionDataLabel() -> String {
        localized("Learning history", "学习记录", "學習記錄", "学習履歴")
    }

    func savedCorrectionCountLabel(_ count: Int) -> String {
        localized(
            "\(count) complete edits",
            "完整修改 \(count) 次",
            "完整修改 \(count) 次",
            "完全な修正 \(count)件"
        )
    }

    func legacyCorrectionCountLabel(_ count: Int) -> String {
        localized(
            "\(count) legacy records retained",
            "另保留 \(count) 条旧版记录",
            "另保留 \(count) 筆舊版記錄",
            "旧形式の記録を\(count)件保持"
        )
    }

    func exportCorrectionDataLabel() -> String {
        localized("Export Learning Data", "导出学习数据", "匯出學習資料", "学習データを書き出す")
    }

    func clearCorrectionDataLabel() -> String {
        localized("Clear…", "清除…", "清除…", "消去…")
    }

    func clearCorrectionDataActionLabel() -> String {
        localized("Clear Learning Data", "清除学习数据", "清除學習資料", "学習データを消去")
    }

    func clearCorrectionDataConfirmationTitle() -> String {
        localized(
            "Clear all learning data?",
            "清除全部学习数据？",
            "清除全部學習資料？",
            "すべての学習データを消去しますか？"
        )
    }

    func clearCorrectionDataConfirmationDetail() -> String {
        localized(
            "This clears separately captured corrections and restarts learning from this point. History and recordings remain, but older History will no longer contribute learning patterns.",
            "这会清除单独记录的人工纠正，并从此刻重新开始学习。历史和录音仍会保留，但更早的历史不再贡献学习模式。",
            "這會清除單獨記錄的人工修正，並從此刻重新開始學習。歷史與錄音仍會保留，但更早的歷史不再貢獻學習模式。",
            "個別に保存された手動修正を消去し、この時点から学習をやり直します。履歴と録音は残りますが、以前の履歴は学習パターンへ反映されなくなります。"
        )
    }

    func correctionDataDetail() -> String {
        localized(
            "Shuo learns word-level patterns by comparing each initial output with your manual correction; it uses the raw transcription only when no initial output exists. The learning history stays on this Mac.",
            "Shuo 会比较每次初始输出与人工纠正，从中学习词元级模式；只有没有初始输出时才使用原始转写。学习记录保留在这台 Mac 上。",
            "Shuo 會比較每次初始輸出與人工修正，從中學習詞元級模式；只有沒有初始輸出時才使用原始轉寫。學習記錄保留在這台 Mac 上。",
            "Shuoは初期出力と手動修正を比較して語句単位のパターンを学習し、初期出力がない場合だけ元の文字起こしを使います。学習履歴はこのMacに保存されます。"
        )
    }

    func correctionCapturedLabel() -> String {
        localized("Edit saved locally", "修改已保存在本机", "修改已儲存在本機", "修正をこのMacに保存しました")
    }

    func enableProjectVocabularyLabel() -> String {
        localized("Use project vocabulary", "使用项目词汇", "使用專案詞彙", "プロジェクト語彙を使用")
    }

    func projectVocabularyOptInDetail() -> String {
        localized(
            "Off by default. When enabled, Shuo can build spelling hints from folders you explicitly link.",
            "默认关闭。开启后，Shuo 可以从你主动关联的文件夹中建立拼写提示。",
            "預設關閉。開啟後，Shuo 可以從你主動連結的資料夾中建立拼寫提示。",
            "初期設定ではオフです。有効にすると、明示的にリンクしたフォルダから表記ヒントを作成できます。"
        )
    }

    func linkProjectFolderLabel() -> String {
        localized("Link Project Folder…", "关联项目文件夹…", "連結專案資料夾…", "プロジェクトフォルダをリンク…")
    }

    func noLinkedProjectsLabel() -> String {
        localized("No project folders linked.", "尚未关联项目文件夹。", "尚未連結專案資料夾。", "リンク済みフォルダはありません。")
    }

    func refreshVocabularyLabel() -> String {
        localized("Refresh Index", "刷新索引", "重新整理索引", "索引を更新")
    }

    func removeProjectLabel() -> String {
        localized("Unlink Project", "解除项目关联", "解除專案連結", "プロジェクトのリンクを解除")
    }

    func unlinkProjectConfirmationTitle(_ projectName: String) -> String {
        localized(
            "Unlink \"\(projectName)\"?",
            "解除“\(projectName)”的关联？",
            "解除「\(projectName)」的連結？",
            "「\(projectName)」のリンクを解除しますか？"
        )
    }

    func unlinkProjectConfirmationDetail() -> String {
        localized(
            "Shuo will forget this link and its local vocabulary index. The project folder and every file on disk will remain unchanged.",
            "Shuo 会移除这项关联及本地词汇索引；项目文件夹和磁盘上的所有文件都不会被删除或修改。",
            "Shuo 會移除這項連結與本機詞彙索引；專案資料夾和磁碟上的所有檔案都不會被刪除或修改。",
            "Shuoはこのリンクとローカル語彙索引を削除します。プロジェクトフォルダとディスク上のファイルは削除も変更もされません。"
        )
    }

    func indexingProjectLabel() -> String {
        localized("Indexing…", "正在索引…", "正在建立索引…", "索引中…")
    }

    func noProjectTermsLabel() -> String {
        localized("No project terms found.", "未找到项目词汇。", "找不到專案詞彙。", "プロジェクト用語が見つかりません。")
    }

    func projectNotIndexedLabel() -> String {
        localized("Not indexed yet", "尚未索引", "尚未建立索引", "未索引")
    }

    func projectTermCountLabel(_ count: Int, date: String) -> String {
        localized(
            "\(count) collected · Updated \(date)",
            "已收录 \(count) 个 · 更新于 \(date)",
            "已收錄 \(count) 個 · 更新於 \(date)",
            "\(count)件収録 · \(date)更新"
        )
    }

    func projectTermSourceLabel(_ sources: [ProjectVocabularyTermSource]) -> String {
        let source = sources.first
        switch source {
        case .projectName:
            return localized("project", "项目名", "專案名稱", "プロジェクト")
        case .manifest:
            return localized("manifest", "清单", "資訊清單", "マニフェスト")
        case .path:
            return localized("path", "路径", "路徑", "パス")
        case .symbol:
            return localized("symbol", "代码符号", "程式碼符號", "シンボル")
        case .documentation:
            return localized("docs", "文档", "文件", "ドキュメント")
        case nil:
            return ""
        }
    }

    func preferredTermsCount(_ count: Int) -> String {
        localized(
            "\(count) saved",
            "已记住 \(count) 个",
            "已記住 \(count) 個",
            "\(count)件"
        )
    }

    func preferredTermsOnePerLineHint() -> String {
        localized("One term per line", "每行一个词", "每行一個詞", "1行に1語")
    }

    func onboardingSubtitle() -> String {
        localized(
            "Set up dictation in one screen.",
            "在一屏内完成听写设置。",
            "在一個畫面內完成聽寫設定。",
            "1画面で音声入力を設定します。"
        )
    }

    func onboardingShortcutTitle() -> String {
        localized("Shortcut", "快捷键", "快速鍵", "ショートカット")
    }

    func onboardingShortcutDetail() -> String {
        localized(
            "Shuo listens only while you hold the shortcut.",
            "只有按住快捷键时，Shuo 才会听取语音。",
            "只有按住快速鍵時，Shuo 才會聽取語音。",
            "ショートカットを押している間だけShuoが音声を聞き取ります。"
        )
    }

    func onboardingPermissionsTitle() -> String {
        localized("Permissions", "权限", "權限", "アクセス権")
    }

    func onboardingMicrophoneLabel() -> String {
        localized("Microphone", "麦克风", "麥克風", "マイク")
    }

    func onboardingAccessibilityLabel() -> String {
        localized("Accessibility", "辅助功能", "輔助使用", "アクセシビリティ")
    }

    func onboardingAllowLabel() -> String {
        localized("Allow", "授权", "允許", "許可")
    }

    func onboardingProviderTitle() -> String {
        localized("Transcription", "转写方式", "轉寫方式", "文字起こし")
    }

    func openAICompatibleProviderLabel() -> String {
        localized(
            "Cloud (OpenAI)",
            "云端（OpenAI）",
            "雲端（OpenAI）",
            "クラウド（OpenAI）"
        )
    }

    func onboardingLocalTitle() -> String {
        localized("Private and local", "私密且本地", "私密且本機", "プライベートなローカル処理")
    }

    func onboardingLocalDetail() -> String {
        localized(
            "Audio and text stay on this Mac—no Shuo account or telemetry. Choose and download one model; the local engine is included.",
            "语音和文字都留在这台 Mac；无需 Shuo 账号，也不会向 Shuo 发送遥测。选择并下载一个模型即可，本地引擎已内置。",
            "音訊和文字都留在這台 Mac；無需 Shuo 帳號，也不會向 Shuo 傳送遙測。選擇並下載一個模型即可，本機引擎已內建。",
            "音声とテキストはこのMac内に留まり、Shuoアカウントやテレメトリ送信はありません。モデルを1つ選んでダウンロードするだけで、ローカルエンジンは内蔵済みです。"
        )
    }

    func correctionRemembered(observed: String, preferred: String) -> String {
        localized(
            "Remembered: \(observed) → \(preferred)",
            "已记住：\(observed) → \(preferred)",
            "已記住：\(observed) → \(preferred)",
            "記憶しました：\(observed) → \(preferred)"
        )
    }

    func floatingWindowLabel() -> String {
        localized("Floating Bar", "悬浮栏", "懸浮列", "フローティングバー")
    }

    func floatingWindowDetail() -> String {
        localized(
            "Keep a small indicator on top. After transcription, click the text to edit it, then press ⌘↩ to confirm and replace the previous insertion.",
            "常驻一个置顶的小指示条。转写后点击内容即可修改，按 ⌘↩ 确认并替换上一段输入。",
            "常駐一個置頂的小指示列。轉寫後點按內容即可修改，按 ⌘↩ 確認並取代上一段輸入。",
            "小さなインジケータを常に手前に表示します。文字起こし後に内容を編集し、⌘↩で確定すると直前の入力を置換できます。"
        )
    }

    func floatingWindowIdleHint() -> String {
        localized("Shuo Floating Bar is ready", "Shuo 悬浮栏已待命", "Shuo 懸浮列已待命", "Shuoフローティングバーは待機中です")
    }

    func floatingWindowExpandHint() -> String {
        localized("Show latest transcript", "显示上一条转写", "顯示上一條轉寫", "直前の文字起こしを表示")
    }

    func floatingWindowTranscriptHint() -> String {
        localized("Click the transcript to edit", "点击转写内容直接修改", "點按轉寫內容直接修改", "文字起こしをクリックして編集")
    }

    func floatingWindowEditActionHint() -> String {
        localized("Edit transcript", "修改转写", "修改轉寫", "文字起こしを編集")
    }

    func floatingWindowConfirmActionHint() -> String {
        localized("Confirm and replace", "确认并替换", "確認並取代", "確定して置換")
    }

    func hideFloatingWindowLabel() -> String {
        localized(
            "Hide Floating Bar",
            "隐藏悬浮栏",
            "隱藏懸浮列",
            "フローティングバーを非表示"
        )
    }

    func quitShuoLabel() -> String {
        quitAppLabel(appName: AppBuildIdentity.displayName)
    }

    func quitAppLabel(appName: String) -> String {
        localized(
            "Quit \(appName)",
            "退出 \(appName)",
            "結束 \(appName)",
            "\(appName)を終了"
        )
    }

    func aboutAppLabel(appName: String = AppBuildIdentity.displayName) -> String {
        localized(
            "About \(appName)",
            "关于 \(appName)",
            "關於 \(appName)",
            "\(appName)について"
        )
    }

    func collapseLabel() -> String {
        localized("Collapse", "收起", "收起", "閉じる")
    }

    func cancelLabel() -> String {
        localized("Cancel", "取消", "取消", "キャンセル")
    }

    func historyDeletionConfirmationTitle(count: Int) -> String {
        if count > 1 {
            return localized(
                "Delete \(count) transcripts?",
                "删除 \(count) 条记录？",
                "刪除 \(count) 筆記錄？",
                "\(count)件の履歴を削除しますか？"
            )
        }
        return localized(
            "Delete this transcript?",
            "删除这条记录？",
            "刪除這筆記錄？",
            "この履歴を削除しますか？"
        )
    }

    func historyDeletionConfirmationDetail() -> String {
        localized(
            "The selected entries will be removed from History and their saved recordings deleted. This cannot be undone. Previously preserved damaged-file recovery copies, if any, are not changed.",
            "所选记录会从 History 中移除，关联录音也会删除；此操作无法撤销。此前保留的损坏文件恢复副本（如果存在）不会被修改。",
            "所選記錄會從 History 中移除，關聯錄音也會刪除；此操作無法復原。先前保留的損壞檔案復原副本（如有）不會被修改。",
            "選択した履歴と関連録音を削除します。この操作は取り消せません。以前に保全された破損ファイルの復旧コピーがある場合、それらは変更されません。"
        )
    }

    func confirmLabel() -> String {
        localized("Confirm", "确认", "確認", "確定")
    }

    func recordingsFolderLabel() -> String {
        localized("Recordings folder", "录音文件夹", "錄音資料夾", "録音フォルダ")
    }

    func openRecordingsFolderLabel() -> String {
        localized("Open Recordings", "浏览录音", "瀏覽錄音", "録音を開く")
    }

    func onboardingCloudDetail() -> String {
        localized(
            "Use OpenAI cloud transcription when accuracy and technical terms matter most. The API key is stored in Keychain.",
            "在更看重准确率和技术词识别时使用 OpenAI 云端转写。API 密钥保存在钥匙串。",
            "在更重視準確率和技術詞辨識時使用 OpenAI 雲端轉寫。API 金鑰儲存在鑰匙圈。",
            "精度や技術用語を重視する場合はOpenAIのクラウド文字起こしを使用します。APIキーはキーチェーンに保存されます。"
        )
    }

    func onboardingLocalModelLabel() -> String {
        localized("Local model", "本地模型", "本機模型", "ローカルモデル")
    }

    func onboardingRecommendedLabel() -> String {
        localized("Recommended", "推荐", "建議", "推奨")
    }

    func onboardingLocalModelRequiredHint() -> String {
        localized(
            "Choose and download a local model to continue.",
            "请选择并下载一个本地模型后继续。",
            "請選擇並下載一個本機模型後繼續。",
            "続行するにはローカルモデルを選んでダウンロードしてください。"
        )
    }

    func onboardingAPIKeyRequiredHint() -> String {
        localized(
            "Enter the API key above to continue.",
            "请填写上方的 API key 后继续。",
            "請填寫上方的 API key 後繼續。",
            "続行するには上のAPIキーを入力してください。"
        )
    }

    func onboardingPermissionsRequiredHint() -> String {
        localized(
            "Allow the two permissions on the left so the shortcut can record and insert text.",
            "请授权左侧两项权限，快捷键才能录音并写入文字。",
            "請授權左側兩項權限，快速鍵才能錄音並寫入文字。",
            "ショートカットで録音して文字を入力できるよう、左側の2つのアクセス権を許可してください。"
        )
    }

    func onboardingReadyLabel() -> String {
        localized(
            "Ready to transcribe.",
            "已经可以开始转写。",
            "已經可以開始轉寫。",
            "文字起こしを開始できます。"
        )
    }

    func onboardingCloudCredentialPendingVerificationLabel() -> String {
        localized(
            "Setup is complete. This API key has not been verified yet; Shuo will check it with the provider on your first transcription.",
            "设置已完成。这个 API key 尚未验证；首次转写时，Shuo 会向服务商验证它。",
            "設定已完成。這個 API key 尚未驗證；首次轉寫時，Shuo 會向服務商驗證它。",
            "設定は完了しました。このAPIキーはまだ検証されておらず、最初の文字起こし時にプロバイダへ確認します。"
        )
    }

    func onboardingSetUpLaterLabel() -> String {
        localized("Set up later", "稍后设置", "稍後設定", "あとで設定")
    }

    func onboardingLanguageLabel() -> String {
        localized(
            "Default transcription languages",
            "默认转写语言",
            "預設轉寫語言",
            "既定の文字起こし言語"
        )
    }

    func onboardingPreferredTermsHint() -> String {
        localized(
            "After setup, add preferred terms such as API names, frameworks, product names, and people.",
            "完成后可以添加常用词，例如 API、框架、产品名和人名。",
            "完成後可以加入常用詞，例如 API、框架、產品名和人名。",
            "設定後、API名、フレームワーク、製品名、人名などの優先用語を追加できます。"
        )
    }

    func onboardingRecordingRetentionHint() -> String {
        localized(
            "Recordings attached to History stay on this Mac until you delete their History items.",
            "随 History 保存的录音会保留在这台 Mac 上，直到你删除对应的历史记录。",
            "隨 History 儲存的錄音會保留在這台 Mac 上，直到你刪除對應的歷史記錄。",
            "履歴に紐づく録音は、その履歴項目を削除するまでこのMacに保存されます。"
        )
    }

    func onboardingContinueLabel() -> String {
        localized("Continue to Shuo", "开始使用 Shuo", "開始使用 Shuo", "Shuoを使い始める")
    }

    func aboutResourcesLabel() -> String {
        localized("Resources", "说明与资源", "說明與資源", "情報とリソース")
    }

    func sourceCodeLabel() -> String {
        localized("Source", "源码", "原始碼", "ソース")
    }

    func feedbackComposerTitle() -> String {
        localized("Send Feedback", "发送反馈", "傳送回饋", "フィードバックを送る")
    }

    func feedbackComposerPrompt() -> String {
        localized(
            "What happened, or what would make Shuo better?",
            "遇到了什么问题，或你希望 Shuo 做得更好？",
            "遇到了什麼問題，或你希望 Shuo 做得更好？",
            "起きたこと、またはShuoに改善してほしいことを書いてください。"
        )
    }

    func feedbackIncludeDiagnosticsLabel() -> String {
        localized(
            "Include redacted diagnostics",
            "附上已脱敏的诊断信息",
            "附上已去識別的診斷資訊",
            "匿名化した診断情報を含める"
        )
    }

    func feedbackComposerPrivacyHint() -> String {
        localized(
            "Your message stays in this window until you choose Send. Shuo will copy the report and open your mail app; diagnostics never include API keys, transcript text, recordings, or device identifiers.",
            "在你点击发送前，内容只保留在这个窗口中。Shuo 会复制报告并打开你的邮件 app；诊断信息不包含 API 密钥、转写文字、录音或设备标识符。",
            "在你點擊傳送前，內容只保留在這個視窗中。Shuo 會複製報告並開啟你的郵件 app；診斷資訊不包含 API 金鑰、轉寫文字、錄音或裝置識別碼。",
            "送信を選ぶまで内容はこの画面内にだけ残ります。Shuoはレポートをコピーしてメールアプリを開きます。診断情報にはAPIキー、文字起こし本文、録音、デバイス識別子は含まれません。"
        )
    }

    func feedbackSendEmailLabel() -> String {
        localized("Copy & Open Mail", "复制并打开邮件", "複製並開啟郵件", "コピーしてメールを開く")
    }

    func feedbackEmailSubject(appName: String = AppBuildIdentity.displayName) -> String {
        localized(
            "\(appName) feedback",
            "\(appName) 反馈",
            "\(appName) 回饋",
            "\(appName) フィードバック"
        )
    }

    func privacyLabel() -> String {
        localized("Privacy", "隐私", "隱私權", "プライバシー")
    }

    func releaseNotesLabel() -> String {
        localized("Release Notes", "版本说明", "版本說明", "リリースノート")
    }

    func uninstallAndDataLabel() -> String {
        localized("Uninstall & Data", "卸载与数据", "解除安裝與資料", "アンインストールとデータ")
    }

    func showWelcomeLabel() -> String {
        localized("Show Welcome", "重新显示首次引导", "重新顯示首次引導", "ようこそ画面を表示")
    }

    func closeLabel() -> String {
        localized("Close", "关闭", "關閉", "閉じる")
    }

    func clearAPIKeyLabel() -> String {
        localized("Remove API keys", "移除 API 密钥", "移除 API 金鑰", "APIキーを削除")
    }

    func privacyDetail() -> String {
        localized(
            "Shuo requires no account, sends no telemetry, behavioral analytics, or crash reports to Shuo, and contains no ads. It stores settings, transcript history, local metrics, recordings, downloaded models, project vocabulary indexes, explicit before-and-after edits, and recovery reports on this Mac; recovery reports are never uploaded automatically. Recordings linked to retained History items stay until you delete those items. Confirmed edits are recorded locally. Correction Learning is off by default; only patterns you enable individually and that meet the relevant threshold can become spelling hints or, in Replacement mode, be applied locally when high-confidence and conflict-free. OpenAI-compatible, ElevenLabs, and Alibaba Cloud API keys are stored separately in Keychain. With Local transcription selected, audio, text, corrections, and personal vocabulary do not leave the Mac; cloud text features are unavailable in Local mode. When a cloud transcription provider is selected, current-task audio, settings, enabled context, and provider-supported spelling hints are sent to that provider; correction learning sends only enabled, eligible preferred wording (B) as hints, not the original mistaken wording or complete History. Optional AI/LLM text features, when enabled with a cloud provider, may also send the current transcript and relevant prompt or context to the configured OpenAI-compatible endpoint. Alibaba Cloud transcription uses Model Studio's Beijing endpoint. Historical recordings and the correction dataset are not uploaded for training. Shuo may preserve damaged-file recovery copies locally to prevent data loss; they are never loaded or uploaded automatically, and deleting one History item does not rewrite a recovery copy that cannot be parsed safely.",
            "Shuo 不需要账号，不会向 Shuo 发送遥测、行为分析或 crash report，也没有广告。它会在这台 Mac 上保存设置、转写历史、本地统计、录音、下载的模型、项目词汇索引、明确修改的前后文本和恢复报告；恢复报告不会自动上传。与保留的 History 记录关联的录音会留在本机，直到你删除对应记录。已确认的修改会保存在本机。纠错学习默认关闭；只有用户逐条开启且达到相应门槛的模式才能成为拼写提示，或在“替换”模式下以高置信且无冲突的规则在本地应用。OpenAI-compatible、ElevenLabs 与阿里云 API 密钥分别保存在钥匙串。选择本地转写时，语音、文字、修正与个人词汇不会离开这台 Mac；本地模式下不可用云端文本功能。选择云端转写时，当前任务所需的音频、设置、启用的上下文和服务商支持的拼写提示会发送给所选服务商；纠错学习只会发送已逐条开启且符合条件的修正后写法（B），不会发送修改前写法或完整历史。另行启用可选的 AI/LLM 文本功能后，当前转写文本和相关提示或上下文还可能发送到你配置的 OpenAI-compatible 接口。阿里云转写使用百炼北京地域接口。历史录音和纠正数据集不会被上传用于训练。为防止数据丢失，Shuo 可能在本机保留损坏文件的恢复副本；它们不会被自动读取或上传，单条 History 删除也不会改写无法安全解析的旧恢复副本。",
            "Shuo 不需要帳號，不會向 Shuo 傳送遙測資料、使用行為分析資料或當機報告，也不含廣告。設定、轉寫記錄、本機統計、錄音、已下載的模型、專案詞彙索引、明確修正所產生的前後文字，以及復原報告都儲存在這台 Mac 上；復原報告絕不會自動上傳。與保留的「歷史」項目連結的錄音會保留到你刪除該項目為止。已確認的修改會儲存在本機。「人工修正學習」預設為關閉；只有你逐項啟用且達到相應門檻的修正模式，才會用作拼字提示；選擇「替換」時，只有信賴度高且沒有衝突的規則才會在本機套用。OpenAI 相容服務、ElevenLabs 和阿里雲的 API 金鑰會分別儲存在「鑰匙圈」中。選用本機轉寫時，音訊、文字、修正內容與個人詞彙都不會離開這台 Mac；本機模式下無法使用雲端 AI 文字功能。使用雲端轉寫服務時，目前任務所需的音訊、設定、已啟用的上下文，以及服務供應商支援的拼字提示會傳送給該服務；人工修正學習只會傳送已逐項啟用且符合條件的偏好寫法（B）作為提示，不會傳送修正前的錯誤寫法或完整「歷史」內容。另行啟用可選的 AI/LLM 文字功能後，目前的轉寫文字及相關提示詞或上下文還可能傳送至你設定的 OpenAI 相容端點。阿里雲轉寫使用百煉（Model Studio）的北京端點。過去的錄音與修正資料集不會上傳作為訓練用途。為避免資料遺失，Shuo 可能會在本機保留受損檔案的復原副本；這些副本不會自動載入或上傳。若復原副本無法安全解析，刪除單一「歷史」項目時也不會改寫該副本。",
            "Shuoの利用にアカウントは不要です。Shuoにテレメトリ、利用状況の分析データ、クラッシュレポートを送信せず、広告も表示しません。設定、文字起こし履歴、ローカル統計、録音、ダウンロード済みモデル、プロジェクト語彙の索引、明示的な修正前後のテキスト、復旧レポートは、このMacに保存されます。復旧レポートが自動的にアップロードされることはありません。履歴に残っている項目に紐づく録音は、その項目を削除するまで保存されます。確定した修正もローカルに保存されます。「手動修正からの学習」は初期設定でオフです。個別に有効にし、所定のしきい値を満たしたパターンだけが表記ヒントになります。「置換」方式では、信頼度が高く競合がない場合に限り、ローカルで適用されます。OpenAI互換サービス、ElevenLabs、Alibaba CloudのAPIキーは、キーチェーンに個別に保存されます。ローカル文字起こしを選択している間は、音声、テキスト、修正内容、個人用語がMacの外に送信されることはありません。ローカルモードではクラウドAIのテキスト機能は利用できません。クラウド文字起こしプロバイダを選択すると、現在のタスクの音声、設定、有効なコンテキスト、およびプロバイダが対応する表記ヒントが、そのプロバイダに送信されます。手動修正からの学習で送信されるのは、個別に有効化され、条件を満した推奨表記（B）のみです。誤認識された元の表記や履歴全体は送信されません。クラウドプロバイダでオプションのAI/LLMテキスト機能を有効にした場合は、現在の文字起こしと関連するプロンプトまたはコンテキストが、設定したOpenAI互換エンドポイントに送信されることがあります。Alibaba Cloudの文字起こしには、Model Studioの北京エンドポイントを使用します。過去の録音と修正データセットを学習目的でアップロードすることはありません。データ損失を防ぐため、破損したファイルの復旧コピーをローカルに保存する場合があります。これらが自動的に読み込まれたりアップロードされたりすることはありません。復旧コピーを安全に解析できない場合、履歴項目を1件削除してもそのコピーは書き換えません。"
        )
    }

    func releaseNotesDetail() -> String {
        let updateBullet = AppRuntime.isCommunityBuild
            ? localized(
                "• Community source builds do not use Shuo's official automatic updater",
                "• Community 源码构建不使用 Shuo 官方自动更新",
                "• Community 原始碼版本不使用 Shuo 官方自動更新",
                "• CommunityソースビルドはShuo公式の自動アップデートを使用しません"
            )
            : localized(
                "• Signed Sparkle updates with cross-user install coordination",
                "• 支持跨用户安装协调的签名 Sparkle 更新",
                "• 經簽署的 Sparkle 更新，支援跨使用者協調安裝",
                "• 署名済みのSparkleアップデートは、複数のmacOSユーザーにまたがるインストール調整に対応"
            )
        return localized(
            "Current release\n\n• Stable Local and OpenAI-compatible transcription; ElevenLabs and Alibaba Cloud adapters remain optional Beta profiles\n• Bundled local whisper.cpp runtime; Local setup requires only a model download\n• Each linked project keeps at most 60 high-priority terms in its local index; every transcription selects hints from all vocabulary sources within a shared request budget of 60 terms and 900 characters\n• Correction Learning is off by default, and each pattern must be enabled individually; choose conservative, conflict-free local Replacement or eligible preferred wording as Cloud AI hints\n• Optional Floating Bar with safe correction\n• Local recordings, raw/final text, and explicit correction capture\n• Adaptive Whisper Mode for quiet speech\n• Safe, quick Copy, Replace, Play, and Redo\n\(updateBullet)\n• Safer clipboard, transcript, and metrics recovery",
            "当前版本\n\n• 稳定支持本地与 OpenAI-compatible 转写；ElevenLabs 和阿里云适配器仍作为可选 Beta profile 提供\n• 内置本地 whisper.cpp runtime；本地设置只需下载模型\n• 每个关联项目的本地索引最多保留 60 个高优先级术语；每次转写会从所有词汇来源中选取提示，总计不超过 60 个、900 字符\n• 人工纠正学习默认关闭，每条修正模式均需单独开启；可选择保守且无冲突的本地“替换”，或把符合条件的偏好写法作为“云端 AI”提示\n• 可选悬浮栏与安全纠正\n• 本地录音、原始/最终文字与明确纠正记录\n• 面向轻声说话的自适应轻声模式\n• 快速且安全的复制、替换、回听与重转\n\(updateBullet)\n• 更安全的剪贴板、转写历史与统计恢复",
            "目前版本\n\n• 穩定支援本機與 OpenAI 相容轉寫；ElevenLabs 與阿里雲介接仍為選用的 Beta 功能\n• 內建本機 whisper.cpp 執行環境；本機設定只需下載模型\n• 每個連結專案的本機索引最多保留 60 個優先術語；每次轉寫會從所有詞彙來源中選取提示，總計不超過 60 個、900 字元\n• 人工修正學習預設關閉，每條修正模式均需個別啟用；可選擇保守且無衝突的本機「替換」，或將符合條件的偏好寫法作為「雲端 AI」提示\n• 可選用懸浮列，安全修正最新內容\n• 在本機儲存錄音、原始與最終文字，以及明確的修正記錄\n• 針對輕聲說話的自適應輕聲模式\n• 快速且安全的複製、替換、播放與重轉\n\(updateBullet)\n• 更安全地復原剪貼簿、轉寫記錄與統計資料",
            "現在のバージョン\n\n• ローカル文字起こしとOpenAI互換文字起こしを安定版として提供。ElevenLabsとAlibaba Cloudのアダプタは、引き続きオプションのベータ版プロファイルで利用可能\n• ローカル文字起こし用のwhisper.cppランタイムを同梱。セットアップ時に必要なのはモデルのダウンロードのみ\n• リンクした各プロジェクトのローカル索引には、優先度の高い用語を最大60件保存。文字起こしごとに、すべての語彙ソースから合計60件・900文字以内でヒントを選択\n• 「手動修正からの学習」は初期設定でオフ。各パターンを個別に有効化し、競合のない安全性重視のローカル「置換」か、条件を満たした推奨表記を「クラウドAI」へのヒントとして送る方法を選択\n• 必要に応じて表示でき、最新の内容を安全に修正できるフローティングバー\n• 録音、元のテキスト、最終テキスト、明示的な修正をローカルに記録\n• 小さな声に対応する適応型のささやきモード\n• コピー、置換、再生、再文字起こしをすばやく安全に実行\n\(updateBullet)\n• クリップボード、文字起こし履歴、統計データをより安全に復旧"
        )
    }

    func uninstallAndDataDetail() -> String {
        let appBundleName = "\(AppBuildIdentity.displayName).app"
        let preferenceDomain = AppBuildIdentity.bundleIdentifier
        return localized(
            "Removing \(appBundleName) alone preserves transcripts, metrics, recordings, downloaded models, settings, and API keys for a later reinstall. Before a complete removal, keep Shuo open long enough to turn off Launch at Login in Settings > Application, back up anything you need, and use the button below to remove all Shuo API keys from Keychain. Then quit Shuo and move \(appBundleName) from Applications to the Trash. Delete the Application Support folder shown below, then remove the preference domain with `defaults delete \(preferenceDomain)`. Delete any model folder you selected outside Application Support separately. Revoke Microphone and Accessibility in System Settings; macOS may still remember that those permissions were previously requested.",
            "只删除 \(appBundleName) 会保留转写、统计、录音、已下载模型、设置和 API 密钥，方便以后重装。若要彻底移除，请先保持 Shuo 打开：在“设置 > 应用”关闭“登录时启动”，备份需要的内容，并用下方按钮移除钥匙串中的所有 Shuo API 密钥。然后退出 Shuo，把“应用程序”中的 \(appBundleName) 移到废纸篓；删除下方显示的 Application Support 文件夹，再运行 `defaults delete \(preferenceDomain)` 清除偏好设置。如果曾选择 Application Support 以外的模型文件夹，也需要另行删除。最后在系统设置中撤销麦克风和辅助功能权限；macOS 仍可能记得这些权限曾经被请求过。",
            "只刪除 \(appBundleName) 會保留轉寫、統計、錄音、已下載模型、設定和 API 金鑰，方便日後重新安裝。若要完整移除，請先讓 Shuo 保持開啟：在「設定 > 應用程式」關閉「登入時啟動」、備份需要的內容，並使用下方按鈕移除鑰匙圈內所有 Shuo API 金鑰。接著結束 Shuo，把「應用程式」中的 \(appBundleName) 移到垃圾桶；刪除下方顯示的 Application Support 資料夾，再執行 `defaults delete \(preferenceDomain)` 清除偏好設定。若曾選擇 Application Support 以外的模型資料夾，也需另行刪除。最後在系統設定中撤銷麥克風與輔助使用權限；macOS 仍可能記得這些權限曾經被要求過。",
            "\(appBundleName)だけを削除した場合、後で再インストールできるように、履歴、メトリクス、録音、ダウンロード済みモデル、設定、APIキーは保持されます。完全に削除する場合は、まずShuoを開いたまま「設定 > App」でログイン時の起動をオフにし、必要なデータをバックアップしてから、下のボタンでShuoのAPIキーをすべてキーチェーンから削除してください。その後Shuoを終了し、アプリケーションフォルダの\(appBundleName)をゴミ箱へ移動します。下記のApplication Supportフォルダを削除し、`defaults delete \(preferenceDomain)`を実行して環境設定を消去してください。Application Support以外のモデルフォルダを選択していた場合は、それも別途削除します。最後にシステム設定でマイクとアクセシビリティの権限を取り消してください。macOSには、これらの権限が以前要求されたことが記録されたままになる場合があります。"
        )
    }

    func recordingCueSoundName(_ sound: RecordingCueSound) -> String {
        switch sound {
        case .softPing:
            return localized("Soft Ping", "轻响", "輕響", "ソフトピン")
        case .doubleTap:
            return localized("Double Tap", "双击", "雙擊", "ダブルタップ")
        case .brightChime:
            return localized("Bright Chime", "清铃", "清鈴", "明るいチャイム")
        case .lowPop:
            return localized("Low Pop", "低响", "低響", "低いポップ")
        case .deepDrop:
            return localized("Deep Drop", "沉降", "沉降", "ディープドロップ")
        case .woodKnock:
            return localized("Wood Knock", "木音", "木音", "ウッドノック")
        case .softPulse:
            return localized("Soft Pulse", "脉冲", "脈衝", "ソフトパルス")
        case .lowOrbit:
            return localized("Low Orbit", "轨道", "軌道", "ローオービット")
        case .subBeacon:
            return localized("Sub Beacon", "信标", "信標", "サブビーコン")
        case .darkPulse:
            return localized("Dark Pulse", "暗脉", "暗脈", "ダークパルス")
        }
    }

    func pushToTalkDisabled(shortcut: PushToTalkShortcut) -> String {
        let shortcutName = shortcutName(shortcut)
        return localized(
            "\(shortcutName) push-to-talk is disabled.",
            "\(shortcutName) 按住说话已关闭。",
            "\(shortcutName) 按住說話已關閉。",
            "\(shortcutName) のプッシュトゥトークはオフです。"
        )
    }

    func holdToDictate(shortcut: PushToTalkShortcut) -> String {
        let shortcutName = shortcutName(shortcut)
        return localized(
            "Hold \(shortcutName) to dictate.",
            "按住 \(shortcutName) 开始听写。",
            "按住 \(shortcutName) 開始聽寫。",
            "\(shortcutName) を押したまま話します。"
        )
    }

    func waitingForAccessibility(shortcut: PushToTalkShortcut) -> String {
        let shortcutName = shortcutName(shortcut)
        return localized(
            "Waiting for Accessibility permission to use \(shortcutName) dictation.",
            "正在等待辅助功能权限，以使用 \(shortcutName) 听写。",
            "正在等待輔助功能權限，以使用 \(shortcutName) 聽寫。",
            "\(shortcutName) の音声入力に必要なアクセシビリティ権限を待機中です。"
        )
    }

    func shortcutMonitorCouldNotStart(shortcut: PushToTalkShortcut) -> String {
        let shortcutName = shortcutName(shortcut)
        return localized(
            "\(shortcutName) shortcut monitor could not start. Try Retry Shortcut or relaunch Shuo.",
            "\(shortcutName) 快捷键监听无法启动。请重试快捷键或重新启动 Shuo。",
            "\(shortcutName) 快捷鍵監聽無法啟動。請重試快捷鍵或重新啟動 Shuo。",
            "\(shortcutName) のショートカット監視を開始できません。ショートカットを再試行するか、Shuoを再起動してください。"
        )
    }

    func noRecordingAvailable() -> String {
        localized(
            "No recording was available to transcribe.",
            "没有可转写的录音。",
            "沒有可轉寫的錄音。",
            "文字起こしできる録音がありません。"
        )
    }

    func microphonePermissionDenied() -> String {
        localized(
            "Microphone permission was denied. Enable Shuo in System Settings > Privacy & Security > Microphone.",
            "麦克风权限已被拒绝。请在系统设置 > 隐私与安全性 > 麦克风中启用 Shuo。",
            "麥克風權限已被拒絕。請在系統設定 > 隱私權與安全性 > 麥克風中啟用 Shuo。",
            "マイク権限が拒否されました。システム設定 > プライバシーとセキュリティ > マイクでShuoを有効にしてください。"
        )
    }

    func recordingCouldNotStart() -> String {
        localized(
            "Recording could not be started.",
            "无法开始录音。",
            "無法開始錄音。",
            "録音を開始できませんでした。"
        )
    }

    func audioInputDidNotBecomeReady() -> String {
        localized(
            "The selected microphone did not begin sending audio. Reconnect it or choose another input.",
            "所选麦克风没有开始传送声音。请重新连接，或选择其他输入设备。",
            "所選麥克風沒有開始傳送聲音。請重新連接，或選擇其他輸入裝置。",
            "選択したマイクから音声が届きませんでした。再接続するか、別の入力を選択してください。"
        )
    }

    func recoveredFromUnexpectedExit(reportPath: String) -> String {
        localized(
            "Shuo recovered from an unexpected exit. A crash report was saved at:\n\(reportPath)",
            "Shuo 检测到上次异常退出。Crash report 已保存到：\n\(reportPath)",
            "Shuo 偵測到上次異常退出。Crash report 已儲存到：\n\(reportPath)",
            "Shuoは前回の異常終了を検出しました。クラッシュレポートを保存しました:\n\(reportPath)"
        )
    }

    func voiceEditCommandNeedsRecentPaste() -> String {
        localized(
            "Voice edit needs a recent Shuo paste in the same app.",
            "语音修改需要最近一次在同一个 app 里由 Shuo 粘贴的内容。",
            "語音修改需要最近一次在同一個 app 裡由 Shuo 貼上的內容。",
            "音声編集には、同じアプリ内で直近にShuoが貼り付けた内容が必要です。"
        )
    }

    func voiceEditCommandSourceNotFound(_ source: String) -> String {
        localized(
            "Could not find \"\(source)\" in the previous Shuo paste.",
            "在上一段 Shuo 粘贴内容里找不到「\(source)」。",
            "在上一段 Shuo 貼上內容裡找不到「\(source)」。",
            "前回Shuoが貼り付けた内容に「\(source)」が見つかりません。"
        )
    }

    func voiceEditCommandFormatHint() -> String {
        localized(
            "Use: edit last sentence change X to Y.",
            "请说：修改上一句 把 X 改成 Y。",
            "請說：修改上一句 把 X 改成 Y。",
            "例: edit last sentence change X to Y."
        )
    }

    func voiceEditCommandCouldNotApply() -> String {
        localized(
            "Could not apply that voice edit.",
            "无法应用这条语音修改。",
            "無法套用這條語音修改。",
            "この音声編集を適用できませんでした。"
        )
    }

    func voiceEditDeletionNotVerified() -> String {
        localized(
            "Shuo could not verify that the cursor is still after the previous paste, so nothing was deleted.",
            "Shuo 无法确认光标仍在上一段粘贴内容的末尾，因此没有删除任何文字。",
            "Shuo 無法確認游標仍在上一段貼上內容的末尾，因此沒有刪除任何文字。",
            "カーソルが前回の貼り付け直後にあることを確認できなかったため、何も削除しませんでした。"
        )
    }

    func voiceEditCorrectionCopiedForSafety() -> String {
        localized(
            "Shuo could not verify the previous paste. The corrected text was copied to the clipboard, and existing text was left unchanged.",
            "Shuo 无法确认上一段粘贴内容。修改结果已复制到剪贴板，现有文字没有被改动。",
            "Shuo 無法確認上一段貼上內容。修改結果已複製到剪貼簿，現有文字沒有被改動。",
            "前回の貼り付けを確認できなかったため、修正文をクリップボードにコピーし、既存のテキストは変更しませんでした。"
        )
    }

    func voiceEditCommandMadeNoChange() -> String {
        localized(
            "The voice edit did not change the previous Shuo paste.",
            "这条语音修改没有改变上一段 Shuo 粘贴内容。",
            "這條語音修改沒有改變上一段 Shuo 貼上內容。",
            "この音声編集では前回Shuoが貼り付けた内容は変更されませんでした。"
        )
    }

    func voiceEditLLMEmptyResponse() -> String {
        localized(
            "LLM voice edit returned an empty response.",
            "LLM 语音修改返回了空结果。",
            "LLM 語音修改回傳了空結果。",
            "LLM音声編集の結果が空でした。"
        )
    }

    func voiceEditLLMFailed(statusCode: Int, message: String) -> String {
        localized(
            "LLM voice edit failed (\(statusCode)): \(message)",
            "LLM 语音修改失败（\(statusCode)）：\(message)",
            "LLM 語音修改失敗（\(statusCode)）：\(message)",
            "LLM音声編集に失敗しました（\(statusCode)）: \(message)"
        )
    }

    func voiceEditCommandModeName(_ mode: VoiceEditCommandMode) -> String {
        switch mode {
        case .localOnly:
            return localized("Local", "本地", "本機", "ローカル")
        case .llmOnly:
            return localized("Cloud AI", "云端 AI", "雲端 AI", "クラウドAI")
        }
    }

    func voiceEditCommandModeDetail(_ mode: VoiceEditCommandMode) -> String {
        switch mode {
        case .localOnly:
            return localized(
                "Applies explicit X-to-Y edits on this Mac without calling a text model.",
                "在本机执行明确的 X 到 Y 修改，不调用文本模型。",
                "在本機執行明確的 X 到 Y 修改，不呼叫文字模型。",
                "明示的なXからYへの変更を、このMac上でテキストモデルを呼び出さずに実行します。"
            )
        case .llmOnly:
            return localized(
                "Sends the edit instruction and previous text to the selected cloud text model for more natural edits.",
                "把修改指令和上一段文字发送给所选云端文本模型，适合更自然的修改表达。",
                "把修改指令與上一段文字傳送給所選雲端文字模型，適合更自然的修改表達。",
                "編集指示と直前のテキストを選択したクラウドテキストモデルへ送り、より自然な編集に対応します。"
            )
        }
    }

    func advancedVoiceEditBetaLabel() -> String {
        localized(
            "Advanced editing · BETA",
            "高级修改 · BETA",
            "進階修改 · BETA",
            "高度な編集 · BETA"
        )
    }

    func missingOpenAIAPIKey() -> String {
        localized(
            "Add an OpenAI API key in Settings before using the OpenAI provider.",
            "使用 OpenAI 服务前，请先在设置中添加 OpenAI API 密钥。",
            "使用 OpenAI 服務前，請先在設定中加入 OpenAI API 金鑰。",
            "OpenAIプロバイダーを使う前に、設定でOpenAI APIキーを追加してください。"
        )
    }

    func historySaveFailed(_ detail: String) -> String {
        localized(
            "Transcript history could not be saved: \(detail)",
            "转写历史无法保存：\(detail)",
            "轉寫歷史無法儲存：\(detail)",
            "文字起こし履歴を保存できませんでした: \(detail)"
        )
    }

    func historyStorageUnavailableForRecording(_ detail: String? = nil) -> String {
        let suffix = detail.map { "\n\n\($0)" } ?? ""
        return localized(
            "Recording is paused because Shuo cannot safely write transcript history. Your existing files were left untouched. Resolve the storage warning and relaunch Shuo.\(suffix)",
            "Shuo 暂停了录音，因为当前无法安全写入转写历史。现有文件均未修改；请先处理存储警告，再重新启动 Shuo。\(suffix)",
            "Shuo 已暫停錄音，因為目前無法安全寫入轉寫歷史。現有檔案均未修改；請先處理儲存警告，再重新啟動 Shuo。\(suffix)",
            "文字起こし履歴へ安全に書き込めないため、録音を一時停止しました。既存ファイルは変更していません。保存警告を解決してShuoを再起動してください。\(suffix)"
        )
    }

    func historyAudioCleanupPending(_ detail: String) -> String {
        localized(
            "The History deletion was committed, but some recording cleanup remains pending. Shuo will retry on the next launch: \(detail)",
            "History 删除已提交，但仍有部分录音等待清理；Shuo 会在下次启动时重试：\(detail)",
            "History 刪除已提交，但仍有部分錄音等待清理；Shuo 會在下次啟動時重試：\(detail)",
            "履歴の削除は確定しましたが、一部の録音削除が保留中です。次回起動時に再試行します: \(detail)"
        )
    }

    func metricsSaveFailed(_ detail: String) -> String {
        localized(
            "Usage metrics could not be saved: \(detail)",
            "使用指标无法保存：\(detail)",
            "使用指標無法儲存：\(detail)",
            "使用状況メトリクスを保存できませんでした: \(detail)"
        )
    }

    func personalizationSaveFailed(_ detail: String) -> String {
        localized(
            "Personalization data could not be saved: \(detail)",
            "个性化数据无法保存：\(detail)",
            "個人化資料無法儲存：\(detail)",
            "パーソナライズデータを保存できませんでした：\(detail)"
        )
    }

    func modelBackupPolicyFailed(_ detail: String) -> String {
        localized(
            "Downloaded models could not be excluded from system backup: \(detail)",
            "无法将已下载模型排除在系统备份之外：\(detail)",
            "無法將已下載模型排除在系統備份之外：\(detail)",
            "ダウンロード済みモデルをシステムバックアップから除外できませんでした：\(detail)"
        )
    }

    func updateBlockedByOtherUserTitle() -> String {
        localized(
            "Update waiting",
            "更新正在等待",
            "更新正在等待",
            "アップデート待機中"
        )
    }

    func updateBlockedByOtherUser() -> String {
        localized(
            "Shuo is running in another macOS account. Quit it there before installing the update.",
            "另一个 macOS 账户正在运行 Shuo。请先在那里退出 Shuo，再安装更新。",
            "另一個 macOS 帳戶正在執行 Shuo。請先在該處結束 Shuo，再安裝更新。",
            "別のmacOSアカウントでShuoが実行中です。そちらで終了してからアップデートしてください。"
        )
    }

    func updateWaitingForOtherUser() -> String {
        localized(
            "Shuo will continue the update automatically after the other account quits. No user data is shared or changed.",
            "另一个账户退出 Shuo 后会自动继续更新。用户数据不会共享或更改。",
            "另一個帳戶結束 Shuo 後會自動繼續更新。使用者資料不會共享或更改。",
            "別のアカウントでShuoを終了すると、自動的にアップデートを続行します。ユーザーデータは共有も変更もされません。"
        )
    }

    func updateOtherUserExited() -> String {
        localized(
            "The other Shuo instance exited. Continuing the update…",
            "另一个 Shuo 已退出，正在继续更新…",
            "另一個 Shuo 已結束，正在繼續更新…",
            "別のShuoが終了しました。アップデートを続行しています…"
        )
    }

    func updateCoordinationFailed(_ detail: String) -> String {
        localized(
            "Shuo could not secure the machine-wide update gate: \(detail)",
            "Shuo 无法建立整机更新门禁：\(detail)",
            "Shuo 無法建立整機更新門禁：\(detail)",
            "マシン全体のアップデート制御を確保できませんでした：\(detail)"
        )
    }

    func updateAlertOK() -> String {
        localized("OK", "知道了", "知道了", "OK")
    }

    func updateCheckAlreadyInProgress() -> String {
        localized(
            "An update check is already in progress.",
            "正在检查更新。",
            "正在檢查更新。",
            "アップデートを確認中です。"
        )
    }

    func checkingForUpdates() -> String {
        localized(
            "Checking for updates…",
            "正在检查更新…",
            "正在檢查更新…",
            "アップデートを確認しています…"
        )
    }

    func updateCheckFinished() -> String {
        localized(
            "Update check finished.",
            "更新检查已完成。",
            "更新檢查已完成。",
            "アップデートの確認が完了しました。"
        )
    }

    func clipboardSnapshotUnavailable() -> String {
        localized(
            "The current clipboard contents responded too slowly. To avoid overwriting them, Shuo did not paste or replace any text. Your transcript is still saved in Shuo; try again later.",
            "当前剪贴板内容响应过慢。为避免覆盖它，Shuo 没有粘贴或替换任何文字。转写仍保留在 Shuo 中，你可以稍后重试。",
            "目前剪貼簿內容回應過慢。為避免覆蓋它，Shuo 沒有貼上或取代任何文字。轉寫仍保留在 Shuo 中，你可以稍後重試。",
            "現在のクリップボード内容の応答に時間がかかりました。上書きを避けるため、Shuoは貼り付けや置換を行っていません。文字起こしはShuoに保存されているため、後でもう一度試せます。"
        )
    }

    func replacementPartiallyModified() -> String {
        localized(
            "Replacement stopped because the target changed during the edit. Some of the previous suffix may have been removed, but Shuo did not paste the new text or overwrite your clipboard. Review the current field; the corrected transcript is still saved in Shuo.",
            "替换过程中目标发生了变化，操作已停止。上一段文字的末尾可能已被部分删除，但 Shuo 没有粘贴新文字，也没有覆盖剪贴板。请检查当前输入框；修正后的转写仍保留在 Shuo 中。",
            "取代過程中目標發生了變化，操作已停止。上一段文字的末尾可能已被部分刪除，但 Shuo 沒有貼上新文字，也沒有覆蓋剪貼簿。請檢查目前輸入框；修正後的轉寫仍保留在 Shuo 中。",
            "置換中に対象が変わったため処理を停止しました。直前の文章末尾が一部削除された可能性がありますが、新しい文章の貼り付けやクリップボードの上書きはしていません。現在の入力欄を確認してください。修正後の文字起こしはShuoに残っています。"
        )
    }

    func recordingSaveFailed(_ detail: String) -> String {
        localized(
            "The transcript was kept, but its recording could not be saved: \(detail)",
            "转写已保留，但录音无法保存：\(detail)",
            "轉寫已保留，但錄音無法儲存：\(detail)",
            "文字起こしは保持されましたが、録音を保存できませんでした: \(detail)"
        )
    }

    func recoveredInterruptedRecording() -> String {
        localized(
            "Shuo recovered a local recording that was interrupted before transcription finished. You can play it or transcribe it again from History.",
            "Shuo 恢复了一段在转写完成前被中断的本地录音。你可以在 History 中回听或重新转写。",
            "Shuo 恢復了一段在轉寫完成前被中斷的本機錄音。你可以在 History 中回聽或重新轉寫。",
            "文字起こしが完了する前に中断されたローカル録音をShuoが復元しました。履歴から再生または再文字起こしできます。"
        )
    }

    func maximumRecordingDurationReached(minutes: Int) -> String {
        localized(
            "Recording reached the \(minutes)-minute limit. Shuo stopped automatically and started transcription.",
            "录音已达到 \(minutes) 分钟上限。Shuo 已自动停止录音并开始转写。",
            "錄音已達到 \(minutes) 分鐘上限。Shuo 已自動停止錄音並開始轉寫。",
            "録音が\(minutes)分の上限に達したため、Shuoが自動的に停止して文字起こしを開始しました。"
        )
    }

    func transcriptionAttemptOutcomeName(_ outcome: TranscriptionAttemptOutcome) -> String {
        switch outcome {
        case .processing:
            return localized("Processing", "处理中", "處理中", "処理中")
        case .succeeded:
            return localized("Succeeded", "成功", "成功", "成功")
        case .failed:
            return localized("Failed", "失败", "失敗", "失敗")
        case .ignoredSilence:
            return localized("Ignored silence", "已忽略静音", "已忽略靜音", "無音を無視")
        case .ignoredEmptyTranscript:
            return localized("Ignored empty transcript", "已忽略空转写", "已忽略空轉寫", "空の文字起こしを無視")
        case .handledVoiceCommand:
            return localized("Handled voice command", "已处理语音命令", "已處理語音命令", "音声コマンドを処理")
        case .cancelled:
            return localized("Cancelled", "已取消", "已取消", "キャンセル済み")
        }
    }

    func cancelTranscriptionLabel() -> String {
        localized("Cancel", "取消", "取消", "キャンセル")
    }

    func transcriptionCancelled() -> String {
        localized("Transcription cancelled", "转写已取消", "轉寫已取消", "文字起こしをキャンセルしました")
    }

    func aiPostProcessingFellBack(_ detail: String) -> String {
        localized(
            "The transcript was kept, but AI post-processing fell back to local processing: \(detail)",
            "转写已保留，但 AI 后处理失败并回退到本地处理：\(detail)",
            "轉寫已保留，但 AI 後處理失敗並回退到本機處理：\(detail)",
            "文字起こしは保持されましたが、AI後処理に失敗したためローカル処理に戻しました: \(detail)"
        )
    }

    func rawTranscriptLabel() -> String {
        localized("Raw transcript", "原始转写", "原始轉寫", "元の文字起こし")
    }

    func finalTranscriptLabel() -> String {
        localized("Final output", "最终输出", "最終輸出", "最終出力")
    }

    func initialOutputLabel() -> String {
        localized("Initial output", "初始输出", "初始輸出", "初回出力")
    }

    func correctedOutputLabel() -> String {
        localized("Corrected output", "修正结果", "修正結果", "修正後")
    }

    func historyRemovedTextAccessibility(_ text: String) -> String {
        localized(
            "Removed text: \(text)",
            "已删除文字：\(text)",
            "已刪除文字：\(text)",
            "削除された文字: \(text)"
        )
    }

    func historyAddedTextAccessibility(_ text: String) -> String {
        localized(
            "Added text: \(text)",
            "已添加文字：\(text)",
            "已新增文字：\(text)",
            "追加された文字: \(text)"
        )
    }

    func historyRemovedPunctuationAccessibility(_ text: String) -> String {
        localized(
            "Removed punctuation: \(text)",
            "已删除标点：\(text)",
            "已刪除標點：\(text)",
            "削除された句読点: \(text)"
        )
    }

    func historyAddedPunctuationAccessibility(_ text: String) -> String {
        localized(
            "Added punctuation: \(text)",
            "已添加标点：\(text)",
            "已新增標點：\(text)",
            "追加された句読点: \(text)"
        )
    }

    func totalAttemptsLabel() -> String {
        localized("Total attempts", "总尝试次数", "總嘗試次數", "合計試行回数")
    }

    func successfulTranscriptionsLabel() -> String {
        localized("Successful", "成功转写", "成功轉寫", "成功")
    }

    func failedTranscriptionsLabel() -> String {
        localized("Failed", "失败转写", "失敗轉寫", "失敗")
    }

    func correctedTranscriptionsLabel() -> String {
        localized("Corrected", "纠正转写", "修正轉寫", "修正済み")
    }

    func averageLatencyLabel() -> String {
        localized("Average latency", "平均延迟", "平均延遲", "平均待ち時間")
    }

    func directUpdateSecurityHint() -> String {
        localized(
            "Direct-download updates are verified with Sparkle EdDSA and Apple code-signing signatures.",
            "直装版更新会同时验证 Sparkle EdDSA 和 Apple 代码签名。",
            "直裝版更新會同時驗證 Sparkle EdDSA 和 Apple 程式碼簽章。",
            "直接配布版の更新はSparkle EdDSAとAppleコード署名の両方で検証されます。"
        )
    }

    func appStoreUpdateHint() -> String {
        localized(
            "Updates for this build are delivered by the Mac App Store.",
            "此版本由 Mac App Store 提供更新。",
            "此版本由 Mac App Store 提供更新。",
            "このビルドのアップデートはMac App Storeから配信されます。"
        )
    }

    func invalidOpenAIBaseURL(_ baseURL: String) -> String {
        let components = URLComponents(
            string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let host = components?.host?.lowercased()
        let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
        if components?.scheme?.lowercased() == "http",
           let host,
           !loopbackHosts.contains(host) {
            return localized(
                "Remote OpenAI-compatible endpoints must use HTTPS. HTTP is allowed only for localhost, 127.0.0.1, or ::1.",
                "远程 OpenAI-compatible 接口必须使用 HTTPS；HTTP 仅允许 localhost、127.0.0.1 或 ::1。",
                "遠端 OpenAI-compatible 介面必須使用 HTTPS；HTTP 僅允許 localhost、127.0.0.1 或 ::1。",
                "リモートのOpenAI互換エンドポイントにはHTTPSが必要です。HTTPはlocalhost、127.0.0.1、::1でのみ使用できます。"
            )
        }

        return localized(
            "Enter a valid HTTPS endpoint. HTTP is allowed only for localhost, 127.0.0.1, or ::1.",
            "请输入有效的 HTTPS 接口；HTTP 仅允许 localhost、127.0.0.1 或 ::1。",
            "請輸入有效的 HTTPS 介面；HTTP 僅允許 localhost、127.0.0.1 或 ::1。",
            "有効なHTTPSエンドポイントを入力してください。HTTPはlocalhost、127.0.0.1、::1でのみ使用できます。"
        )
    }

    func openAIRequestFailed(statusCode: Int, message: String) -> String {
        localized(
            "OpenAI transcription failed (\(statusCode)): \(message)",
            "OpenAI 转写失败（\(statusCode)）：\(message)",
            "OpenAI 轉寫失敗（\(statusCode)）：\(message)",
            "OpenAIの文字起こしに失敗しました（\(statusCode)）: \(message)"
        )
    }

    func missingLocalWhisperExecutable() -> String {
        localized(
            "Local whisper executable is not configured. Install whisper.cpp or choose the whisper-cli path in Model Management.",
            "本地 whisper 可执行文件还没有配置。请先安装 whisper.cpp，或在模型管理里选择 whisper-cli 路径。",
            "本機 whisper 執行檔尚未設定。請先安裝 whisper.cpp，或在模型管理裡選擇 whisper-cli 路徑。",
            "ローカル whisper 実行ファイルが設定されていません。whisper.cpp をインストールするか、モデル管理で whisper-cli のパスを選択してください。"
        )
    }

    func localWhisperExecutableNotFound(_ path: String) -> String {
        localized(
            "Local whisper executable was not found or is not executable: \(path)",
            "找不到本地 whisper 可执行文件，或者这个文件不可执行：\(path)",
            "找不到本機 whisper 執行檔，或此檔案無法執行：\(path)",
            "ローカル whisper 実行ファイルが見つからないか、実行できません: \(path)"
        )
    }

    func missingLocalWhisperModel() -> String {
        localized(
            "Local whisper model is not configured. Choose a ggml .bin model in Model Management.",
            "本地 whisper 模型还没有配置。请在模型管理里选择一个 ggml .bin 模型。",
            "本機 whisper 模型尚未設定。請在模型管理裡選擇一個 ggml .bin 模型。",
            "ローカル whisper モデルが設定されていません。モデル管理で ggml .bin モデルを選択してください。"
        )
    }

    func localWhisperModelNotFound(_ path: String) -> String {
        localized(
            "Local whisper model was not found: \(path)",
            "找不到本地 whisper 模型：\(path)",
            "找不到本機 whisper 模型：\(path)",
            "ローカル whisper モデルが見つかりません: \(path)"
        )
    }

    func localWhisperFailed(statusCode: Int32, output: String) -> String {
        localized(
            "Local whisper failed (\(statusCode)): \(output)",
            "本地 whisper 运行失败（\(statusCode)）：\(output)",
            "本機 whisper 執行失敗（\(statusCode)）：\(output)",
            "ローカル whisper が失敗しました（\(statusCode)）: \(output)"
        )
    }

    func localizedStubTranscript() -> String {
        localized(
            "Shuo recorded audio successfully. Connect a real transcription provider to replace this placeholder.",
            "Shuo 已成功录音。连接真实转写服务后会替换这段占位文字。",
            "Shuo 已成功錄音。連接真實轉寫服務後會取代這段佔位文字。",
            "Shuoは録音に成功しました。実際の文字起こしプロバイダーを接続すると、このプレースホルダーは置き換えられます。"
        )
    }

    func metricsLanguageName(_ language: MetricsLanguage) -> String {
        switch language {
        case .chinese:
            return localized("Chinese", "中文", "中文", "中国語")
        case .english:
            return localized("English", "英文", "英文", "英語")
        case .spanish:
            return localized("Spanish", "西班牙语", "西班牙文", "スペイン語")
        case .french:
            return localized("French", "法语", "法文", "フランス語")
        case .japanese:
            return localized("Japanese", "日文", "日文", "日本語")
        case .other:
            return localized("Other / symbols", "其他 / 符号", "其他 / 符號", "その他 / 記号")
        }
    }

    func promptContextDisplayTitle(_ title: String) -> String {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "General":
            return localized("General", "通用", "通用", "一般")
        case "Developer vocabulary":
            return localized("Developer vocabulary", "开发者词汇", "開發者詞彙", "開発者語彙")
        case "Lowercase English":
            return localized("Lowercase English", "英文转小写", "英文轉小寫", "英字を小文字にする")
        case "Imported context":
            return localized("Imported context", "导入的上下文", "匯入的上下文", "インポートしたコンテキスト")
        default:
            return title
        }
    }

    func promptContextStoredTitle(displayTitle: String, currentTitle: String) -> String {
        let currentDisplayTitle = promptContextDisplayTitle(currentTitle)
        guard displayTitle == currentDisplayTitle else {
            return displayTitle
        }
        return currentTitle
    }

    func compactCopyLabel() -> String {
        localized("Copy", "复制", "複製", "コピー")
    }

    func compactReplaceLabel() -> String {
        localized("Replace", "替换", "替換", "置換")
    }

    func compactPlayLabel() -> String {
        localized("Play", "播放", "播放", "再生")
    }

    func compactStopLabel() -> String {
        localized("Stop", "停止", "停止", "停止")
    }

    func compactRetranscribeLabel() -> String {
        localized("Redo", "重转", "重轉", "再変換")
    }

    func replacePreviousInsertionHelp() -> String {
        localized(
            "Replace the most recent text inserted by Shuo",
            "替换最近一次由 Shuo 输入的文字",
            "替換最近一次由 Shuo 輸入的文字",
            "直前にShuoが入力したテキストを置換"
        )
    }

    func automaticSpeechThresholdLabel() -> String {
        localized("Auto", "自动", "自動", "自動")
    }

    func speechThresholdDetail() -> String {
        localized(
            "Lower values keep quieter speech but may admit more background noise. Whisper Mode adjusts the threshold automatically from the room noise level.",
            "数值越低越容易保留轻声，也可能收进更多环境噪音；轻声模式会根据当前底噪自动调整。",
            "數值越低越容易保留輕聲，也可能收進更多環境噪音；輕聲模式會根據目前底噪自動調整。",
            "値を低くすると小さな声を拾いやすくなりますが、環境音も入りやすくなります。Whisper Modeでは周囲のノイズに合わせて自動調整します。"
        )
    }

    private func resourceText(_ key: String, fallback: String) -> String {
        LocalizationResourceStore.shared.text(key, language: language) ?? fallback
    }

    private func localized(_ english: String, _ simplifiedChinese: String, _ traditionalChinese: String, _ japanese: String) -> String {
        switch language {
        case .english:
            return english
        case .simplifiedChinese:
            return simplifiedChinese
        case .traditionalChinese:
            return traditionalChinese
        case .japanese:
            return japanese
        }
    }
}

private extension AppLanguage {
    var localizationResourceKey: String {
        switch self {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .japanese:
            return "ja"
        }
    }
}

private final class LocalizationResourceStore: @unchecked Sendable {
    static let shared = LocalizationResourceStore()

    private let values: [String: [String: String]]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "Localization", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            self.values = [:]
            return
        }

        self.values = values
    }

    func text(_ key: String, language: AppLanguage) -> String? {
        values[language.localizationResourceKey]?[key]
            ?? values[AppLanguage.english.localizationResourceKey]?[key]
    }
}
