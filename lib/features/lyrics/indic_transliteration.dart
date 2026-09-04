/// High-performance Indic phonetic transliterator for lyrics.
/// Maps Devanagari and Tamil Unicode code points into Latin Romanized phonetic equivalents.
class IndicTransliterator {
  static const Map<int, String> _devanagariVowels = {
    0x0905: 'a',
    0x0906: 'aa',
    0x0907: 'i',
    0x0908: 'ee',
    0x0909: 'u',
    0x090A: 'oo',
    0x090F: 'e',
    0x0910: 'ai',
    0x0913: 'o',
    0x0914: 'au',
  };

  static const Map<int, String> _devanagariConsonants = {
    0x0915: 'k',
    0x0916: 'kh',
    0x0917: 'g',
    0x0918: 'gh',
    0x0919: 'ng',
    0x091A: 'ch',
    0x091B: 'chh',
    0x091C: 'j',
    0x091D: 'jh',
    0x091E: 'ny',
    0x091F: 't',
    0x0920: 'th',
    0x0921: 'd',
    0x0922: 'dh',
    0x0923: 'n',
    0x0924: 't',
    0x0925: 'th',
    0x0926: 'd',
    0x0927: 'dh',
    0x0928: 'n',
    0x092A: 'p',
    0x092B: 'ph',
    0x092C: 'b',
    0x092D: 'bh',
    0x092E: 'm',
    0x092F: 'y',
    0x0930: 'r',
    0x0932: 'l',
    0x0935: 'v',
    0x0936: 'sh',
    0x0937: 'sh',
    0x0938: 's',
    0x0939: 'h',
  };

  static const Map<int, String> _devanagariMatras = {
    0x093E: 'aa',
    0x093F: 'i',
    0x0940: 'ee',
    0x0941: 'u',
    0x0942: 'oo',
    0x0947: 'e',
    0x0948: 'ai',
    0x094B: 'o',
    0x094C: 'au',
  };

  static const int _devanagariVirama = 0x094D;
  static const int _devanagariAnusvara = 0x0902;
  static const int _devanagariVisarga = 0x0903;

  static const Map<int, String> _tamilVowels = {
    0x0B85: 'a',
    0x0B86: 'aa',
    0x0B87: 'i',
    0x0B88: 'ee',
    0x0B89: 'u',
    0x0B8A: 'oo',
    0x0B8E: 'e',
    0x0B8F: 'ee',
    0x0B90: 'ai',
    0x0B92: 'o',
    0x0B93: 'oo',
    0x0B94: 'au',
  };

  static const Map<int, String> _tamilConsonants = {
    0x0B95: 'k',
    0x0B99: 'ng',
    0x0B9A: 'ch',
    0x0B9C: 'j',
    0x0B9E: 'ny',
    0x0B9F: 't',
    0x0BA3: 'n',
    0x0BA4: 'th',
    0x0BA8: 'n',
    0x0BA9: 'n',
    0x0BAA: 'p',
    0x0BAE: 'm',
    0x0BAF: 'y',
    0x0BB0: 'r',
    0x0BB1: 'r',
    0x0BB2: 'l',
    0x0BB3: 'l',
    0x0BB4: 'zh',
    0x0BB5: 'v',
    0x0BB7: 'sh',
    0x0BB8: 's',
    0x0BB9: 'h',
  };

  static const Map<int, String> _tamilMatras = {
    0x0BBE: 'aa',
    0x0BBF: 'i',
    0x0BC0: 'ee',
    0x0BC1: 'u',
    0x0BC2: 'oo',
    0x0BC6: 'e',
    0x0BC7: 'ee',
    0x0BC8: 'ai',
    0x0BCA: 'o',
    0x0BCB: 'oo',
    0x0BCC: 'au',
  };

  static const int _tamilVirama = 0x0BCD;

  /// Transliterates text containing Devanagari or Tamil scripts to phonetic Latin characters.
  /// Preserves non-Indic characters (English, punctuation, spaces, numbers).
  static String transliterate(String text) {
    if (text.isEmpty) return text;

    final runes = text.runes.toList();
    final buffer = StringBuffer();
    final len = runes.length;

    for (int i = 0; i < len; i++) {
      final code = runes[i];

      // Devanagari check (0x0900 - 0x097F)
      if (code >= 0x0900 && code <= 0x097F) {
        if (_devanagariVowels.containsKey(code)) {
          buffer.write(_devanagariVowels[code]);
        } else if (_devanagariConsonants.containsKey(code)) {
          final consonant = _devanagariConsonants[code]!;
          // Check following rune for matra or virama
          if (i + 1 < len) {
            final nextCode = runes[i + 1];
            if (nextCode == _devanagariVirama) {
              buffer.write(consonant);
              i++; // Skip virama
            } else if (_devanagariMatras.containsKey(nextCode)) {
              buffer.write(consonant);
              buffer.write(_devanagariMatras[nextCode]);
              i++; // Skip matra
            } else {
              buffer.write('${consonant}a');
            }
          } else {
            buffer.write('${consonant}a');
          }
        } else if (_devanagariMatras.containsKey(code)) {
          buffer.write(_devanagariMatras[code]);
        } else if (code == _devanagariAnusvara) {
          buffer.write('n');
        } else if (code == _devanagariVisarga) {
          buffer.write('h');
        } else if (code == _devanagariVirama) {
          // Handled above
        } else {
          buffer.write(String.fromCharCode(code));
        }
        continue;
      }

      // Tamil check (0x0B80 - 0x0BFF)
      if (code >= 0x0B80 && code <= 0x0BFF) {
        if (_tamilVowels.containsKey(code)) {
          buffer.write(_tamilVowels[code]);
        } else if (_tamilConsonants.containsKey(code)) {
          final consonant = _tamilConsonants[code]!;
          if (i + 1 < len) {
            final nextCode = runes[i + 1];
            if (nextCode == _tamilVirama) {
              buffer.write(consonant);
              i++; // Skip virama
            } else if (_tamilMatras.containsKey(nextCode)) {
              buffer.write(consonant);
              buffer.write(_tamilMatras[nextCode]);
              i++; // Skip matra
            } else {
              buffer.write('${consonant}a');
            }
          } else {
            buffer.write('${consonant}a');
          }
        } else if (_tamilMatras.containsKey(code)) {
          buffer.write(_tamilMatras[code]);
        } else if (code == _tamilVirama) {
          // Handled above
        } else {
          buffer.write(String.fromCharCode(code));
        }
        continue;
      }

      // Standard character (Latin, punctuation, etc.)
      buffer.write(String.fromCharCode(code));
    }

    return buffer.toString();
  }

  /// Check whether a string contains any Indic characters
  static bool containsIndic(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x0900 && rune <= 0x097F) || (rune >= 0x0B80 && rune <= 0x0BFF)) {
        return true;
      }
    }
    return false;
  }
}
