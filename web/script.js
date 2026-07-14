document.documentElement.classList.add("js");
document.documentElement.dataset.visualStyle = "thin";

const LANGUAGE_STORAGE_KEY = "shuo-site-language";
const THEME_STORAGE_KEY = "shuo-site-theme";
const themePreferences = ["auto", "light", "dark"];
const colorSchemeQuery = window.matchMedia("(prefers-color-scheme: dark)");

const interfaceCopy = {
  en: {
    languageControl: "Language. Current: {language}",
    languageNames: {
      en: "English",
      "zh-Hans": "Simplified Chinese",
      "zh-Hant": "Traditional Chinese",
      ja: "Japanese"
    },
    legacyLanguageToggle: "Switch language. Current: {language}",
    themeControl: "Theme: {theme}. Next: {nextTheme}",
    themeNames: { auto: "Automatic", light: "Light", dark: "Dark" }
  },
  "zh-Hans": {
    languageControl: "语言。当前：{language}",
    languageNames: {
      en: "English",
      "zh-Hans": "简体中文",
      "zh-Hant": "繁体中文",
      ja: "日本語"
    },
    legacyLanguageToggle: "切换语言。当前：{language}",
    themeControl: "主题：{theme}。下一个：{nextTheme}",
    themeNames: { auto: "跟随系统", light: "浅色", dark: "深色" }
  },
  "zh-Hant": {
    languageControl: "語言。目前：{language}",
    languageNames: {
      en: "English",
      "zh-Hans": "簡體中文",
      "zh-Hant": "繁體中文",
      ja: "日本語"
    },
    legacyLanguageToggle: "切換語言。目前：{language}",
    themeControl: "主題：{theme}。下一個：{nextTheme}",
    themeNames: { auto: "跟隨系統", light: "淺色", dark: "深色" }
  },
  ja: {
    languageControl: "言語。現在：{language}",
    languageNames: {
      en: "English",
      "zh-Hans": "簡体字中国語",
      "zh-Hant": "繁体字中国語",
      ja: "日本語"
    },
    legacyLanguageToggle: "言語を切り替えます。現在：{language}",
    themeControl: "テーマ：{theme}。次：{nextTheme}",
    themeNames: { auto: "システム設定", light: "ライト", dark: "ダーク" }
  }
};

const themeIcons = {
  auto: "◐",
  light: "☀︎",
  dark: "☾"
};

const homepageMetadata = {
  en: {
    title: "Shuo — Voice typing for team names, project jargon, and global work",
    description:
      "A local-first Mac voice keyboard for team names, project jargon, and global work, with an editable correction bar and local voice history."
  },
  "zh-Hans": {
    title: "Shuo 说 — 为真实工作语言而做的 Mac 语音键盘",
    description:
      "中文想法、英文术语和项目词汇可以一句话说完。Shuo 本地优先，并让你直接修改刚刚的转写。"
  },
  "zh-Hant": {
    title: "Shuo 說 — 為真實工作語言而做的 Mac 語音鍵盤",
    description:
      "中文想法、英文術語和專案詞彙可以一句話說完。Shuo 以本機為先，並讓你直接修改剛剛的轉寫。"
  },
  ja: {
    title: "Shuo 說 シュオ — 実際の仕事の言葉をそのまま話せるMac音声キーボード",
    description:
      "日本語の考え、英語の専門用語、プロジェクト固有の言葉を自然に話せます。ローカル優先で、直前の文字起こしをフローティングバーから修正できます。"
  }
};

