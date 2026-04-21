import XCTest
@testable import KokoroTTS

final class KokoroTTSTests: XCTestCase {

    func testDefaultModelId() {
        XCTAssertEqual(KokoroTTSModel.defaultModelId, "aufklarer/Kokoro-82M-CoreML")
    }

    func testDefaultConfig() {
        let config = KokoroConfig.default
        XCTAssertEqual(config.sampleRate, 24000)
        XCTAssertEqual(config.maxPhonemeLength, 128)
        XCTAssertEqual(config.styleDim, 256)
        XCTAssertEqual(config.languages.count, 8)
        XCTAssertTrue(config.languages.contains("en"))
    }

    func testConfigCodable() throws {
        let config = KokoroConfig.default
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(KokoroConfig.self, from: data)
        XCTAssertEqual(decoded.sampleRate, config.sampleRate)
        XCTAssertEqual(decoded.maxPhonemeLength, config.maxPhonemeLength)
        XCTAssertEqual(decoded.styleDim, config.styleDim)
    }

    // MARK: - Phonemizer Tests

    func testPhonemizerTokenize() {
        let vocab: [String: Int] = [
            "<pad>": 0, "<bos>": 1, "<eos>": 2,
            "h": 3, "e": 4, "l": 5, "o": 6, " ": 7,
        ]
        let phonemizer = KokoroPhonemizer(vocab: vocab)
        let ids = phonemizer.tokenize("hello")
        XCTAssertEqual(ids.first, 1)
        XCTAssertEqual(ids.last, 2)
        XCTAssertTrue(ids.count >= 3)
    }

    func testPhonemizerPadding() {
        let vocab: [String: Int] = ["<pad>": 0, "<bos>": 1, "<eos>": 2, "a": 3]
        let phonemizer = KokoroPhonemizer(vocab: vocab)
        let ids = phonemizer.tokenize("a")
        let padded = phonemizer.pad(ids, to: 10)
        XCTAssertEqual(padded.count, 10)
        XCTAssertEqual(padded[0], 1)
        XCTAssertEqual(padded.last(where: { $0 != 0 }), 2)
    }

    func testPhonemizerTruncation() {
        let vocab: [String: Int] = ["<pad>": 0, "<bos>": 1, "<eos>": 2, "a": 3]
        let phonemizer = KokoroPhonemizer(vocab: vocab)
        let longText = String(repeating: "a", count: 1000)
        let ids = phonemizer.tokenize(longText, maxLength: 20)
        XCTAssertEqual(ids.count, 20)
        XCTAssertEqual(ids.first, 1)
        XCTAssertEqual(ids.last, 2)
    }

    func testPhonemizerUnknownChars() {
        let vocab: [String: Int] = ["<pad>": 0, "<bos>": 1, "<eos>": 2, "a": 3]
        let phonemizer = KokoroPhonemizer(vocab: vocab)
        let ids = phonemizer.tokenize("axyz")
        XCTAssertEqual(ids, [1, 3, 2])
    }
}

// MARK: - Chinese Phonemizer Tests

final class ChinesePhonemeizerTests: XCTestCase {

    // MARK: - Tone Extraction

    func testExtractTone1() {
        let (base, tone) = ChinesePhonemizer.extractTone("nǐ")
        XCTAssertEqual(base, "ni")
        XCTAssertEqual(tone, "3")
    }

    func testExtractTone2() {
        let (base, tone) = ChinesePhonemizer.extractTone("hǎo")
        XCTAssertEqual(base, "hao")
        XCTAssertEqual(tone, "3")
    }

    func testExtractTone4() {
        let (base, tone) = ChinesePhonemizer.extractTone("shì")
        XCTAssertEqual(base, "shi")
        XCTAssertEqual(tone, "4")
    }

    func testExtractToneNeutral() {
        let (base, tone) = ChinesePhonemizer.extractTone("de")
        XCTAssertEqual(base, "de")
        XCTAssertEqual(tone, "5")
    }

    // MARK: - Finals Normalization

    func testNormalizeIU() {
        XCTAssertEqual(ChinesePhonemizer.normalizeFinalsNotation("liu"), "liou")
    }

    func testNormalizeUI() {
        XCTAssertEqual(ChinesePhonemizer.normalizeFinalsNotation("gui"), "guei")
    }

    func testNormalizeUN() {
        XCTAssertEqual(ChinesePhonemizer.normalizeFinalsNotation("gun"), "guen")
    }

    func testNormalizeJQXU() {
        // After j/q/x, u → ü
        XCTAssertEqual(ChinesePhonemizer.normalizeFinalsNotation("ju"), "jü")
        XCTAssertEqual(ChinesePhonemizer.normalizeFinalsNotation("qu"), "qü")
        XCTAssertEqual(ChinesePhonemizer.normalizeFinalsNotation("xu"), "xü")
    }

    // MARK: - Syllable → IPA

    func testSyllableMA() {
        let ipa = ChinesePhonemizer.syllableToIPA("mā")
        XCTAssertTrue(ipa.contains("m"), "Should contain initial 'm': \(ipa)")
        XCTAssertTrue(ipa.contains("a"), "Should contain final 'a': \(ipa)")
    }

