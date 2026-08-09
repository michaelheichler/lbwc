## Chapter 4: Unicode Text Versus Bytes
### Core Ideas
- Python 3 treats human-readable text and raw byte sequences as different domains: `str` stores Unicode characters, while `bytes` and `bytearray` store integers from 0 through 255.
- Encoding turns text into bytes for storage or transport, and decoding turns bytes back into text. The codec must match the data, or the result may fail or silently become wrong.
- `bytes`, `bytearray`, and `memoryview` support low-level binary work, but their indexing, slicing, mutability, and copying behavior differ from `str`.
- UTF codecs can represent the whole Unicode range. Many legacy encodings cover only a small character set and can produce encode errors or misleading decoded text.
- Text I/O should follow the Unicode sandwich: decode at the boundary, process `str` internally, then encode only at output boundaries.
- Unicode equality is not just byte or code-point equality. Normalization and case folding are needed for dependable matching across composed characters, compatibility characters, and language-specific casing behavior.
- Sorting Unicode text by code point is usually not human-correct. Locale-aware collation or a Unicode Collation Algorithm implementation is needed when order matters to users.
- Python exposes Unicode metadata through `unicodedata`, and some standard APIs intentionally behave differently when passed `str` versus `bytes`.

### Practitioner Guidance
- In reviews, flag text file access that omits `encoding=`. Default encodings vary by platform, locale, redirection, and standard stream state.
- Keep API boundaries explicit: accept `str` for text APIs, `bytes` for binary protocols, and convert only at file, network, CLI, or OS boundaries.
- Prefer UTF-8 for durable text interchange unless an external protocol, file format, or legacy system requires a different codec.
- Treat `errors="ignore"` and broad replacement handlers as data-loss choices. Require a clear reason and a user-visible recovery strategy.
- Use `unicodedata.normalize("NFC", value)` before storing or comparing general user text, and add `.casefold()` for case-insensitive matching.
- Reserve NFKC/NFKD, accent stripping, and ASCII simplification for search keys, slugs, indexing, or compatibility layers, not for preserving original user text.
- For Unicode sorting, use process-level locale setup only in applications, not libraries. Consider `pyuca` or ICU-style tooling when deployments make OS locale support unreliable.
- When working with filesystem paths or regexes, check whether the code is operating on `str` or `bytes`. The same API can have different matching and return semantics.

### Pitfalls
- Assuming one character equals one byte breaks for almost all real-world non-ASCII text.
- Decoding with the wrong 8-bit codec may produce plausible but incorrect text without raising an exception.
- UTF-8 files with a BOM can trip tools that expect the first bytes to have another meaning, such as Unix executable scripts.
- Redirected standard output can use a different encoding than an interactive terminal, especially on Windows.
- Comparing or deduplicating raw Unicode strings without normalization can miss visually identical text.
- Removing diacritics or applying compatibility normalization can change meaning, especially outside the narrow use case of search or display simplification.

### Skill Hooks
- Unicode, `str` vs `bytes`, binary sequence, `bytearray`, `memoryview`
- `.encode()`, `.decode()`, codec, encoding, decoding, UTF-8, UTF-16, BOM, UTF-8-SIG
- `UnicodeEncodeError`, `UnicodeDecodeError`, source file encoding, coding cookie
- text file, `open(..., encoding=...)`, locale default, standard I/O encoding, Windows code page
- normalization, NFC, NFD, NFKC, NFKD, `unicodedata.normalize`
- case-insensitive Unicode comparison, `casefold`, accent stripping, slug generation, ASCII fallback
- collation, Unicode sorting, locale, `locale.strxfrm`, `pyuca`, ICU
- `unicodedata.name`, character lookup, numeric Unicode metadata, Unicode categories
- regex on text vs regex on bytes, `os.listdir` with `str` or `bytes`, `os.fsencode`, `os.fsdecode`

### Cross-Links
- Chapter 2 / sequence material: binary sequences, slicing behavior, and `memoryview` are linked from this chapter.
- File I/O material: text wrappers, binary mode, and explicit encodings connect naturally to broader file-handling guidance.
- Regular expression guidance: `str` patterns and `bytes` patterns have different Unicode awareness.
- OS/path handling guidance: filesystem encoding and dual-mode path APIs affect filename handling.
- Companion binary parsing material: `struct` and binary records extend the low-level bytes side of this chapter.