const documentMetadata = {
  privacy: {
    en: {
      title: "Privacy — Shuo",
      description:
        "How Shuo stores audio, transcripts, corrections, and project vocabulary, and when selected cloud features send data off this Mac."
    },
    "zh-Hans": {
      title: "隐私 — Shuo 说",
      description:
        "了解 Shuo 如何在本机保存录音、转写、纠正与项目词汇，以及哪些可选云端功能会发送当前任务所需的数据。"
    },
    "zh-Hant": {
      title: "隱私 — Shuo 說",
      description:
        "了解 Shuo 如何在本機保存錄音、轉寫、修正與專案詞彙，以及哪些選用的雲端功能會傳送目前任務所需的資料。"
    },
    ja: {
      title: "プライバシー — Shuo 說 シュオ",
      description:
        "音声、文字起こし、修正、プロジェクト用語をShuoがMac内にどう保存し、どのクラウド機能が処理中のデータを送信するかを説明します。"
    }
  },
  "release-notes": {
    en: {
      title: "Release Notes — Shuo 1.0.0",
      description:
        "What is included in the Shuo 1.0.0 direct download for macOS."
    },
    "zh-Hans": {
      title: "版本说明 — Shuo 说 1.0.0",
      description: "Shuo 1.0.0 macOS 直装版的功能与可靠性改进。"
    },
    "zh-Hant": {
      title: "版本說明 — Shuo 說 1.0.0",
      description: "Shuo 1.0.0 macOS 直接下載版的功能與可靠性改進。"
    },
    ja: {
      title: "リリースノート — Shuo 說 シュオ 1.0.0",
      description:
        "Shuo 1.0.0 macOS直接配布版の機能と信頼性の改善をまとめています。"
    }
  }
};

const openGraphLocales = {
  en: "en_US",
  "zh-Hans": "zh_CN",
  "zh-Hant": "zh_TW",
  ja: "ja_JP"
};

const readStoredPreference = (key) => {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
};

const writeStoredPreference = (key, value) => {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Storage can be unavailable in private or embedded contexts. The current
    // page should still honor the user's choice for the rest of this visit.
  }
};

const normalizeLanguage = (language) => {
  if (typeof language !== "string") {
    return null;
  }

  const normalized = language.trim().replaceAll("_", "-").toLowerCase();
  if (!normalized) {
    return null;
  }
  if (normalized === "en" || normalized.startsWith("en-")) {
    return "en";
  }
  if (normalized === "ja" || normalized.startsWith("ja-")) {
    return "ja";
  }
  if (normalized.startsWith("zh")) {
    const usesTraditionalScript = ["hant", "tw", "hk", "mo"].some((part) =>
      normalized.split("-").includes(part)
    );
    return usesTraditionalScript ? "zh-Hant" : "zh-Hans";
  }
  return null;
};

const detectBrowserLanguage = () => {
  const candidates = navigator.languages?.length
    ? navigator.languages
    : [navigator.language || "en"];

  for (const candidate of candidates) {
    const supportedLanguage = normalizeLanguage(candidate);
    if (supportedLanguage) {
      return supportedLanguage;
    }
  }
  return "en";
};

const normalizeThemePreference = (theme) =>
  themePreferences.includes(theme) ? theme : null;

const resolvedTheme = (preference) =>
  preference === "auto" ? (colorSchemeQuery.matches ? "dark" : "light") : preference;

const formatInterfaceCopy = (template, replacements) =>
  Object.entries(replacements).reduce(
    (output, [key, value]) => output.replaceAll(`{${key}}`, value),
    template
  );

let activeLanguage = "en";
let activeThemePreference = "auto";
const fixedPageLanguage = normalizeLanguage(document.documentElement.dataset.pageLanguage);
const currentPageName = document.documentElement.dataset.pageName || "home";
const localizedLanguageSlugs = {
  en: "en",
  "zh-Hans": "zh-hans",
  "zh-Hant": "zh-hant",
  ja: "ja"
};

const navigateToLocalizedPage = (language) => {
  const normalized = normalizeLanguage(language) || "en";
  writeStoredPreference(LANGUAGE_STORAGE_KEY, normalized);
  const filename = currentPageName === "home" ? "" : `${currentPageName}.html`;
  const target = new URL(`../${localizedLanguageSlugs[normalized]}/${filename}`, window.location.href);
  const requestedTheme = normalizeThemePreference(
    new URLSearchParams(window.location.search).get("theme")
  );
  if (requestedTheme) {
    target.searchParams.set("theme", requestedTheme);
  }
  target.hash = window.location.hash;
  window.location.assign(target);
};

const languageAvailableOnThisPage = (language) => {
  const normalized = normalizeLanguage(language) || "en";
  const hasFourLanguageContent = Boolean(
    document.querySelector(".lang-ja") && document.querySelector(".lang-zh-hant")
  );
  if (hasFourLanguageContent) {
    return normalized;
  }
  if (normalized === "zh-Hant") {
    return "zh-Hans";
  }
  return normalized === "ja" ? "en" : normalized;
};

