//! Document language detection and resolution for CJK-aware rendering.
//!
//! The rendered page gets a `lang` attribute so the browser (and `:lang()` CSS)
//! can pick the right glyph shapes and fonts for Japanese, Simplified Chinese,
//! Traditional Chinese, and Korean. Resolution order:
//!
//! 1. `lang:` in the document's YAML front matter
//! 2. explicit `--lang` / config `lang`
//! 3. content detection ([`detect`])
//! 4. OS locale (`LC_ALL` / `LANG`)
//! 5. none (no attribute)

/// A document language we know how to render specially.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lang {
    Ja,
    ZhHans,
    ZhHant,
    /// Chinese with unknown script (no distinctive characters seen).
    Zh,
    Ko,
}

impl Lang {
    /// BCP 47 tag used for the `lang` attribute.
    pub fn tag(self) -> &'static str {
        match self {
            Lang::Ja => "ja",
            Lang::ZhHans => "zh-Hans",
            Lang::ZhHant => "zh-Hant",
            Lang::Zh => "zh",
            Lang::Ko => "ko",
        }
    }

    /// Parse a user-supplied tag or locale string (case-insensitive, `_` or `-`).
    /// Accepts `ja`, `ja-JP`, `zh-Hans`, `zh-CN`, `zh-SG`, `zh-Hant`, `zh-TW`,
    /// `zh-HK`, `zh-MO`, `zh`, `ko`, `ko-KR`, and `LANG`-style values like `ja_JP.UTF-8`.
    pub fn parse(s: &str) -> Option<Lang> {
        let s = s.trim();
        let s = s.split('.').next().unwrap_or(s); // drop ".UTF-8"
        let s = s.split('@').next().unwrap_or(s); // drop "@euro"
        let lower = s.to_ascii_lowercase().replace('_', "-");
        let mut parts = lower.split('-');
        let primary = parts.next()?;
        let rest: Vec<&str> = parts.collect();
        match primary {
            "ja" | "jpn" => Some(Lang::Ja),
            "ko" | "kor" => Some(Lang::Ko),
            "zh" | "zho" | "chi" => {
                for p in &rest {
                    match *p {
                        "hans" | "cn" | "sg" | "my" => return Some(Lang::ZhHans),
                        "hant" | "tw" | "hk" | "mo" => return Some(Lang::ZhHant),
                        _ => {}
                    }
                }
                Some(Lang::Zh)
            }
            _ => None,
        }
    }
}

/// Split a leading YAML front matter block (`---\n...\n---`) off the content.
/// Returns `(lang value if present, body without the block)`.
pub fn split_front_matter(content: &str) -> (Option<String>, &str) {
    let rest = content.strip_prefix('\u{feff}').unwrap_or(content);
    let Some(after_open) = rest.strip_prefix("---") else {
        return (None, content);
    };
    // The opening fence must be alone on its line.
    let after_open = match after_open.strip_prefix("\r\n").or_else(|| after_open.strip_prefix('\n')) {
        Some(s) => s,
        None => return (None, content),
    };
    // Find the closing fence on its own line.
    let mut offset = 0;
    for line in after_open.split_inclusive('\n') {
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed == "---" || trimmed == "..." {
            let yaml = &after_open[..offset];
            let body = &after_open[offset + line.len()..];
            let lang = yaml.lines().find_map(|l| {
                let (k, v) = l.split_once(':')?;
                if k.trim().eq_ignore_ascii_case("lang") || k.trim().eq_ignore_ascii_case("language") {
                    let v = v.trim().trim_matches(|c| c == '"' || c == '\'');
                    if v.is_empty() { None } else { Some(v.to_string()) }
                } else {
                    None
                }
            });
            return (lang, body);
        }
        offset += line.len();
    }
    (None, content)
}

fn is_kana(c: char) -> bool {
    matches!(c, '\u{3041}'..='\u{309F}' | '\u{30A1}'..='\u{30FA}' | '\u{30FC}' | '\u{31F0}'..='\u{31FF}' | '\u{FF66}'..='\u{FF9F}')
}
fn is_hangul(c: char) -> bool {
    matches!(c, '\u{AC00}'..='\u{D7A3}' | '\u{1100}'..='\u{11FF}' | '\u{3131}'..='\u{318E}' | '\u{A960}'..='\u{A97F}')
}
fn is_bopomofo(c: char) -> bool {
    matches!(c, '\u{3105}'..='\u{312F}' | '\u{31A0}'..='\u{31BF}')
}
fn is_han(c: char) -> bool {
    matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}' | '\u{20000}'..='\u{2A6DF}' | '\u{F900}'..='\u{FAFF}')
}