    func testSyllableSHI() {
        let ipa = ChinesePhonemizer.syllableToIPA("shì")
        XCTAssertTrue(ipa.hasPrefix("ʂ"), "Should start with retroflex: \(ipa)")
    }

    func testSyllableZHI() {
        // "zhi" → zh + retroflex i
        let ipa = ChinesePhonemizer.syllableToIPA("zhī")
        XCTAssertTrue(ipa.hasPrefix("ʈʂ"), "Should start with ʈʂ: \(ipa)")
    }

    // MARK: - Full Pipeline

    func testChinesePhonemizerProducesOutput() {
        let phonemizer = ChinesePhonemizer()
        let result = phonemizer.phonemize("你好")
        XCTAssertFalse(result.isEmpty, "Should produce phonemes for Chinese text")
    }

    func testChinesePhonemizerPunctuation() {
        let phonemizer = ChinesePhonemizer()
        let result = phonemizer.phonemize("你好，世界。")
        XCTAssertTrue(result.contains(","), "Should convert Chinese comma")
        XCTAssertTrue(result.contains("."), "Should convert Chinese period")
    }

    func testChinesePhonemizerMultipleSyllables() {
        let phonemizer = ChinesePhonemizer()
        let result = phonemizer.phonemize("你好世界")
        // Should have multiple phoneme segments
        XCTAssertGreaterThan(result.count, 4, "Should produce multi-syllable IPA: \(result)")
    }
}

// MARK: - Japanese Phonemizer Tests

final class JapanesePhonemeizerTests: XCTestCase {

    // MARK: - Katakana → Phonemes

    func testSingleKatakana() {
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("ア"), "a")
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("カ"), "ka")
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("サ"), "sa")
    }

    func testDigraphKatakana() {
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("シャ"), "sha")
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("チャ"), "cha")
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("キョ"), "kyo")
    }

    func testSpecialKatakana() {
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("ッ"), "ʔ")
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("ン"), "ɴ")
        XCTAssertEqual(JapanesePhonemizer.katakanaToPhonemes("ー"), "ː")
    }

    func testKatakanaSequence() {
        // コンニチハ → ko ɴ ni chi ha
        let result = JapanesePhonemizer.katakanaToPhonemes("コンニチハ")
        XCTAssertEqual(result, "koɴnichiha")
    }

    func testDigraphPriority() {
        // キャ should match as digraph "kya", not キ+ャ → "ki"+"ya"
        let result = JapanesePhonemizer.katakanaToPhonemes("キャ")
        XCTAssertEqual(result, "kya")
    }

    // MARK: - Romaji → Katakana

    func testRomajiToKatakana() {
        let result = JapanesePhonemizer.romajiToKatakana("toukyou")
        // Should produce katakana
        XCTAssertTrue(result.unicodeScalars.allSatisfy {
            (0x30A0...0x30FF).contains($0.value) || $0.value == 0x30FC
        }, "Should be katakana: \(result)")
    }

    // MARK: - Full Pipeline

    func testJapanesePhonemizerProducesOutput() {
        let phonemizer = JapanesePhonemizer()
        let result = phonemizer.phonemize("こんにちは")
        XCTAssertFalse(result.isEmpty, "Should produce phonemes for Japanese text")
    }

    func testJapanesePhonemizerPunctuation() {
        let phonemizer = JapanesePhonemizer()
        let result = phonemizer.phonemize("こんにちは。")
        XCTAssertTrue(result.contains("."), "Should convert Japanese period")
    }

    func testJapanesePhonemizerKanji() {
        let phonemizer = JapanesePhonemizer()
        let result = phonemizer.phonemize("東京")
        XCTAssertFalse(result.isEmpty, "Should phonemize kanji: \(result)")
        // Should produce something like "toukyou" phonemes
        XCTAssertGreaterThan(result.count, 3, "Should produce multi-mora IPA: \(result)")
    }
}


// MARK: - Hindi Phonemizer Tests

final class HindiPhonemizerTests: XCTestCase {

    func testRomanToIPA() {
        let ipa = HindiPhonemizer.romanToIPA("namastē")
        XCTAssertFalse(ipa.isEmpty)
        XCTAssertTrue(ipa.contains("n"), "Should contain 'n': \(ipa)")
    }

    func testHindiPhonemizerProducesOutput() {
        let phonemizer = HindiPhonemizer()
        let result = phonemizer.phonemize("नमस्ते")
        XCTAssertFalse(result.isEmpty, "Should produce phonemes for Hindi: \(result)")
    }

    func testHindiMultipleWords() {
        let phonemizer = HindiPhonemizer()
        let result = phonemizer.phonemize("नमस्ते दुनिया")
        XCTAssertGreaterThan(result.count, 5, "Should produce multi-word IPA: \(result)")
    }
}

// MARK: - Latin Phonemizer Tests (French, Spanish, Portuguese)

final class LatinPhonemizerTests: XCTestCase {

