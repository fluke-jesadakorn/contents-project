//! Whisper prompt + hallucination-strip utilities.
//!
//! Mirrors `SUPPRESS_REGEX`, `HALLUC_TAGS`, `build_whisper_prompt`, and
//! `_strip_hallucinations` from the Python implementation.

use once_cell::sync::Lazy;
use regex::Regex;

#[allow(dead_code)] // reserved for a future whisper.cpp backend
pub const DEFAULT_WHISPER_PROMPT: &str = "A conversation.";

/// Substrings we ask whisper-cli to suppress via `--suppress-regex`.
pub const SUPPRESS_REGEX: &str =
    r"\b([dD]anke fürs zuschauen|[uU]ntertitel|[sS]ubtitles|[mM]usik|[aA]mara|字幕組)\b";

/// Post-process stripping — catches cases the regex didn't (especially MLX).
pub const HALLUC_TAGS: &[&str] = &[
    "[MUSIK]", "[musik]", "[ Music ]", "[音楽]", "[비명]", "[박수]", "[拍手]",
    "(Lebhafte Musik)", "(Music)",
];

static RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(SUPPRESS_REGEX).expect("valid suppress regex"));

static HALLUC_RE: Lazy<Regex> = Lazy::new(|| {
    let escaped = HALLUC_TAGS
        .iter()
        .map(|t| regex::escape(t))
        .collect::<Vec<_>>()
        .join("|");
    Regex::new(&format!("(?i)({})", escaped)).expect("valid halluc regex")
});

static REPETITION_TOKENS: Lazy<Regex> = Lazy::new(|| Regex::new(r"\S+").unwrap());

static STUTTER_THAI_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"[\u0E00-\u0E7F]{4,}").unwrap());

/// Build the whisper prompt for a given source language.
#[allow(dead_code)] // reserved for a future whisper.cpp backend
pub fn build_whisper_prompt(src_lang: &str) -> String {
    // Optional: include language hints / glossary here in the future.
    let s = DEFAULT_WHISPER_PROMPT.to_string();
    if !src_lang.is_empty() && src_lang != "auto" {
        // We don't add specific language hints to keep whisper robust across
        // language switches; the Python version doesn't either.
    }
    s
}

/// Strip common hallucinations from a transcription.
pub fn strip_hallucinations(input: &str) -> String {
    let mut text = input.to_string();
    text = HALLUC_RE.replace_all(&text, " ").to_string();
    text = RE.replace_all(&text, " ").to_string();
    text = collapse_repetition(&text);
    text = STUTTER_THAI_RE.replace_all(&text, |caps: &regex::Captures| {
        // Collapse 4+ Thai character run to 2 (preserves the char once).
        let s = &caps[0];
        let first: String = s.chars().take(2).collect();
        first
    })
    .to_string();
    // Collapse runs of whitespace.
    text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    text.trim().to_string()
}

/// Collapse runs of 3+ identical consecutive tokens (e.g. "the the the the fox"
/// → "the fox"). Implemented in code since `regex` doesn't support backrefs.
fn collapse_repetition(input: &str) -> String {
    let tokens: Vec<&str> = REPETITION_TOKENS.find_iter(input).map(|m| m.as_str()).collect();
    if tokens.len() < 3 {
        return input.to_string();
    }
    let mut out: Vec<&str> = Vec::with_capacity(tokens.len());
    let mut i = 0;
    while i < tokens.len() {
        let cur = tokens[i];
        let lower_cur = cur.to_lowercase();
        let mut j = i + 1;
        while j < tokens.len() && tokens[j].to_lowercase() == lower_cur {
            j += 1;
        }
        let run_len = j - i;
        if run_len >= 3 {
            out.push(cur);
        } else {
            out.extend(tokens[i..j].iter().copied());
        }
        i = j;
    }
    out.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_musik_tag() {
        let s = "Hallo Welt [MUSIK] Wie geht es dir?";
        assert_eq!(strip_hallucinations(s), "Hallo Welt Wie geht es dir?");
    }

    #[test]
    fn strips_repetition() {
        let s = "the the the the quick brown fox";
        let out = strip_hallucinations(s);
        assert!(out.contains("quick brown fox"));
        assert!(!out.contains("the the the"));
    }

    #[test]
    fn default_prompt_works() {
        assert!(!build_whisper_prompt("en").is_empty());
        assert!(!build_whisper_prompt("auto").is_empty());
    }
}