/// Characters that occur in Simplified Chinese but are neither Traditional
/// Chinese nor standard Japanese (jōyō) forms. Forms shared with Japanese
/// shinjitai (国, 学, 会, 体, 医, 区, 写, 来, 台 ...) are deliberately excluded so
/// kanji-only Japanese text casts no vote.
const HANS_ONLY: &[char] = &[
    '这', '说', '们', '时', '为', '么', '个', '对', '还', '没', '过', '样', '点', '见', '两',
    '后', '开', '关', '发', '电', '机', '问', '题', '长', '间', '门', '东', '车', '马', '鸟',
    '语', '词', '书', '读', '认', '识', '让', '给', '从', '经', '济', '业', '产', '动', '风',
    '飞', '师', '药', '头', '脑', '网', '线', '视', '听', '买', '卖', '钱', '银', '岁', '几',
    '边', '远', '进', '运', '选', '设', '计', '论', '议', '讲', '结', '构', '组', '织', '统',
    '实', '现', '应', '该', '确', '务', '员', '团', '园', '图', '层', '页', '显', '码', '软',
    '输', '术', '数', '据', '库', '联', '击', '单', '复', '杂', '简', '汉', '华', '湾', '丽',
    '们', '爱', '欢', '乐', '难', '观', '习', '亚', '欧', '异', '导', '尽', '态', '亿',
];

/// Characters that occur in Traditional Chinese but differ from both the
/// Simplified and the standard Japanese form (e.g. 說 vs 説, 對 vs 対, 體 vs 体).
/// Traditional forms that Japanese also uses (見, 電, 語, 書, 確 ...) are excluded.
const HANT_ONLY: &[char] = &[
    '這', '說', '們', '麼', '對', '沒', '樣', '點', '兩', '關', '發', '寫', '讀', '讓', '從',
    '來', '經', '濟', '產', '醫', '藥', '腦', '聽', '賣', '錢', '歲', '邊', '實', '應', '團',
    '圖', '區', '顯', '數', '據', '擊', '單', '雜', '體', '臺', '灣', '愛', '歡', '樂', '難',
    '觀', '習', '亞', '歐', '異', '導', '盡', '態', '億', '覺', '學', '國', '會', '氣', '處',
    '衛', '證', '總', '權', '變', '轉', '將', '爲', '與', '舉', '體', '龍', '藝', '廣',
];

/// Strip fenced code, inline code, and URLs so they do not skew detection.
fn strip_noise(text: &str) -> String {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        regex::Regex::new(r"(?s)```.*?```|~~~.*?~~~|`[^`\n]*`|https?://\S+|<[^>\n]{1,200}>").unwrap()
    });
    re.replace_all(text, " ").into_owned()
}

/// Detect the document language from its text. Returns `None` for documents
/// with no CJK script, and for Han-only text with no distinctive simplified /
/// traditional characters (kanji-only Japanese is indistinguishable from
/// Chinese here; the caller falls back to locale).
pub fn detect(text: &str) -> Option<Lang> {
    let cleaned = strip_noise(text);
    // Sample the beginning of the document; this is plenty for script statistics.
    let sample: String = cleaned.chars().take(8000).collect();

    let (mut kana, mut hangul, mut bopomofo, mut han) = (0usize, 0usize, 0usize, 0usize);
    let (mut hans, mut hant) = (0usize, 0usize);
    for c in sample.chars() {
        if is_kana(c) {
            kana += 1;
        } else if is_hangul(c) {
            hangul += 1;
        } else if is_bopomofo(c) {
            bopomofo += 1;
        } else if is_han(c) {
            han += 1;
            if HANS_ONLY.contains(&c) {
                hans += 1;
            } else if HANT_ONLY.contains(&c) {
                hant += 1;
            }
        }
    }

    // Syllabaries / alphabets are decisive: pick the most frequent one.
    let best = [(kana, Lang::Ja), (hangul, Lang::Ko), (bopomofo, Lang::ZhHant)]
        .into_iter()
        .filter(|(n, _)| *n > 0)
        .max_by_key(|(n, _)| *n);
    if let Some((_, lang)) = best {
        return Some(lang);
    }
    if han == 0 {
        return None;
    }
    match hans.cmp(&hant) {
        std::cmp::Ordering::Greater => Some(Lang::ZhHans),
        std::cmp::Ordering::Less => Some(Lang::ZhHant),
        std::cmp::Ordering::Equal if hans > 0 => Some(Lang::Zh),
        _ => None, // Han only, nothing distinctive: could be Japanese or Chinese
    }
}

/// Language from the OS locale environment, if it is one we handle.
pub fn from_env_locale() -> Option<Lang> {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .find(|v| !v.is_empty() && v != "C" && v != "POSIX")
        .and_then(|v| Lang::parse(&v))
}