const updateThemeControls = () => {
  const copy = interfaceCopy[activeLanguage] || interfaceCopy.en;
  const nextPreference = resolvedTheme(activeThemePreference) === "light" ? "dark" : "light";
  const themeLabel = formatInterfaceCopy(copy.themeControl, {
    theme: copy.themeNames[activeThemePreference],
    nextTheme: copy.themeNames[nextPreference]
  });
  const currentResolvedTheme = resolvedTheme(activeThemePreference);

  document.querySelectorAll("[data-theme-toggle]").forEach((toggle) => {
    toggle.dataset.themePreference = activeThemePreference;
    toggle.dataset.resolvedTheme = currentResolvedTheme;
    toggle.setAttribute("aria-label", themeLabel);
    toggle.setAttribute("title", themeLabel);

    toggle.querySelectorAll("[data-theme-icon]").forEach((icon) => {
      icon.hidden = icon.dataset.themeIcon !== activeThemePreference;
    });

    const currentIcon =
      toggle.querySelector("[data-theme-icon-current]") ||
      toggle.querySelector('[aria-hidden="true"]:not([data-theme-icon])');
    if (currentIcon) {
      currentIcon.textContent = themeIcons[activeThemePreference];
    }
  });

  document.querySelectorAll("[data-theme-option]").forEach((option) => {
    const isSelected = option.dataset.themeOption === activeThemePreference;
    option.setAttribute("aria-pressed", String(isSelected));
  });
};

const setTheme = (preference, { persist = true, updateURL = false } = {}) => {
  const normalized = normalizeThemePreference(preference) || "auto";
  const nextResolvedTheme = resolvedTheme(normalized);
  activeThemePreference = normalized;
  document.documentElement.dataset.theme = nextResolvedTheme;
  document.documentElement.dataset.themePreference = normalized;

  const themeColor = document.querySelector('meta[name="theme-color"]');
  if (themeColor) {
    themeColor.setAttribute("content", nextResolvedTheme === "dark" ? "#080908" : "#f4f1e8");
  }

  updateThemeControls();
  if (persist) {
    writeStoredPreference(THEME_STORAGE_KEY, normalized);
  }
  if (updateURL && window.history?.replaceState) {
    const url = new URL(window.location.href);
    url.searchParams.set("theme", normalized);
    window.history.replaceState(window.history.state, "", url);
  }
};

const localizedAttributeValue = (element, prefix, language) => {
  const attributes = {
    en: `${prefix}-en`,
    "zh-Hans": `${prefix}-zh-hans`,
    "zh-Hant": `${prefix}-zh-hant`,
    ja: `${prefix}-ja`
  };
  const fallbacks = {
    en: [],
    "zh-Hans": [`${prefix}-zh`],
    "zh-Hant": [`${prefix}-zh-hans`, `${prefix}-zh`, `${prefix}-en`],
    ja: [`${prefix}-en`]
  };

  for (const attribute of [attributes[language], ...fallbacks[language]]) {
    const value = element.getAttribute(attribute);
    if (value) {
      return value;
    }
  }
  return null;
};

const updateLanguageControls = () => {
  const copy = interfaceCopy[activeLanguage] || interfaceCopy.en;
  const currentLanguageName = copy.languageNames[activeLanguage];
  const languageControlLabel = formatInterfaceCopy(copy.languageControl, {
    language: currentLanguageName
  });

  document.querySelectorAll("[data-language-option]").forEach((option) => {
    const optionLanguage = normalizeLanguage(option.dataset.languageOption);
    const isSelected = optionLanguage === activeLanguage;
    option.setAttribute("aria-pressed", String(isSelected));
    if (isSelected) {
      option.setAttribute("aria-current", "true");
    } else {
      option.removeAttribute("aria-current");
    }
  });

  document.querySelectorAll("[data-language-select]").forEach((select) => {
    if (Array.from(select.options).some((option) => option.value === activeLanguage)) {
      select.value = activeLanguage;
    }
    select.setAttribute("aria-label", languageControlLabel);
    select.setAttribute("title", languageControlLabel);
  });

  document.querySelectorAll("[data-language-toggle]").forEach((toggle) => {
    const label = formatInterfaceCopy(copy.legacyLanguageToggle, {
      language: currentLanguageName
    });
    toggle.setAttribute("aria-pressed", String(activeLanguage === "en"));
    toggle.setAttribute("aria-label", label);
    toggle.setAttribute("title", label);
  });

  document
    .querySelectorAll(
      "[data-aria-label-en], [data-aria-label-zh], [data-aria-label-zh-hans], " +
        "[data-aria-label-zh-hant], [data-aria-label-ja]"
    )
    .forEach((element) => {
      const label = localizedAttributeValue(element, "data-aria-label", activeLanguage);
      if (label) {
        element.setAttribute("aria-label", label);
      }
    });

  document
    .querySelectorAll(
      "[data-title-en], [data-title-zh], [data-title-zh-hans], " +
        "[data-title-zh-hant], [data-title-ja]"
    )
    .forEach((element) => {
      const title = localizedAttributeValue(element, "data-title", activeLanguage);
      if (title) {
        element.setAttribute("title", title);
      }
    });

  updateThemeControls();
};

