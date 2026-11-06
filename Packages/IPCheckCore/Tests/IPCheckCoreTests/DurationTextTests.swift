import IPCheckCore
import Testing

@Suite("Длительность коротко")
struct DurationTextTests {
  @Test(
    "Секунды, минуты и часы",
    arguments: [
      (0, "0 с"), (59, "59 с"), (60, "1 мин"), (100, "1 мин 40 с"), (3599, "59 мин 59 с"),
      (3600, "1 ч"), (3725, "1 ч 2 мин"), (90_000, "25 ч"),
    ])
  func formats(seconds: Int, expected: String) {
    #expect(DurationText.short(seconds: seconds) == expected)
  }

  @Test("Отрицательное значение (часы Mac перевели назад) — «0 с»")
  func negativeIsZero() {
    #expect(DurationText.short(seconds: -5) == "0 с")
  }
}