    func testFrenchBasic() {
        let phonemizer = LatinPhonemizer(language: .french)
        let result = phonemizer.phonemize("Bonjour le monde")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("ʒ") || result.contains("ʁ"),
            "French should produce French IPA phonemes: \(result)")
    }

    func testSpanishBasic() {
        let phonemizer = LatinPhonemizer(language: .spanish)
        let result = phonemizer.phonemize("Hola mundo")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("o") && result.contains("l"),
            "Spanish should produce correct phonemes: \(result)")
    }

    func testPortugueseBasic() {
        let phonemizer = LatinPhonemizer(language: .portuguese)
        let result = phonemizer.phonemize("Olá mundo")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("a"),
            "Portuguese should produce correct phonemes: \(result)")
    }

    func testFrenchNasalVowels() {
        let phonemizer = LatinPhonemizer(language: .french)
        let result = phonemizer.phonemize("bonjour")
        XCTAssertTrue(result.contains("ɔ̃") || result.contains("ʒ"),
            "Should handle French nasals/consonants: \(result)")
    }

    func testSpanishContextRules() {
        let phonemizer = LatinPhonemizer(language: .spanish)
        // c before e → θ
        let result = phonemizer.phonemize("cena")
        XCTAssertTrue(result.contains("θ"), "c before e should be θ: \(result)")
    }

    func testPunctuation() {
        let phonemizer = LatinPhonemizer(language: .french)
        let result = phonemizer.phonemize("Bonjour, monde!")
        XCTAssertTrue(result.contains(","), "Should preserve comma")
        XCTAssertTrue(result.contains("!"), "Should preserve exclamation")
    }
}

// MARK: - Multilingual Tokenizer Routing Tests

final class MultilingualTokenizerTests: XCTestCase {

    private func makeVocab() -> [String: Int] {
        ["<pad>": 0, "<bos>": 1, "<eos>": 2,
         "a": 3, "b": 4, "d": 5, "e": 6, "f": 7, "h": 8,
         "i": 9, "k": 10, "l": 11, "m": 12, "n": 13, "o": 14,
         "p": 15, "r": 16, "s": 17, "t": 18, "u": 19, "w": 20,
         "ə": 21, "ɾ": 22, "ɡ": 23, "ʃ": 24, "ʒ": 25, "ʁ": 26,
         "ɲ": 27, "θ": 28, "x": 29, "ɛ": 30, "ɔ": 31, "j": 32,
         " ": 33, ",": 34, ".": 35]
    }

    func testChineseRouting() {
        let phonemizer = KokoroPhonemizer(vocab: makeVocab())
        let ids = phonemizer.tokenize("你好", language: "zh")
        XCTAssertEqual(ids.first, 1, "Should start with BOS")
        XCTAssertEqual(ids.last, 2, "Should end with EOS")
        XCTAssertGreaterThan(ids.count, 2, "Should produce tokens for Chinese")
    }

    func testJapaneseRouting() {
        let phonemizer = KokoroPhonemizer(vocab: makeVocab())
        let ids = phonemizer.tokenize("こんにちは", language: "ja")
        XCTAssertEqual(ids.first, 1)
        XCTAssertEqual(ids.last, 2)
        XCTAssertGreaterThan(ids.count, 2, "Should produce tokens for Japanese")
    }

    func testHindiRouting() {
        let phonemizer = KokoroPhonemizer(vocab: makeVocab())
        let ids = phonemizer.tokenize("नमस्ते", language: "hi")
        XCTAssertEqual(ids.first, 1)
        XCTAssertEqual(ids.last, 2)
        XCTAssertGreaterThan(ids.count, 2, "Should produce tokens for Hindi")
    }

    func testFrenchRouting() {
        let phonemizer = KokoroPhonemizer(vocab: makeVocab())
        let ids = phonemizer.tokenize("bonjour", language: "fr")
        XCTAssertEqual(ids.first, 1)
        XCTAssertEqual(ids.last, 2)
        XCTAssertGreaterThan(ids.count, 2, "Should produce tokens for French")
    }

    func testSpanishRouting() {
        let phonemizer = KokoroPhonemizer(vocab: makeVocab())
        let ids = phonemizer.tokenize("hola", language: "es")
        XCTAssertEqual(ids.first, 1)
        XCTAssertEqual(ids.last, 2)
        XCTAssertGreaterThan(ids.count, 2, "Should produce tokens for Spanish")
    }

    func testPortugueseRouting() {
        let phonemizer = KokoroPhonemizer(vocab: makeVocab())
        let ids = phonemizer.tokenize("olá", language: "pt")
        XCTAssertEqual(ids.first, 1)
        XCTAssertEqual(ids.last, 2)
        XCTAssertGreaterThan(ids.count, 2, "Should produce tokens for Portuguese")
    }

    func testEnglishRoutingDefault() {
        let phonemizer = KokoroPhonemizer(vocab: makeVocab())
        let idsDefault = phonemizer.tokenize("hello")
        let idsEn = phonemizer.tokenize("hello", language: "en")
        XCTAssertEqual(idsDefault, idsEn, "Default should route to English")
    }
}