const updatePageMetadata = () => {
  const metadata =
    currentPageName === "home"
      ? homepageMetadata[activeLanguage]
      : documentMetadata[currentPageName]?.[activeLanguage];
  if (!metadata) {
    return;
  }

  document.title = metadata.title;
  const metadataTargets = [
    ['meta[name="description"]', metadata.description],
    ['meta[property="og:locale"]', openGraphLocales[activeLanguage]],
    ['meta[property="og:title"]', metadata.title],
    ['meta[property="og:description"]', metadata.description],
    ['meta[name="twitter:title"]', metadata.title],
    ['meta[name="twitter:description"]', metadata.description]
  ];

  metadataTargets.forEach(([selector, content]) => {
    document.querySelector(selector)?.setAttribute("content", content);
  });
};

const setLanguage = (language, { persist = true, updateURL = false } = {}) => {
  const normalized = fixedPageLanguage || languageAvailableOnThisPage(language);
  const previousLanguage = activeLanguage;
  activeLanguage = normalized;
  document.body.dataset.language = normalized;
  document.documentElement.dataset.language = normalized;
  document.documentElement.lang = normalized;
  updateLanguageControls();
  updatePageMetadata();

  if (persist) {
    writeStoredPreference(LANGUAGE_STORAGE_KEY, normalized);
  }

  if (!fixedPageLanguage && updateURL && window.history?.replaceState) {
    const url = new URL(window.location.href);
    url.searchParams.set("lang", normalized);
    window.history.replaceState(window.history.state, "", url);
  }

  if (previousLanguage !== normalized) {
    document.dispatchEvent(
      new CustomEvent("shuo:languagechange", { detail: { language: normalized } })
    );
  }
};

const requestedLanguage = normalizeLanguage(
  new URLSearchParams(window.location.search).get("lang")
);
const requestedTheme = normalizeThemePreference(
  new URLSearchParams(window.location.search).get("theme")
);
const storedLanguage = normalizeLanguage(readStoredPreference(LANGUAGE_STORAGE_KEY));
const initialLanguage =
  fixedPageLanguage || requestedLanguage || storedLanguage || detectBrowserLanguage();
const initialTheme =
  requestedTheme || normalizeThemePreference(readStoredPreference(THEME_STORAGE_KEY)) || "auto";

setTheme(initialTheme, { persist: false });
setLanguage(initialLanguage, { persist: false });

document.querySelectorAll("[data-theme-toggle]").forEach((toggle) => {
  toggle.addEventListener("click", () => {
    const nextPreference = resolvedTheme(activeThemePreference) === "light" ? "dark" : "light";
    setTheme(nextPreference, {
      updateURL: true
    });
  });
});

document.querySelectorAll("[data-theme-option]").forEach((option) => {
  option.addEventListener("click", () =>
    setTheme(option.dataset.themeOption, { updateURL: true })
  );
});

document.querySelectorAll("[data-language-option]").forEach((option) => {
  option.addEventListener("click", () => {
    if (fixedPageLanguage) {
      navigateToLocalizedPage(option.dataset.languageOption);
      return;
    }
    setLanguage(option.dataset.languageOption, { updateURL: true });
  });
});

