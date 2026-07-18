#!/usr/bin/env python3
"""Build fixed-language GitHub Pages routes from Shuo's multilingual HTML."""

from __future__ import annotations

import argparse
import html
import json
from html.parser import HTMLParser
from pathlib import Path


SITE_ORIGIN = "https://stcheng.github.io"
SITE_ROOT = "/shuo"
SITE_URL = f"{SITE_ORIGIN}{SITE_ROOT}"
IMAGE_URL = f"{SITE_URL}/assets/shuo-icon.png"
VOID_ELEMENTS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}

LANGUAGES = {
    "en": {
        "slug": "en",
        "html_class": "lang-en",
        "og_locale": "en_US",
        "name": "English",
    },
    "zh-Hans": {
        "slug": "zh-hans",
        "html_class": "lang-zh",
        "og_locale": "zh_CN",
        "name": "简体中文",
    },
    "zh-Hant": {
        "slug": "zh-hant",
        "html_class": "lang-zh-hant",
        "og_locale": "zh_TW",
        "name": "繁體中文",
    },
    "ja": {
        "slug": "ja",
        "html_class": "lang-ja",
        "og_locale": "ja_JP",
        "name": "日本語",
    },
}

PAGES = {
    "home": {
        "source": "index.html",
        "output": "index.html",
        "x_default": "/",
        "metadata": {
            "en": (
                "Shuo — Voice typing for team names, project jargon, and global work",
                "A local-first Mac voice keyboard for team names, project jargon, and global work, with an editable correction bar and local voice history.",
            ),
            "zh-Hans": (
                "Shuo 说 — 为真实工作语言而做的 Mac 语音键盘",
                "中文想法、英文术语和项目词汇可以一句话说完。Shuo 本地优先，并让你直接修改刚刚的转写。",
            ),
            "zh-Hant": (
                "Shuo 說 — 為真實工作語言而做的 Mac 語音鍵盤",
                "中文想法、英文術語和專案詞彙可以一句話說完。Shuo 以本機為先，並讓你直接修改剛剛的轉寫。",
            ),
            "ja": (
                "Shuo 說 シュオ — 実際の仕事の言葉をそのまま話せるMac音声キーボード",
                "日本語の考え、英語の専門用語、プロジェクト固有の言葉を自然に話せます。ローカル優先で、直前の文字起こしをフローティングバーから修正できます。",
            ),
        },
    },
    "privacy": {
        "source": "privacy.html",
        "output": "privacy.html",
        "x_default": "/privacy.html",
        "metadata": {
            "en": (
                "Privacy — Shuo",
                "How Shuo stores audio, transcripts, corrections, and project vocabulary, and when selected cloud features send data off this Mac.",
            ),
            "zh-Hans": (
                "隐私 — Shuo 说",
                "了解 Shuo 如何在本机保存录音、转写、纠正与项目词汇，以及哪些可选云端功能会发送当前任务所需的数据。",
            ),
            "zh-Hant": (
                "隱私 — Shuo 說",
                "了解 Shuo 如何在本機保存錄音、轉寫、修正與專案詞彙，以及哪些選用的雲端功能會傳送目前任務所需的資料。",
            ),
            "ja": (
                "プライバシー — Shuo 說 シュオ",
                "音声、文字起こし、修正、プロジェクト用語をShuoがMac内にどう保存し、どのクラウド機能が処理中のデータを送信するかを説明します。",
            ),
        },
    },
    "release-notes": {
        "source": "release-notes.html",
        "output": "release-notes.html",
        "x_default": "/release-notes.html",
        "metadata": {
            "en": (
                "Release Notes & Version History — Shuo",
                "Release notes and version history for the Shuo macOS direct download.",
            ),
            "zh-Hans": (
                "版本说明与更新历史 — Shuo 说",
                "查看 Shuo macOS 直装版的版本说明与更新历史。",
            ),
            "zh-Hant": (
                "版本說明與更新歷史 — Shuo 說",
                "查看 Shuo macOS 直接下載版的版本說明與更新歷史。",
            ),
            "ja": (
                "リリースノートと更新履歴 — Shuo 說 シュオ",
                "Shuo macOS直接配布版のリリースノートと更新履歴。",
            ),
        },
    },
}


