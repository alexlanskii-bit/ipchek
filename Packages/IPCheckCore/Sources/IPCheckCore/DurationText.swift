/// Длительность коротко, с сокращениями без склонений: «1 мин 40 с», «2 ч 5 мин».
public enum DurationText {
  public static func short(seconds: Int) -> String {
    let total = max(seconds, 0)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let rest = total % 60
    if hours > 0 {
      return minutes > 0 ? "\(hours) ч \(minutes) мин" : "\(hours) ч"
    }
    if minutes > 0 {
      return rest > 0 ? "\(minutes) мин \(rest) с" : "\(minutes) мин"
    }
    return "\(rest) с"
  }
}