document.querySelectorAll("[data-language-select]").forEach((select) => {
  select.addEventListener("change", () => {
    if (fixedPageLanguage) {
      navigateToLocalizedPage(select.value);
      return;
    }
    setLanguage(select.value, { updateURL: true });
  });
});

document.querySelectorAll("[data-language-toggle]").forEach((toggle) => {
  toggle.addEventListener("click", () => {
    const nextLanguage = activeLanguage === "en" ? "zh-Hans" : "en";
    if (fixedPageLanguage) {
      navigateToLocalizedPage(nextLanguage);
      return;
    }
    setLanguage(nextLanguage, { updateURL: true });
  });
});

const handleSystemThemeChange = () => {
  if (activeThemePreference === "auto") {
    setTheme("auto", { persist: false });
  }
};

if (typeof colorSchemeQuery.addEventListener === "function") {
  colorSchemeQuery.addEventListener("change", handleSystemThemeChange);
} else if (typeof colorSchemeQuery.addListener === "function") {
  colorSchemeQuery.addListener(handleSystemThemeChange);
}

const revealItems = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.16 }
  );

  revealItems.forEach((item) => revealObserver.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

const hero = document.querySelector(".hero");

if (hero && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  hero.addEventListener("pointermove", (event) => {
    const bounds = hero.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    hero.style.setProperty("--hero-x", `${x * 18}px`);
    hero.style.setProperty("--hero-y", `${y * 14}px`);
  });

  hero.addEventListener("pointerleave", () => {
    hero.style.setProperty("--hero-x", "0px");
    hero.style.setProperty("--hero-y", "0px");
  });
}

const correctionDemo = document.querySelector("[data-correction-demo]");

if (correctionDemo) {
  const steps = ["insert", "edit", "replace"];
  const stepButtons = Array.from(correctionDemo.querySelectorAll("[data-correction-step]"));
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const animatedLine = correctionDemo.querySelector("[data-correction-animation-line]");
  const targetLine = correctionDemo.querySelector(".correction-target p");
  const originalLine = correctionDemo.querySelector(
    '.correction-line-state[data-demo-state~="insert"]'
  );
  const replacementLine = correctionDemo.querySelector(
    '.correction-line-state[data-demo-state~="replace"]'
  );
  const languageClassNames = {
    en: "lang-en",
    "zh-Hans": "lang-zh",
    "zh-Hant": "lang-zh-hant",
    ja: "lang-ja"
  };
  const cycleDelay = 3400;
  let activeIndex = 0;
  let cycleTimer;
  let textAnimationRun = 0;
  let correctionIsVisible = !("IntersectionObserver" in window);
  let pointerIsInside = false;
  let focusIsInside = false;
  let hasAnimatedInitialStep = false;

  const localizedLineText = (line) => {
    const languageClassName = languageClassNames[activeLanguage] || "lang-en";
    const localizedLine = line?.querySelector(`.${languageClassName}`) || line?.querySelector(".lang");
    return (localizedLine || line)?.textContent.trim() || "";
  };

  const splitGraphemes = (text) => {
    if (typeof Intl !== "undefined" && typeof Intl.Segmenter === "function") {
      try {
        const segmenter = new Intl.Segmenter(activeLanguage, { granularity: "grapheme" });
        return Array.from(segmenter.segment(text), ({ segment }) => segment);
      } catch {
        // Array.from still preserves Unicode code points if segmentation is unavailable.
      }
    }
    return Array.from(text);
  };

  const frameDelay = (characterCount, totalDuration, minimum, maximum) =>
    Math.max(
      minimum,
      Math.min(maximum, Math.round(totalDuration / Math.max(1, characterCount)))
    );

  const waitForAnimationFrame = (duration) =>
    new Promise((resolve) => window.setTimeout(resolve, duration));

  const cancelCorrectionTextAnimation = () => {
    textAnimationRun += 1;
    correctionDemo.classList.remove("is-text-animating");
    delete correctionDemo.dataset.textMotion;
    if (animatedLine) {
      animatedLine.textContent = "";
    }
  };

  const animateCorrectionText = async (step) => {
    const run = textAnimationRun + 1;
    textAnimationRun = run;
    correctionDemo.classList.remove("is-text-animating");
    delete correctionDemo.dataset.textMotion;

    if (animatedLine) {
      animatedLine.textContent = "";
    }

    const originalText = localizedLineText(originalLine);
    const replacementText = localizedLineText(replacementLine);
    const accessibleText = step === "replace" ? replacementText : originalText;
    if (targetLine && accessibleText) {
      targetLine.setAttribute("aria-label", accessibleText);
    }

    if (
      !animatedLine ||
      reducedMotion.matches ||
      !originalText ||
      !["insert", "replace"].includes(step)
    ) {
      return;
    }

    const originalCharacters = splitGraphemes(originalText);
    const replacementCharacters = splitGraphemes(replacementText);
    correctionDemo.classList.add("is-text-animating");

    if (step === "insert") {
      correctionDemo.dataset.textMotion = "type";
      await waitForAnimationFrame(120);
      const delay = frameDelay(originalCharacters.length, 1150, 14, 30);

      for (let end = 1; end <= originalCharacters.length; end += 1) {
        if (run !== textAnimationRun) {
          return;
        }
        animatedLine.textContent = originalCharacters.slice(0, end).join("");
        await waitForAnimationFrame(delay);
      }
    } else {
      animatedLine.textContent = originalText;
      correctionDemo.dataset.textMotion = "delete";
      await waitForAnimationFrame(240);

      let sharedPrefixLength = 0;
      while (
        sharedPrefixLength < originalCharacters.length &&
        sharedPrefixLength < replacementCharacters.length &&
        originalCharacters[sharedPrefixLength] === replacementCharacters[sharedPrefixLength]
      ) {
        sharedPrefixLength += 1;
      }

      const deleteCount = originalCharacters.length - sharedPrefixLength;
      const deleteDelay = frameDelay(deleteCount, 680, 8, 24);
      for (let end = originalCharacters.length - 1; end >= sharedPrefixLength; end -= 1) {
        if (run !== textAnimationRun) {
          return;
        }
        animatedLine.textContent = originalCharacters.slice(0, end).join("");
        await waitForAnimationFrame(deleteDelay);
      }

      if (run !== textAnimationRun) {
        return;
      }
      await waitForAnimationFrame(150);
      correctionDemo.dataset.textMotion = "type";

      const typeCount = replacementCharacters.length - sharedPrefixLength;
      const typeDelay = frameDelay(typeCount, 900, 10, 28);
      for (let end = sharedPrefixLength + 1; end <= replacementCharacters.length; end += 1) {
        if (run !== textAnimationRun) {
          return;
        }
        animatedLine.textContent = replacementCharacters.slice(0, end).join("");
        await waitForAnimationFrame(typeDelay);
      }
    }

    if (run === textAnimationRun) {
      correctionDemo.classList.remove("is-text-animating");
      delete correctionDemo.dataset.textMotion;
      animatedLine.textContent = "";
    }
  };

  const activateCorrectionStep = (step, { animate = true } = {}) => {
    const nextIndex = steps.indexOf(step);

    if (nextIndex < 0) {
      return;
    }

    activeIndex = nextIndex;
    correctionDemo.dataset.state = step;
    stepButtons.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.correctionStep === step));
    });

    if (animate) {
      void animateCorrectionText(step);
    } else {
      cancelCorrectionTextAnimation();
      const staticText = localizedLineText(step === "replace" ? replacementLine : originalLine);
      if (targetLine && staticText) {
        targetLine.setAttribute("aria-label", staticText);
      }
    }
  };

  const stopCorrectionCycle = () => {
    window.clearTimeout(cycleTimer);
    cycleTimer = undefined;
  };

  const startCorrectionCycle = () => {
    stopCorrectionCycle();

    if (
      reducedMotion.matches ||
      !correctionIsVisible ||
      pointerIsInside ||
      focusIsInside ||
      document.hidden
    ) {
      return;
    }

    cycleTimer = window.setTimeout(() => {
      activeIndex = (activeIndex + 1) % steps.length;
      activateCorrectionStep(steps[activeIndex]);
      startCorrectionCycle();
    }, cycleDelay);
  };

  stepButtons.forEach((button) => {
    button.addEventListener("click", () => {
      activateCorrectionStep(button.dataset.correctionStep);
      startCorrectionCycle();
    });
  });

  correctionDemo.addEventListener("pointerenter", () => {
    pointerIsInside = true;
    stopCorrectionCycle();
  });
  correctionDemo.addEventListener("pointerleave", () => {
    pointerIsInside = false;
    startCorrectionCycle();
  });
  correctionDemo.addEventListener("focusin", () => {
    focusIsInside = true;
    stopCorrectionCycle();
  });
  correctionDemo.addEventListener("focusout", (event) => {
    if (!correctionDemo.contains(event.relatedTarget)) {
      focusIsInside = false;
      startCorrectionCycle();
    }
  });

  const handleReducedMotionChange = () => {
    if (reducedMotion.matches) {
      stopCorrectionCycle();
      cancelCorrectionTextAnimation();
    } else {
      startCorrectionCycle();
    }
  };

  if (typeof reducedMotion.addEventListener === "function") {
    reducedMotion.addEventListener("change", handleReducedMotionChange);
  } else if (typeof reducedMotion.addListener === "function") {
    reducedMotion.addListener(handleReducedMotionChange);
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      stopCorrectionCycle();
      cancelCorrectionTextAnimation();
    } else {
      activateCorrectionStep(steps[activeIndex], { animate: false });
      startCorrectionCycle();
    }
  });

  document.addEventListener("shuo:languagechange", () => {
    activateCorrectionStep(steps[activeIndex], { animate: false });
  });

  if ("IntersectionObserver" in window) {
    const correctionObserver = new IntersectionObserver(
      ([entry]) => {
        correctionIsVisible = entry.isIntersecting;
        if (entry.isIntersecting) {
          if (!hasAnimatedInitialStep) {
            hasAnimatedInitialStep = true;
            activateCorrectionStep(steps[activeIndex]);
          }
          startCorrectionCycle();
        } else {
          stopCorrectionCycle();
          cancelCorrectionTextAnimation();
        }
      },
      { threshold: 0.25 }
    );
    correctionObserver.observe(correctionDemo);
  } else {
    hasAnimatedInitialStep = true;
    activateCorrectionStep(steps[activeIndex]);
    startCorrectionCycle();
  }
}