def localized_url(language: str, page: dict[str, object]) -> str:
    slug = LANGUAGES[language]["slug"]
    output = page["output"]
    suffix = "/" if output == "index.html" else f"/{output}"
    return f"{SITE_URL}/{slug}{suffix}"


def alternate_links(page: dict[str, object]) -> str:
    links = [
        f'<link rel="alternate" hreflang="{language}" href="{localized_url(language, page)}">'
        for language in LANGUAGES
    ]
    links.append(
        f'<link rel="alternate" hreflang="x-default" href="{SITE_URL}{page["x_default"]}">'
    )
    return "\n    ".join(links)


def structured_data(page_name: str, language: str, page: dict[str, object]) -> dict[str, object]:
    title, description = page["metadata"][language]
    common = {
        "@context": "https://schema.org",
        "name": title,
        "description": description,
        "url": localized_url(language, page),
        "inLanguage": language,
    }
    if page_name == "home":
        return {
            **common,
            "@type": "SoftwareApplication",
            "name": "Shuo",
            "applicationCategory": "UtilitiesApplication",
            "operatingSystem": "macOS 14 or later",
            "downloadUrl": "https://github.com/stcheng/shuo/releases/download/v1.2.4/Shuo-1.2.4-macOS.dmg",
            "image": IMAGE_URL,
        }
    return {
        **common,
        "@type": "WebPage",
        "isPartOf": {"@type": "WebSite", "name": "Shuo", "url": f"{SITE_URL}/"},
        "dateModified": "2026-07-17",
    }


def metadata_markup(page_name: str, language: str, page: dict[str, object]) -> str:
    title, description = page["metadata"][language]
    locale = LANGUAGES[language]["og_locale"]
    other_locales = [
        details["og_locale"]
        for key, details in LANGUAGES.items()
        if key != language
    ]
    locale_alternates = "\n    ".join(
        f'<meta property="og:locale:alternate" content="{value}">' for value in other_locales
    )
    canonical = localized_url(language, page)
    schema = json.dumps(
        structured_data(page_name, language, page), ensure_ascii=False, separators=(",", ":")
    ).replace("</", "<\\/")
    return f"""    <title>{html.escape(title)}</title>
    <meta name="description" content="{html.escape(description, quote=True)}">
    <meta name="robots" content="index,follow,max-image-preview:large">
    <link rel="canonical" href="{canonical}">
    {alternate_links(page)}
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Shuo">
    <meta property="og:locale" content="{locale}">
    {locale_alternates}
    <meta property="og:title" content="{html.escape(title, quote=True)}">
    <meta property="og:description" content="{html.escape(description, quote=True)}">
    <meta property="og:url" content="{canonical}">
    <meta property="og:image" content="{IMAGE_URL}">
    <meta property="og:image:width" content="512">
    <meta property="og:image:height" content="512">
    <meta property="og:image:alt" content="Shuo app icon">
    <meta name="twitter:card" content="summary">
    <meta name="twitter:title" content="{html.escape(title, quote=True)}">
    <meta name="twitter:description" content="{html.escape(description, quote=True)}">
    <meta name="twitter:image" content="{IMAGE_URL}">
    <script type="application/ld+json">{schema}</script>"""


