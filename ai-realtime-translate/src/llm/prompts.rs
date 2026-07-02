//! Translation prompt builder + memory block + validation.
//!
//! Mirrors `build_translation_prompt`, `_memory_block`, and
//! `validate_translation` from the Python implementation.

use crate::state::TranscriptEntry;

/// Build the system prompt for the LLM.
pub fn build_translation_prompt(
    src: &str,
    tgt: &str,
    glossary: &str,
    custom_prompt: &str,
    concise: bool,
) -> String {
    let pair = format!("{}→{}", src.to_uppercase(), tgt.to_uppercase());
    let base = match (src, tgt) {
        ("de", "th") => DE_TO_TH,
        ("en", "th") => EN_TO_TH,
        ("ja", "th") => JA_TO_TH,
        _ => GENERIC,
    };
    let mut prompt = base.replace("{PAIR}", &pair).to_string();

    if concise {
        prompt.push_str("\n\nBe CONCISE. Use the shortest natural translation — no extra explanation, no repetition.");
    }
    if !glossary.trim().is_empty() {
        prompt.push_str("\n\nGLOSSARY (preferred terms; always translate these accordingly):\n");
        prompt.push_str(glossary.trim());
    }
    if !custom_prompt.trim().is_empty() {
        prompt.push_str("\n\nADDITIONAL INSTRUCTIONS:\n");
        prompt.push_str(custom_prompt.trim());
    }
    prompt
}

const DE_TO_TH: &str = r#"You are a real-time translator for {PAIR}.
Input is German speech-to-text. Translate it into natural, fluent Thai.

Rules:
- Preserve meaning, tone, and intent. Be literal but readable.
- Numbers, dates, times: write in Thai (e.g. "drei Uhr" → "สามโมง", "Montag" → "วันจันทร์").
- Keep names, brands, technical terms in the original form where appropriate.
- NEVER add explanation, notes, or commentary. Output ONLY the Thai translation."#;

const EN_TO_TH: &str = r#"You are a real-time translator for {PAIR}.
Input is English speech-to-text. Translate it into natural, fluent Thai.

Rules:
- Preserve meaning, tone, and intent. Be literal but readable.
- Numbers, dates, times: write in Thai (e.g. "3 PM" → "บ่ายสามโมง", "Monday" → "วันจันทร์").
- Keep names, brands, technical terms in the original form where appropriate.
- NEVER add explanation, notes, or commentary. Output ONLY the Thai translation."#;

const JA_TO_TH: &str = r#"You are a real-time translator for {PAIR}.
Input is Japanese speech-to-text. Translate it into natural, fluent Thai.

Rules:
- Preserve meaning, tone, and intent. Be literal but readable.
- Numbers, dates, times: write in Thai (e.g. "三時" → "สามโมง", "月曜日" → "วันจันทร์").
- Honorifics: drop them unless directly relevant.
- NEVER add explanation, notes, or commentary. Output ONLY the Thai translation."#;

const GENERIC: &str = r#"You are a real-time translator for {PAIR}.
Translate the input into the target language.

Rules:
- Preserve meaning, tone, and intent.
- Keep names, brands, technical terms in their original form when natural in the target.
- NEVER add explanation, notes, or commentary. Output ONLY the translation."#;

/// Format the last N segments as a context block for the LLM.
pub fn memory_block(history: &[TranscriptEntry]) -> String {
    if history.is_empty() {
        return String::new();
    }
    let mut s = String::from("RECENT CONTEXT (older → newer):\n");
    for (i, h) in history.iter().rev().enumerate() {
        s.push_str(&format!(
            "{}. {} → {}\n",
            i + 1,
            truncate(&h.src, 200),
            truncate(&h.tgt, 200)
        ));
    }
    s.push_str("\nTRANSLATE NOW:\n");
    s
}

fn truncate(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        s.to_string()
    } else {
        let mut out: String = s.chars().take(n).collect();
        out.push('…');
        out
    }
}

/// Light validation — reject obvious failures (echo, empty, off-topic).
pub fn validate_translation(src: &str, tgt: &str, _src_lang: &str, tgt_lang: &str) -> bool {
    let tgt = tgt.trim();
    if tgt.is_empty() {
        return false;
    }
    // Echo: identical to source.
    if tgt == src.trim() && src.trim().len() > 4 {
        return false;
    }
    // Target-language character check (rough heuristic for non-Latin scripts).
    if tgt_lang == "th" {
        let thai = tgt.chars().filter(|c| ('\u{0E00}'..='\u{0E7F}').contains(c)).count();
        if thai == 0 && tgt.chars().count() > 4 {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_de_th_prompt() {
        let p = build_translation_prompt("de", "th", "", "", false);
        assert!(p.contains("DE→TH"));
        assert!(p.contains("German"));
    }

    #[test]
    fn memory_block_empty() {
        assert_eq!(memory_block(&[]), "");
    }

    #[test]
    fn validation_rejects_echo() {
        assert!(!validate_translation("hello world", "hello world", "en", "th"));
    }

    #[test]
    fn validation_rejects_non_thai() {
        assert!(!validate_translation("hi", "hello", "en", "th"));
    }
}