/// Full resolution: front matter > explicit > detection > locale.
/// `explicit` may be `"auto"` (or empty) to mean "not specified".
pub fn resolve(content: &str, explicit: Option<&str>) -> Option<Lang> {
    let (fm, body) = split_front_matter(content);
    if let Some(l) = fm.as_deref().and_then(Lang::parse) {
        return Some(l);
    }
    if let Some(l) = explicit
        .filter(|s| !s.is_empty() && !s.eq_ignore_ascii_case("auto"))
        .and_then(Lang::parse)
    {
        return Some(l);
    }
    detect(body).or_else(from_env_locale)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn japanese_with_kana() {
        assert_eq!(detect("これは日本語の文書です。表示を確認する。"), Some(Lang::Ja));
    }

    #[test]
    fn kanji_only_japanese_is_undecidable() {
        // Common shinjitai are deliberately excluded from the vote table.
        assert_eq!(detect("動作確認 新規作成 学校 会社"), None);
    }

    #[test]
    fn simplified_chinese() {
        assert_eq!(detect("这是一个简体中文的文档，用来测试显示。"), Some(Lang::ZhHans));
    }

    #[test]
    fn traditional_chinese() {
        assert_eq!(detect("這是一個繁體中文的文件，用來測試顯示。"), Some(Lang::ZhHant));
    }

    #[test]
    fn bopomofo_is_traditional() {
        assert_eq!(detect("注音符號 ㄅㄆㄇㄈ 練習"), Some(Lang::ZhHant));
    }

    #[test]
    fn korean() {
        assert_eq!(detect("이것은 한국어 문서입니다. 표시를 확인합니다."), Some(Lang::Ko));
    }

    #[test]
    fn english_is_none() {
        assert_eq!(detect("# Title\n\nJust some English text with 中 nothing else."), None);
        assert_eq!(detect("Plain ASCII only."), None);
    }

    #[test]
    fn code_blocks_and_urls_are_ignored() {
        let md = "# README\n\n```\nこれはコード内の日本語\n```\n\nhttps://example.com/日本語 `インライン`\n\nThis is English.";
        assert_eq!(detect(md), None);
    }

    #[test]
    fn mixed_picks_dominant_syllabary() {
        let md = "한국어 문장이 많습니다. 한국어 한국어 한국어. 日本語のひらがな。";
        assert_eq!(detect(md), Some(Lang::Ko));
    }

    #[test]
    fn parse_tags_and_locales() {
        assert_eq!(Lang::parse("ja"), Some(Lang::Ja));
        assert_eq!(Lang::parse("ja_JP.UTF-8"), Some(Lang::Ja));
        assert_eq!(Lang::parse("zh-Hans"), Some(Lang::ZhHans));
        assert_eq!(Lang::parse("zh_CN"), Some(Lang::ZhHans));
        assert_eq!(Lang::parse("zh-TW"), Some(Lang::ZhHant));
        assert_eq!(Lang::parse("zh-Hant-HK"), Some(Lang::ZhHant));
        assert_eq!(Lang::parse("zh"), Some(Lang::Zh));
        assert_eq!(Lang::parse("ko-KR"), Some(Lang::Ko));
        assert_eq!(Lang::parse("en_US.UTF-8"), None);
        assert_eq!(Lang::parse("C"), None);
    }

    #[test]
    fn front_matter_lang_wins() {
        let md = "---\ntitle: x\nlang: zh-Hant\n---\n\nこれは日本語です。";
        let (fm, body) = split_front_matter(md);
        assert_eq!(fm.as_deref(), Some("zh-Hant"));
        assert!(body.starts_with("\nこれは"));
        assert_eq!(resolve(md, None), Some(Lang::ZhHant));
    }

    #[test]
    fn explicit_beats_detection_but_not_front_matter() {
        assert_eq!(resolve("これは日本語です。", Some("ko")), Some(Lang::Ko));
        assert_eq!(resolve("これは日本語です。", Some("auto")), Some(Lang::Ja));
        assert_eq!(resolve("---\nlang: ja\n---\nhello", Some("ko")), Some(Lang::Ja));
    }

    #[test]
    fn front_matter_requires_closing_fence() {
        let md = "---\nlang: ja\nno closing fence";
        let (fm, body) = split_front_matter(md);
        assert_eq!(fm, None);
        assert_eq!(body, md);
    }

    #[test]
    fn no_front_matter_when_not_at_start() {
        let md = "# Title\n---\nlang: ja\n---\n";
        assert_eq!(split_front_matter(md).0, None);
    }
}
