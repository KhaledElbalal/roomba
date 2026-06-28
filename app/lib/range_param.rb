class RangeParam
  PRESETS = {
    "7d"    => -> { 7.days.ago.beginning_of_day.. },
    "30d"   => -> { 30.days.ago.beginning_of_day.. },
    "90d"   => -> { 90.days.ago.beginning_of_day.. },
    "month" => -> { Time.current.beginning_of_month.. }
  }.freeze
  DEFAULT = "30d"

  def self.parse(value)
    PRESETS.fetch(value.to_s, PRESETS[DEFAULT]).call
  end
end