const architecture = document.querySelector("[data-architecture]");

if (architecture) {
  const path = architecture.querySelector(".architecture-path");
  const nodes = Array.from(architecture.querySelectorAll(".architecture-node"));
  const stageButtons = nodes.map((node) => node.querySelector("[data-architecture-stage]"));
  const detailPanels = Array.from(architecture.querySelectorAll(".architecture-detail"));
  const supportsHover = window.matchMedia("(hover: hover) and (pointer: fine)");

  const activateArchitectureStage = (button) => {
    const activeIndex = stageButtons.indexOf(button);

    if (activeIndex < 0) {
      return;
    }

    const controlledPanelID = button.getAttribute("aria-controls");
    const progress = stageButtons.length > 1 ? (activeIndex / (stageButtons.length - 1)) * 100 : 0;
    path?.style.setProperty("--architecture-progress", `${progress}%`);

    nodes.forEach((node, index) => {
      node.classList.toggle("is-active", index === activeIndex);
      node.classList.toggle("is-passed", index <= activeIndex);
    });

    stageButtons.forEach((stageButton) => {
      stageButton.setAttribute("aria-expanded", String(stageButton === button));
    });

    detailPanels.forEach((panel) => {
      panel.hidden = panel.id !== controlledPanelID;
    });
  };

  stageButtons.forEach((button, index) => {
    button.addEventListener("click", () => activateArchitectureStage(button));
    button.addEventListener("focus", () => activateArchitectureStage(button));

    button.addEventListener("pointerenter", () => {
      if (supportsHover.matches) {
        activateArchitectureStage(button);
      }
    });

    button.addEventListener("keydown", (event) => {
      let nextIndex;

      if (event.key === "ArrowRight" || event.key === "ArrowDown") {
        nextIndex = (index + 1) % stageButtons.length;
      } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
        nextIndex = (index - 1 + stageButtons.length) % stageButtons.length;
      } else if (event.key === "Home") {
        nextIndex = 0;
      } else if (event.key === "End") {
        nextIndex = stageButtons.length - 1;
      }

      if (typeof nextIndex === "number") {
        event.preventDefault();
        stageButtons[nextIndex].focus();
      }
    });
  });
}
