use std::{cmp::Reverse, collections::HashMap};

pub(crate) struct IndexedEntry {
    pub(crate) id: String,
    pub(crate) name_lower: String,
    pub(crate) fields_lower: Vec<String>,
    pub(crate) usage: u32,
}

impl IndexedEntry {
    pub(crate) fn new(
        id: String,
        name: &str,
        generic_name: Option<&str>,
        keywords: &[String],
        usage: u32,
    ) -> Self {
        let name_lower = name.to_lowercase();
        let mut fields_lower = Vec::with_capacity(1 + usize::from(generic_name.is_some()) + keywords.len());
        if !name_lower.is_empty() {
            fields_lower.push(name_lower.clone());
        }
        if let Some(g) = generic_name {
            if !g.is_empty() {
                fields_lower.push(g.to_lowercase());
            }
        }
        for kw in keywords {
            if !kw.is_empty() {
                fields_lower.push(kw.to_lowercase());
            }
        }
        Self {
            id,
            name_lower,
            fields_lower,
            usage,
        }
    }
}

pub(crate) struct Matcher {
    entries: Vec<IndexedEntry>,
    usage_map: HashMap<String, u32>,
    scratch: Vec<(u8, u32, i32, usize)>,
}

impl Matcher {
    pub(crate) fn new() -> Self {
        Self {
            entries: Vec::new(),
            usage_map: HashMap::new(),
            scratch: Vec::new(),
        }
    }

    pub(crate) fn set_entries(&mut self, mut entries: Vec<IndexedEntry>) {
        for entry in &mut entries {
            if let Some(&count) = self.usage_map.get(&entry.id) {
                entry.usage = count;
            }
        }
        self.entries = entries;
    }

    pub(crate) fn set_usage(&mut self, usage: HashMap<String, u32>) {
        self.usage_map = usage;
        for entry in &mut self.entries {
            entry.usage = self.usage_map.get(&entry.id).copied().unwrap_or(0);
        }
    }

    /// Rank indexed entries for `query`, writing matching entry indices into `out`.
    pub(crate) fn rank(&mut self, query: &str, out: &mut Vec<usize>) {
        out.clear();
        let q = query.trim().to_lowercase();
        self.scratch.clear();

        if q.is_empty() {
            for (idx, entry) in self.entries.iter().enumerate() {
                self.scratch.push((0, entry.usage, 0, idx));
            }
            let entries = &self.entries;
            self.scratch.sort_unstable_by(|a, b| {
                b.1.cmp(&a.1)
                    .then_with(|| entries[a.3].name_lower.cmp(&entries[b.3].name_lower))
            });
            out.extend(self.scratch.iter().map(|item| item.3));
            return;
        }

        let q_bytes = q.as_bytes();
        let q_ascii = q.is_ascii();

        for (idx, entry) in self.entries.iter().enumerate() {
            if let Some((tier, bonus)) = score_entry(entry, &q, q_bytes, q_ascii) {
                self.scratch.push((tier, entry.usage, bonus, idx));
            }
        }

        let entries = &self.entries;
        self.scratch.sort_unstable_by(|a, b| {
            a.0.cmp(&b.0)
                .then_with(|| Reverse(a.1).cmp(&Reverse(b.1)))
                .then_with(|| Reverse(a.2).cmp(&Reverse(b.2)))
                .then_with(|| entries[a.3].name_lower.cmp(&entries[b.3].name_lower))
        });

        out.extend(self.scratch.iter().map(|item| item.3));
    }
}

fn score_entry(
    entry: &IndexedEntry,
    q: &str,
    q_bytes: &[u8],
    q_ascii: bool,
) -> Option<(u8, i32)> {
    if entry.name_lower.starts_with(q) {
        return Some((0, 0));
    }

    let mut best_subseq: Option<i32> = None;
    for (field_idx, field) in entry.fields_lower.iter().enumerate() {
        if let Some(pos) = field.find(q) {
            // Prefer earlier field (name > genericName > keywords) and earlier match offset.
            let bonus = -(field_idx as i32) * 16 - (pos as i32);
            return Some((1, bonus));
        }
        let quality = if q_ascii && field.is_ascii() {
            subsequence_ascii(q_bytes, field.as_bytes())
        } else {
            subsequence_unicode(q, field)
        };
        if let Some(score) = quality {
            let adjusted = score - (field_idx as i32) * 8;
            if best_subseq.is_none_or(|prev| adjusted > prev) {
                best_subseq = Some(adjusted);
            }
        }
    }

    best_subseq.map(|bonus| (2, bonus))
}

#[inline]
fn is_boundary_byte(b: u8) -> bool {
    matches!(b, b' ' | b'-' | b'_' | b'.' | b'/')
}

fn subsequence_ascii(needle: &[u8], hay: &[u8]) -> Option<i32> {
    if needle.len() > hay.len() {
        return None;
    }
    let mut j = 0usize;
    let mut bonus = 0i32;
    let mut last_match: Option<usize> = None;

    for (i, &b) in hay.iter().enumerate() {
        if b == needle[j] {
            if i == 0 || is_boundary_byte(hay[i - 1]) {
                bonus += 6;
            }
            if let Some(prev) = last_match {
                if i == prev + 1 {
                    bonus += 5;
                } else {
                    bonus -= (i - prev - 1).min(8) as i32;
                }
            }
            last_match = Some(i);
            j += 1;
            if j == needle.len() {
                return Some(bonus);
            }
        }
    }
    None
}

fn subsequence_unicode(needle: &str, hay: &str) -> Option<i32> {
    let mut needle_chars = needle.chars();
    let mut target = needle_chars.next()?;
    let mut bonus = 0i32;
    let mut prev_sep = true;

    for ch in hay.chars() {
        if ch == target {
            if prev_sep {
                bonus += 6;
            }
            match needle_chars.next() {
                Some(next) => target = next,
                None => return Some(bonus),
            }
        }
        prev_sep = !ch.is_alphanumeric();
    }
    None
}