class LocalizedHTMLParser(HTMLParser):
    """Filter non-target language nodes and replace document metadata."""

    def __init__(self, language: str, page_name: str, page: dict[str, object]):
        super().__init__(convert_charrefs=False)
        self.language = language
        self.page_name = page_name
        self.page = page
        self.target_class = LANGUAGES[language]["html_class"]
        self.output: list[str] = []
        self.skip_depth = 0
        self.skip_title = False

    @staticmethod
    def _serialized_attrs(attrs: list[tuple[str, str | None]]) -> str:
        output = []
        for name, value in attrs:
            if value is None:
                output.append(name)
            else:
                output.append(f'{name}="{html.escape(value, quote=True)}"')
        return (" " + " ".join(output)) if output else ""

    @staticmethod
    def _attr_map(attrs: list[tuple[str, str | None]]) -> dict[str, str]:
        return {name: value or "" for name, value in attrs}

    def _is_wrong_language(self, attrs: list[tuple[str, str | None]]) -> bool:
        classes = set(self._attr_map(attrs).get("class", "").split())
        return "lang" in classes and self.target_class not in classes

    def _rewrite_attrs(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> list[tuple[str, str | None]]:
        rewritten = []
        for name, value in attrs:
            if tag == "html" and name in {"lang", "data-language", "data-page-language", "data-page-name"}:
                continue
            if tag == "body" and name == "data-language":
                continue
            if tag == "option" and name == "selected":
                continue
            if value is not None and name in {"href", "src"} and (
                value.startswith("assets/")
                or value.startswith("styles.css")
                or value.startswith("script.js")
                or value == "site.webmanifest"
            ):
                value = f"../{value}"
            rewritten.append((name, value))

        if tag == "html":
            rewritten.extend(
                [
                    ("lang", self.language),
                    ("data-language", self.language),
                    ("data-page-language", self.language),
                    ("data-page-name", self.page_name),
                ]
            )
        elif tag == "body":
            rewritten.append(("data-language", self.language))
        elif tag == "option" and dict(rewritten).get("value") == self.language:
            rewritten.append(("selected", None))
        return rewritten

    def handle_decl(self, decl: str) -> None:
        self.output.append(f"<!{decl}>")

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.skip_depth:
            if tag not in VOID_ELEMENTS:
                self.skip_depth += 1
            return
        if self._is_wrong_language(attrs):
            self.skip_depth = 1
            return

        attr_map = self._attr_map(attrs)
        if tag == "title":
            self.skip_title = True
            return
        if tag == "meta" and (
            attr_map.get("name") in {"description", "robots", "twitter:card", "twitter:title", "twitter:description", "twitter:image"}
            or attr_map.get("property", "").startswith("og:")
        ):
            return
        if tag == "link" and attr_map.get("rel") in {"canonical", "alternate"}:
            return
        if tag == "script" and attr_map.get("type") == "application/ld+json":
            self.skip_depth = 1
            return

        attrs = self._rewrite_attrs(tag, attrs)
        self.output.append(f"<{tag}{self._serialized_attrs(attrs)}>")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.skip_depth or self._is_wrong_language(attrs):
            return
        attrs = self._rewrite_attrs(tag, attrs)
        self.output.append(f"<{tag}{self._serialized_attrs(attrs)} />")

    def handle_endtag(self, tag: str) -> None:
        if self.skip_depth:
            self.skip_depth -= 1
            return
        if tag == "title" and self.skip_title:
            self.skip_title = False
            return
        if tag == "head":
            self.output.append("\n" + metadata_markup(self.page_name, self.language, self.page) + "\n  ")
        self.output.append(f"</{tag}>")

    def handle_data(self, data: str) -> None:
        if not self.skip_depth and not self.skip_title:
            self.output.append(data)

    def handle_entityref(self, name: str) -> None:
        if not self.skip_depth and not self.skip_title:
            self.output.append(f"&{name};")

    def handle_charref(self, name: str) -> None:
        if not self.skip_depth and not self.skip_title:
            self.output.append(f"&#{name};")

    def handle_comment(self, data: str) -> None:
        if not self.skip_depth:
            self.output.append(f"<!--{data}-->")

    def handle_pi(self, data: str) -> None:
        if not self.skip_depth:
            self.output.append(f"<?{data}>")

    def rendered(self) -> str:
        return "".join(self.output)


class LanguageCoverageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.counts = {language: 0 for language in LANGUAGES}

    def handle_starttag(self, _tag: str, attrs: list[tuple[str, str | None]]) -> None:
        classes = set(dict(attrs).get("class", "").split())
        if "lang" not in classes:
            return
        for language, details in LANGUAGES.items():
            if details["html_class"] in classes:
                self.counts[language] += 1


class GeneratedPageAuditParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.html_attributes: dict[str, str] = {}
        self.body_attributes: dict[str, str] = {}
        self.canonical_urls: list[str] = []
        self.alternate_languages: set[str] = set()
        self.language_classes: set[str] = set()
        self.selected_options: set[str] = set()
        self.title_count = 0
        self.description_count = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = {name: value or "" for name, value in attrs}
        if tag == "html":
            self.html_attributes = attributes
        elif tag == "body":
            self.body_attributes = attributes
        elif tag == "title":
            self.title_count += 1
        elif tag == "meta" and attributes.get("name") == "description":
            self.description_count += 1
        elif tag == "link" and attributes.get("rel") == "canonical":
            self.canonical_urls.append(attributes.get("href", ""))
        elif tag == "link" and attributes.get("rel") == "alternate":
            self.alternate_languages.add(attributes.get("hreflang", ""))
        elif tag == "option" and "selected" in attributes:
            self.selected_options.add(attributes.get("value", ""))

        classes = set(attributes.get("class", "").split())
        if "lang" in classes:
            self.language_classes.update(
                classes & {details["html_class"] for details in LANGUAGES.values()}
            )


def validate_language_coverage(source: str, source_name: str) -> None:
    parser = LanguageCoverageParser()
    parser.feed(source)
    parser.close()
    counts = set(parser.counts.values())
    if len(counts) != 1 or counts == {0}:
        detail = ", ".join(f"{language}={count}" for language, count in parser.counts.items())
        raise ValueError(f"Incomplete language coverage in {source_name}: {detail}")


def validate_generated_page(
    rendered: str,
    language: str,
    page_name: str,
    page: dict[str, object],
) -> None:
    parser = GeneratedPageAuditParser()
    parser.feed(rendered)
    parser.close()
    expected_class = LANGUAGES[language]["html_class"]
    expected_alternates = {*LANGUAGES, "x-default"}
    expected_canonical = localized_url(language, page)

    if parser.html_attributes.get("lang") != language:
        raise ValueError(f"Generated {page_name}/{language} has an incorrect html lang")
    if parser.html_attributes.get("data-page-language") != language:
        raise ValueError(f"Generated {page_name}/{language} is not language-locked")
    if parser.html_attributes.get("data-page-name") != page_name:
        raise ValueError(f"Generated {page_name}/{language} has an incorrect page identity")
    if parser.body_attributes.get("data-language") != language:
        raise ValueError(f"Generated {page_name}/{language} has an incorrect body language")
    if parser.language_classes != {expected_class}:
        raise ValueError(
            f"Generated {page_name}/{language} contains other-language content: "
            f"{sorted(parser.language_classes)}"
        )
    if parser.canonical_urls != [expected_canonical]:
        raise ValueError(f"Generated {page_name}/{language} has an incorrect canonical URL")
    if parser.alternate_languages != expected_alternates:
        raise ValueError(f"Generated {page_name}/{language} has incomplete hreflang links")
    if parser.selected_options != {language}:
        raise ValueError(f"Generated {page_name}/{language} has an incorrect language selector")
    if parser.title_count != 1 or parser.description_count != 1:
        raise ValueError(f"Generated {page_name}/{language} has incomplete metadata")


def build(source_root: Path, output_root: Path) -> None:
    for page_name, page in PAGES.items():
        source = (source_root / page["source"]).read_text(encoding="utf-8")
        validate_language_coverage(source, page["source"])
        for language, details in LANGUAGES.items():
            parser = LocalizedHTMLParser(language, page_name, page)
            parser.feed(source)
            parser.close()
            rendered = parser.rendered()
            validate_generated_page(rendered, language, page_name, page)
            destination = output_root / details["slug"] / page["output"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(rendered, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).parent)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    build(arguments.source.resolve(), arguments.output.resolve())


if __name__ == "__main__":
    main()
